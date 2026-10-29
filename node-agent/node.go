package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"os/exec"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Spec is what the backend asks for; it is stored on the container as a label so the
// agent stays stateless and can recreate a phone (for the root switch) with the same settings.
type Spec struct {
	Version string `json:"version"`
	Root    bool   `json:"root"`
	Cpus    int    `json:"cpus"`
	RamMb   int    `json:"ramMb"`
	Width   int    `json:"width"`
	Height  int    `json:"height"`
	Dpi     int    `json:"dpi"`
	Fps     int    `json:"fps"`
}

type VersionInfo struct {
	Version string `json:"version"`
	Root    bool   `json:"rootAvailable"`
}

type NodeInfo struct {
	Arch       string        `json:"arch"`
	MaxDevices int           `json:"maxDevices"`
	Devices    int           `json:"devices"`
	Versions   []VersionInfo `json:"versions"`
}

var refPattern = regexp.MustCompile(`^nv[0-9a-f]{10}$`)

type Node struct {
	cfg      Config
	locks    sync.Map   // ref -> *sync.Mutex; one lifecycle operation per phone at a time
	createMu sync.Mutex // keeps the capacity check and the container start together
}

func NewNode(cfg Config) *Node { return &Node{cfg: cfg} }

func (n *Node) Prepare(ctx context.Context) error {
	if _, err := run(ctx, "docker", "network", "inspect", n.cfg.Network); err != nil {
		if _, err := run(ctx, "docker", "network", "create", n.cfg.Network); err != nil {
			return err
		}
	}
	_, err := run(ctx, "adb", "start-server")
	return err
}

func (n *Node) Info(ctx context.Context) (NodeInfo, error) {
	versions, err := n.versions(ctx)
	if err != nil {
		return NodeInfo{}, err
	}
	count, err := n.count(ctx)
	if err != nil {
		return NodeInfo{}, err
	}
	list := make([]VersionInfo, 0, len(versions))
	for v, root := range versions {
		list = append(list, VersionInfo{v, root})
	}
	sort.Slice(list, func(i, j int) bool { return list[i].Version < list[j].Version })
	return NodeInfo{runtime.GOARCH, n.cfg.MaxDevices, count, list}, nil
}

func (n *Node) Create(ctx context.Context, spec Spec) (string, error) {
	if err := n.checkSpec(ctx, spec); err != nil {
		return "", err
	}
	ref := newRef()
	unlock := n.lock(ref)
	defer unlock()
	if err := n.reserve(ctx, ref, spec); err != nil {
		return "", err
	}
	if err := n.waitBoot(ctx, ref); err != nil {
		n.remove(ref)
		return "", err
	}
	log.Printf("created %s (Android %s, root=%v)", ref, spec.Version, spec.Root)
	return ref, nil
}

func (n *Node) reserve(ctx context.Context, ref string, spec Spec) error {
	n.createMu.Lock()
	defer n.createMu.Unlock()
	count, err := n.count(ctx)
	if err != nil {
		return err
	}
	if count >= n.cfg.MaxDevices {
		return &apiError{409, "no_capacity", fmt.Sprintf("this server already runs %d phones", count)}
	}
	if err := n.runContainer(ctx, ref, spec); err != nil {
		n.remove(ref)
		return err
	}
	return nil
}

func (n *Node) State(ctx context.Context, ref string) (string, error) {
	if !refPattern.MatchString(ref) {
		return "", badRequest("invalid ref")
	}
	status, err := n.status(ctx, ref)
	if err != nil {
		return "", err
	}
	switch status {
	case "":
		return "MISSING", nil
	case "running":
		return "RUNNING", nil
	case "exited", "created":
		return "STOPPED", nil
	default:
		return "UNKNOWN", nil
	}
}

func (n *Node) Start(ctx context.Context, ref string) error {
	unlock, err := n.existing(ctx, ref)
	if err != nil {
		return err
	}
	defer unlock()
	if _, err := run(ctx, "docker", "start", container(ref)); err != nil {
		return err
	}
	return n.waitBoot(ctx, ref)
}

func (n *Node) Stop(ctx context.Context, ref string) error {
	unlock, err := n.existing(ctx, ref)
	if err != nil {
		return err
	}
	defer unlock()
	n.disconnect(ctx, ref)
	_, err = run(ctx, "docker", "stop", "-t", "30", container(ref))
	return err
}

func (n *Node) Restart(ctx context.Context, ref string) error {
	unlock, err := n.existing(ctx, ref)
	if err != nil {
		return err
	}
	defer unlock()
	n.disconnect(ctx, ref)
	if _, err := run(ctx, "docker", "restart", "-t", "30", container(ref)); err != nil {
		return err
	}
	return n.waitBoot(ctx, ref)
}

// SetRoot swaps the system image (with or without Magisk) and keeps the phone's /data volume,
// so apps and files survive. The phone returns to the power state it had before.
func (n *Node) SetRoot(ctx context.Context, ref string, enabled bool) error {
	unlock, err := n.existing(ctx, ref)
	if err != nil {
		return err
	}
	defer unlock()
	spec, err := n.spec(ctx, ref)
	if err != nil {
		return err
	}
	if spec.Root == enabled {
		return nil
	}
	spec.Root = enabled
	if err := n.checkSpec(ctx, spec); err != nil {
		return err
	}
	status, err := n.status(ctx, ref)
	if err != nil {
		return err
	}
	n.disconnect(ctx, ref)
	if _, err := run(ctx, "docker", "rm", "-f", container(ref)); err != nil {
		return err
	}
	if err := n.runContainer(ctx, ref, spec); err != nil {
		return err
	}
	if status != "running" {
		_, err = run(ctx, "docker", "stop", "-t", "30", container(ref))
		return err
	}
	return n.waitBoot(ctx, ref)
}

func (n *Node) Destroy(ctx context.Context, ref string) error {
	if !refPattern.MatchString(ref) {
		return badRequest("invalid ref")
	}
	unlock := n.lock(ref)
	defer unlock()
	n.disconnect(ctx, ref)
	return n.remove(ref)
}

func (n *Node) runContainer(ctx context.Context, ref string, spec Spec) error {
	label, _ := json.Marshal(spec)
	cpus := min(max(spec.Cpus, 1), runtime.NumCPU())
	args := []string{"run", "-d", "--privileged",
		"--name", container(ref),
		"--network", n.cfg.Network,
		"--restart", "unless-stopped",
		"--label", "nuvola.ref=" + ref,
		"--label", "nuvola.spec=" + string(label),
		"-v", volume(ref) + ":/data",
		"--cpus", strconv.Itoa(cpus),
		"--memory", strconv.Itoa(max(spec.RamMb, 1024)) + "m",
		n.image(spec),
		"androidboot.redroid_width=" + strconv.Itoa(spec.Width),
		"androidboot.redroid_height=" + strconv.Itoa(spec.Height),
		"androidboot.redroid_dpi=" + strconv.Itoa(spec.Dpi),
		"androidboot.redroid_fps=" + strconv.Itoa(min(max(spec.Fps, 10), 60)),
		"androidboot.redroid_gpu_mode=guest",
		"androidboot.use_memfd=true",
	}
	_, err := run(ctx, "docker", args...)
	return err
}

// waitBoot connects adb and waits for Android to finish booting, then keeps the display awake
// so the stream never shows a sleeping screen.
func (n *Node) waitBoot(ctx context.Context, ref string) error {
	ctx, cancel := context.WithTimeout(ctx, n.cfg.BootTimeout)
	defer cancel()
	for {
		if serial, err := n.serial(ctx, ref); err == nil {
			_, _ = run(ctx, "adb", "connect", serial)
			out, err := run(ctx, "adb", "-s", serial, "shell", "getprop", "sys.boot_completed")
			if err == nil && strings.TrimSpace(out) == "1" {
				_, _ = run(ctx, "adb", "-s", serial, "shell", "svc power stayon true; settings put system screen_off_timeout 2147483647")
				return nil
			}
		}
		select {
		case <-ctx.Done():
			return &apiError{504, "boot_timeout", "Android did not finish booting in time"}
		case <-time.After(3 * time.Second):
		}
	}
}

func (n *Node) serial(ctx context.Context, ref string) (string, error) {
	out, err := run(ctx, "docker", "inspect", "--format",
		fmt.Sprintf(`{{(index .NetworkSettings.Networks %q).IPAddress}}`, n.cfg.Network), container(ref))
	ip := strings.TrimSpace(out)
	if err != nil || ip == "" {
		return "", &apiError{409, "not_running", "the phone is not running"}
	}
	return ip + ":5555", nil
}

func (n *Node) disconnect(ctx context.Context, ref string) {
	if serial, err := n.serial(ctx, ref); err == nil {
		_, _ = run(ctx, "adb", "disconnect", serial)
	}
}

func (n *Node) remove(ref string) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	if out, err := run(ctx, "docker", "rm", "-f", container(ref)); err != nil && !strings.Contains(out, "No such container") {
		return err
	}
	if out, err := run(ctx, "docker", "volume", "rm", "-f", volume(ref)); err != nil && !strings.Contains(out, "no such volume") {
		return err
	}
	return nil
}

func (n *Node) status(ctx context.Context, ref string) (string, error) {
	out, err := run(ctx, "docker", "inspect", "--format", "{{.State.Status}}", container(ref))
	if err != nil {
		if strings.Contains(out, "No such") {
			return "", nil
		}
		return "", err
	}
	return strings.TrimSpace(out), nil
}

func (n *Node) spec(ctx context.Context, ref string) (Spec, error) {
	out, err := run(ctx, "docker", "inspect", "--format", `{{index .Config.Labels "nuvola.spec"}}`, container(ref))
	if err != nil {
		return Spec{}, err
	}
	var s Spec
	err = json.Unmarshal([]byte(strings.TrimSpace(out)), &s)
	return s, err
}

// existing validates the ref, takes the phone's lock and checks the container is there.
func (n *Node) existing(ctx context.Context, ref string) (func(), error) {
	if !refPattern.MatchString(ref) {
		return nil, badRequest("invalid ref")
	}
	unlock := n.lock(ref)
	status, err := n.status(ctx, ref)
	if err == nil && status == "" {
		err = &apiError{404, "not_found", "no such phone on this server"}
	}
	if err != nil {
		unlock()
		return nil, err
	}
	return unlock, nil
}

func (n *Node) checkSpec(ctx context.Context, spec Spec) error {
	if spec.Width < 320 || spec.Height < 320 || spec.Width > 2160 || spec.Height > 3840 || spec.Dpi < 120 || spec.Dpi > 640 {
		return badRequest("unsupported screen settings")
	}
	versions, err := n.versions(ctx)
	if err != nil {
		return err
	}
	root, ok := versions[spec.Version]
	if !ok {
		return &apiError{422, "image_not_available", "Android " + spec.Version + " is not installed on this server"}
	}
	if spec.Root && !root {
		return &apiError{422, "root_not_available", "Android " + spec.Version + " has no root image on this server"}
	}
	return nil
}

// versions lists installed images: tag "13" is the stock system, "13-root" the same with Magisk.
func (n *Node) versions(ctx context.Context) (map[string]bool, error) {
	out, err := run(ctx, "docker", "image", "ls", "--format", "{{.Tag}}", n.cfg.ImageRepo)
	if err != nil {
		return nil, err
	}
	tags := strings.Fields(out)
	result := map[string]bool{}
	for _, t := range tags {
		if !strings.HasSuffix(t, "-root") {
			result[t] = false
		}
	}
	for _, t := range tags {
		if v, ok := strings.CutSuffix(t, "-root"); ok {
			if _, base := result[v]; base {
				result[v] = true
			}
		}
	}
	return result, nil
}

func (n *Node) image(spec Spec) string {
	if spec.Root {
		return n.cfg.ImageRepo + ":" + spec.Version + "-root"
	}
	return n.cfg.ImageRepo + ":" + spec.Version
}

func (n *Node) count(ctx context.Context) (int, error) {
	out, err := run(ctx, "docker", "ps", "-a", "--filter", "label=nuvola.ref", "--format", "{{.Names}}")
	return len(strings.Fields(out)), err
}

func (n *Node) lock(ref string) func() {
	m, _ := n.locks.LoadOrStore(ref, &sync.Mutex{})
	mu := m.(*sync.Mutex)
	mu.Lock()
	return mu.Unlock
}

func container(ref string) string { return "nuvola-" + ref }
func volume(ref string) string    { return "nuvola-data-" + ref }

func newRef() string {
	b := make([]byte, 5)
	_, _ = rand.Read(b)
	return "nv" + hex.EncodeToString(b)
}

// run executes a command and returns its combined output; the error carries that output.
func run(ctx context.Context, name string, args ...string) (string, error) {
	var buf bytes.Buffer
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	err := cmd.Run()
	out := buf.String()
	if err != nil {
		return out, fmt.Errorf("%s %s: %v: %s", name, args[0], err, strings.TrimSpace(out))
	}
	return out, nil
}
