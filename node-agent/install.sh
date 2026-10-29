#!/usr/bin/env bash
# Turns a fresh Ubuntu 22.04/24.04 server (x86_64 or arm64) into a Nuvola phone node.
# Run as root:
#   curl -fsSL https://raw.githubusercontent.com/al3m6i89-mind-ai/mind-ai/nuvola-cloudphone/node-agent/install.sh | sudo bash
# Safe to run again: it keeps the node token and skips images that are already built.
# It also works as a cloud-init (first boot) script; pass NODE_TOKEN to choose the token in advance.
set -euo pipefail

REPO_URL=${REPO_URL:-https://github.com/al3m6i89-mind-ai/mind-ai}
REPO_BRANCH=${REPO_BRANCH:-nuvola-cloudphone}
ANDROID_VERSIONS=${ANDROID_VERSIONS:-"12 13 14"}
# 1 adds Google Play (MindTheGapps) to every image. Root images also get Magisk.
WITH_GAPPS=${WITH_GAPPS:-1}
MAX_DEVICES=${MAX_DEVICES:-auto}
DOMAIN=${DOMAIN:-}
# "cloudflare" reaches the node through a free Cloudflare quick tunnel: for a home computer
# with no public IP or open ports. Otherwise the server needs ports 80 and 443 open.
TUNNEL=${TUNNEL:-none}
# The backend the node reports its address to.
BACKEND_URL=${BACKEND_URL:-https://nuvola-api-zuhair.onrender.com/api/v1}
# For testing: build the agent from a local checkout and skip the public HTTPS setup.
AGENT_SRC=${AGENT_SRC:-}
SKIP_HTTPS=${SKIP_HTTPS:-0}
REDROID_SCRIPT_COMMIT=a4951b782fc8e06c845d9553bf07bb643fd8c158
DIR=/opt/nuvola

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || fail "Run this script as root (put sudo before bash)."
case "$(uname -m)" in x86_64|aarch64) ;; *) fail "Unsupported CPU $(uname -m); use x86_64 or arm64." ;; esac
mkdir -p "$DIR"

step "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl git python3 python3-venv openssl iptables
command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh
systemctl enable --now docker

step "Enabling Android kernel support (binder)"
if ! grep -qw binder /proc/filesystems; then
    apt-get install -y "linux-modules-extra-$(uname -r)" || true
    modprobe binder_linux devices="binder,hwbinder,vndbinder" || true
fi
grep -qw binder /proc/filesystems || fail "This kernel has no binder support, so Android cannot run here. Use an Ubuntu image from your provider (not a minimal or container-based VPS)."
echo binder_linux > /etc/modules-load.d/nuvola.conf
echo 'options binder_linux devices="binder,hwbinder,vndbinder"' > /etc/modprobe.d/nuvola.conf

step "Building Android images: $ANDROID_VERSIONS (this takes a while the first time)"
RS="$DIR/redroid-script"
if [ ! -d "$RS/.git" ]; then git clone -q https://github.com/ayasa520/redroid-script "$RS"; fi
git -C "$RS" fetch -q origin
git -C "$RS" checkout -q "$REDROID_SCRIPT_COMMIT"
[ -x "$RS/.venv/bin/python" ] || python3 -m venv "$RS/.venv"
"$RS/.venv/bin/pip" install -q -r "$RS/requirements.txt"

build_image() { # $1 version, $2 "root" or "", result tagged nuvola/android:<v>[-root]
    local v=$1 root=$2 tag="nuvola/android:$1${2:+-root}" flags=() name="redroid/redroid:$1.0.0"
    if docker image inspect "$tag" >/dev/null 2>&1; then echo "$tag already built"; return 0; fi
    if [ "$WITH_GAPPS" = 1 ]; then flags+=(-mtg); name+="_mindthegapps"; fi
    if [ -n "$root" ]; then flags+=(-m); name+="_magisk"; fi
    if [ ${#flags[@]} -eq 0 ]; then
        docker pull "redroid/redroid:$v.0.0-latest" && docker tag "redroid/redroid:$v.0.0-latest" "$tag"
        return
    fi
    (cd "$RS" && USER=root XDG_CACHE_HOME="$DIR/cache" .venv/bin/python redroid.py -a "$v.0.0" "${flags[@]}") \
        && docker image inspect "$name" >/dev/null 2>&1 \
        && docker tag "$name" "$tag" && docker rmi "$name" >/dev/null
}
built=0
for v in $ANDROID_VERSIONS; do
    if build_image "$v" ""; then
        built=$((built + 1))
        build_image "$v" root || echo "WARNING: root image for Android $v failed; phones on $v will be offered without root."
    else
        echo "WARNING: Android $v image failed to build; skipping it."
    fi
done
[ "$built" -gt 0 ] || fail "No Android image could be built. Check the messages above."

step "Building the node agent"
if [ -z "$AGENT_SRC" ]; then
    if [ ! -d "$DIR/src/.git" ]; then git clone -q --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$DIR/src"; fi
    git -C "$DIR/src" fetch -q --depth 1 origin "$REPO_BRANCH"
    git -C "$DIR/src" reset -q --hard FETCH_HEAD
    AGENT_SRC="$DIR/src/node-agent"
fi
docker build -q -t nuvola/agent "$AGENT_SRC" >/dev/null

if [ "$MAX_DEVICES" = auto ]; then
    MAX_DEVICES=$(( $(awk '/MemTotal/ {print int($2 / 1048576)}' /proc/meminfo) / 3 ))
    [ "$MAX_DEVICES" -ge 1 ] || MAX_DEVICES=1
fi
if [ ! -f "$DIR/node.env" ]; then
    echo "NODE_TOKEN=${NODE_TOKEN:-$(openssl rand -hex 32)}" > "$DIR/node.env"
fi
chmod 600 "$DIR/node.env"
set_env() { sed -i "/^$1=/d" "$DIR/node.env"; [ -z "$2" ] || echo "$1=$2" >> "$DIR/node.env"; }
set_env MAX_DEVICES "$MAX_DEVICES"
set_env BACKEND_URL "$BACKEND_URL"

if [ "$TUNNEL" = cloudflare ]; then
    set_env PUBLIC_URL ""
    set_env TUNNEL_METRICS 127.0.0.1:20241
elif [ "$SKIP_HTTPS" != 1 ]; then
    if [ -z "$DOMAIN" ]; then
        ip=$(curl -fsS https://api.ipify.org) || fail "Could not find this server's public IP address."
        DOMAIN="${ip//./-}.sslip.io"
    fi
    set_env PUBLIC_URL "https://$DOMAIN"
    set_env TUNNEL_METRICS ""
fi

step "Starting the node agent"
docker rm -f nuvola-agent >/dev/null 2>&1 || true
docker run -d --name nuvola-agent --restart unless-stopped --network host \
    -v /var/run/docker.sock:/var/run/docker.sock --env-file "$DIR/node.env" nuvola/agent >/dev/null

if [ "$SKIP_HTTPS" = 1 ] && [ "$TUNNEL" != cloudflare ]; then
    echo "Agent running on 127.0.0.1:7100 (HTTPS skipped)."
    exit 0
fi

docker rm -f nuvola-tunnel nuvola-caddy >/dev/null 2>&1 || true
if [ "$TUNNEL" = cloudflare ]; then
    # No open ports or public IP needed (home internet). The address changes on every restart;
    # the agent reports it to the backend each minute.
    step "Starting the Cloudflare tunnel"
    docker run -d --name nuvola-tunnel --restart unless-stopped --network host \
        cloudflare/cloudflared:2024.12.2 tunnel --no-autoupdate --metrics 127.0.0.1:20241 --url http://127.0.0.1:7100 >/dev/null
    host=""
    for _ in $(seq 1 30); do
        host=$(curl -fsS http://127.0.0.1:20241/quicktunnel 2>/dev/null | sed -n 's/.*"hostname":"\([^"]*\)".*/\1/p')
        [ -n "$host" ] && break
        sleep 3
    done
    [ -n "$host" ] || fail "The Cloudflare tunnel did not start. Check: docker logs nuvola-tunnel"
    DOMAIN=$host
else
    step "Opening ports 80 and 443 and setting up HTTPS"
    for port in 80 443; do
        iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport "$port" -j ACCEPT
    done
    command -v netfilter-persistent >/dev/null && netfilter-persistent save >/dev/null 2>&1 || true
    command -v ufw >/dev/null && ufw status | grep -q active && ufw allow 80,443/tcp >/dev/null || true
    printf '%s {\n    reverse_proxy 127.0.0.1:7100\n}\n' "$DOMAIN" > "$DIR/Caddyfile"
    docker run -d --name nuvola-caddy --restart unless-stopped --network host \
        -v "$DIR/Caddyfile:/etc/caddy/Caddyfile:ro" -v nuvola-caddy-data:/data caddy:2.8 >/dev/null
fi

step "Checking https://$DOMAIN"
ok=0
for _ in $(seq 1 30); do
    if curl -fsS "https://$DOMAIN/healthz" >/dev/null 2>&1; then ok=1; break; fi
    sleep 5
done
token=$(sed -n 's/^NODE_TOKEN=//p' "$DIR/node.env")
echo
if [ "$ok" = 1 ]; then
    printf '\033[1;32mNuvola node is ready at https://%s\033[0m\n\n' "$DOMAIN"
else
    printf '\033[1;33mThe node runs, but https://%s is not reachable yet.\033[0m\n' "$DOMAIN"
    [ "$TUNNEL" = cloudflare ] || printf 'Open TCP ports 80 and 443 in your cloud firewall (Oracle: VCN > Security List > Ingress rules), then run this script again.\n'
    echo
fi
printf 'Add this one setting to the backend (Render > nuvola-api-zuhair > Environment):\n\n'
printf '  REDROID_NODE_TOKEN=%s\n\n' "$token"
printf 'The node reports its address to %s every minute.\n' "$BACKEND_URL"
printf 'Images: %s\nMax phones: %s\n' "$(docker image ls --format '{{.Tag}}' nuvola/android | sort | tr '\n' ' ')" "$MAX_DEVICES"
