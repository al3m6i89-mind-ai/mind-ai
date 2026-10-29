#!/usr/bin/env bash
# Drives the real backend the way the app does, against a live node:
# register, subscribe, create an Android phone, open a session and check its stream, delete it.
# Needs API (backend base URL) and curl + jq.
set -euo pipefail
API=${API:-http://127.0.0.1:8080/api/v1}
j() { curl -fsS -H "Content-Type: application/json" ${TOKEN:+-H "Authorization: Bearer $TOKEN"} "$@"; }

for _ in $(seq 1 60); do curl -fsS "$API/health" >/dev/null 2>&1 && break; sleep 3; done
email="ci-$(date +%s)@example.com"
TOKEN=$(j -X POST "$API/auth/register" -d "{\"email\":\"$email\",\"password\":\"secret123\",\"displayName\":\"CI\",\"acceptTerms\":true}" | jq -r .accessToken)
catalog=$(j "$API/catalog")
echo "catalog: $catalog"
image=$(jq -r '.androidImages[] | select(.androidVersion=="13") | .id' <<<"$catalog")
region=$(jq -r '.regions[0].id' <<<"$catalog")
[ "$(jq -r '.androidImages[0].simulated' <<<"$catalog")" = false ] || { echo "catalog still simulated"; exit 1; }
plan=$(j "$API/plans" | jq -r '.[] | select(.code=="starter-day") | .id')
sub=$(j -X POST "$API/subscriptions" -d "{\"planId\":\"$plan\"}" | jq -r .id)
device=$(j -X POST "$API/devices" -H "Idempotency-Key: ci-$RANDOM$RANDOM" \
    -d "{\"subscriptionId\":\"$sub\",\"androidImageId\":\"$image\",\"regionId\":\"$region\",\"displayName\":\"CI phone\",\"rootEnabled\":false}" | jq -r .id)
echo "device $device ($image in $region)"
for i in $(seq 1 100); do
    d=$(j "$API/devices/$device")
    status=$(jq -r .status <<<"$d")
    [ "$status" = RUNNING ] && [ "$(jq -r '.pendingAction // empty' <<<"$d")" = "" ] && break
    [ "$status" = ERROR ] && { echo "device failed: $d"; exit 1; }
    sleep 5
done
[ "$status" = RUNNING ] || { echo "device never became RUNNING: $d"; exit 1; }
echo "device running"
session=$(j -X POST "$API/devices/$device/sessions")
url="$(jq -r .gatewayUrl <<<"$session")?ticket=$(jq -r .token <<<"$session")"
echo "session gateway: $(jq -r .gatewayUrl <<<"$session")"
(cd "$(dirname "$0")/.." && STREAM_URL="$url" go run ./cmd/e2e)
j -X DELETE "$API/sessions/$(jq -r .sessionId <<<"$session")" >/dev/null
j -X DELETE "$API/devices/$device" >/dev/null
for _ in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "$API/devices/$device")
    [ "$code" = 404 ] && { echo "FULL STACK PASSED"; exit 0; }
    sleep 3
done
echo "device was not deleted"; exit 1
