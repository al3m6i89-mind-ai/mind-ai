// End-to-end check of a live node: creates a real Android phone, streams its screen,
// sends touches and keys, stops, starts, switches root and deletes it. Used by CI.
//
//	NODE_URL=http://127.0.0.1:7100 NODE_TOKEN=... go run ./cmd/e2e
package main

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/coder/websocket"
)

var (
	nodeURL = strings.TrimRight(os.Getenv("NODE_URL"), "/")
	token   = os.Getenv("NODE_TOKEN")
	version = envOr("ANDROID_VERSION", "13")
)

func main() {
	log.SetFlags(log.Ltime)
	// Full-stack mode: the backend issued the session; only check the stream it points to.
	if u := os.Getenv("STREAM_URL"); u != "" {
		stream(u)
		log.Print("STREAM CHECK PASSED")
		return
	}
	var node struct {
		Arch     string
		Versions []struct {
			Version       string
			RootAvailable bool
		}
	}
	must(call("GET", "/v1/node", nil, &node, time.Minute))
	log.Printf("node: %+v", node)

	var created struct{ Ref string }
	start := time.Now()
	must(call("POST", "/v1/devices", map[string]any{
		"version": version, "root": false, "cpus": 2, "ramMb": 3072,
		"width": 720, "height": 1280, "dpi": 320, "fps": 30,
	}, &created, 8*time.Minute))
	ref := created.Ref
	log.Printf("created %s, booted in %s", ref, time.Since(start).Round(time.Second))
	expectState(ref, "RUNNING")

	// A wrong ticket must be refused before any stream starts.
	resp, err := http.Get(nodeURL + "/v1/stream/" + ref + "?ticket=v1." + ref + ".9999999999.bad")
	must(err)
	resp.Body.Close()
	if resp.StatusCode != 401 {
		log.Fatalf("forged ticket: want 401, got %d", resp.StatusCode)
	}
	stream(streamURL(ref))
	if os.Getenv("CHECK_GAPPS") == "1" {
		if out := adbShell(ref, "pm list packages com.android.vending"); !strings.Contains(out, "com.android.vending") {
			log.Fatalf("Google Play is not installed: %q", out)
		}
		log.Print("Google Play installed")
	}
	if path := os.Getenv("SCREENSHOT"); path != "" {
		screenshot(ref, path)
	}

	must(call("POST", "/v1/devices/"+ref+"/stop", nil, nil, 2*time.Minute))
	expectState(ref, "STOPPED")
	must(call("POST", "/v1/devices/"+ref+"/start", nil, nil, 6*time.Minute))
	expectState(ref, "RUNNING")
	log.Print("stop and start ok")

	for _, v := range node.Versions {
		if v.Version == version && v.RootAvailable {
			must(call("POST", "/v1/devices/"+ref+"/root", map[string]bool{"enabled": true}, nil, 6*time.Minute))
			expectState(ref, "RUNNING")
			if os.Getenv("CHECK_MAGISK") == "1" {
				deadline := time.Now().Add(2 * time.Minute)
				for strings.TrimSpace(adbShell(ref, "pidof magiskd")) == "" {
					if time.Now().After(deadline) {
						log.Fatal("Magisk daemon is not running on the root image")
					}
					time.Sleep(5 * time.Second)
				}
				log.Print("Magisk running")
			}
			must(call("POST", "/v1/devices/"+ref+"/root", map[string]bool{"enabled": false}, nil, 6*time.Minute))
			expectState(ref, "RUNNING")
			log.Print("root switch ok")
		}
	}

	must(call("DELETE", "/v1/devices/"+ref, nil, nil, 2*time.Minute))
	expectState(ref, "MISSING")
	log.Print("ALL CHECKS PASSED")
}

// stream opens the screen like the phone app does and checks real H.264 video arrives
// and that input is accepted.
func streamURL(ref string) string {
	exp := strconv.FormatInt(time.Now().Add(time.Minute).Unix(), 10)
	payload := "v1." + ref + "." + exp
	m := hmac.New(sha256.New, []byte(token))
	m.Write([]byte(payload))
	ticket := payload + "." + base64.RawURLEncoding.EncodeToString(m.Sum(nil))
	return strings.Replace(nodeURL, "http", "ws", 1) + "/v1/stream/" + ref + "?ticket=" + ticket
}

func stream(wsURL string) {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	ws, _, err := websocket.Dial(ctx, wsURL, nil)
	must(err)
	defer ws.CloseNow()
	ws.SetReadLimit(16 << 20)

	typ, msg, err := ws.Read(ctx)
	must(err)
	var meta struct {
		Codec         string
		Width, Height int
	}
	if typ != websocket.MessageText || json.Unmarshal(msg, &meta) != nil || meta.Codec != "h264" || meta.Width == 0 {
		log.Fatalf("bad stream meta: %s", msg)
	}
	log.Printf("stream meta: %s", msg)

	var config, key, frames int
	var bytesIn int
	touched := false
	for frames < 60 || key == 0 {
		typ, msg, err := ws.Read(ctx)
		if err != nil {
			log.Fatalf("stream ended early (config=%d key=%d frames=%d): %v", config, key, frames, err)
		}
		if typ != websocket.MessageBinary || len(msg) < 12 {
			log.Fatal("bad video packet")
		}
		flags := binary.BigEndian.Uint64(msg)
		size := binary.BigEndian.Uint32(msg[8:])
		if int(size) != len(msg)-12 {
			log.Fatalf("packet size %d but %d bytes", size, len(msg)-12)
		}
		bytesIn += len(msg)
		switch {
		case flags&(1<<63) != 0:
			config++
		case flags&(1<<62) != 0:
			key++
			frames++
		default:
			frames++
		}
		if key > 0 && !touched {
			touched = true
			x, y := meta.Width/2, meta.Height/2
			must(ws.Write(ctx, websocket.MessageBinary, touch(0, x, y, meta.Width, meta.Height)))
			must(ws.Write(ctx, websocket.MessageBinary, touch(1, x, y, meta.Width, meta.Height)))
			must(ws.Write(ctx, websocket.MessageBinary, key3(0, 3))) // HOME down
			must(ws.Write(ctx, websocket.MessageBinary, key3(1, 3))) // HOME up
		}
	}
	if config == 0 {
		log.Fatal("no codec config packet received")
	}
	log.Printf("stream ok: %d config, %d key frames, %d frames, %d KB", config, key, frames, bytesIn/1024)
	ws.Close(websocket.StatusNormalClosure, "")
}

// touch builds a scrcpy 2.7 INJECT_TOUCH_EVENT message (32 bytes).
func touch(action byte, x, y, w, h int) []byte {
	b := new(bytes.Buffer)
	b.WriteByte(2)
	b.WriteByte(action)
	binary.Write(b, binary.BigEndian, int64(0))
	binary.Write(b, binary.BigEndian, int32(x))
	binary.Write(b, binary.BigEndian, int32(y))
	binary.Write(b, binary.BigEndian, uint16(w))
	binary.Write(b, binary.BigEndian, uint16(h))
	binary.Write(b, binary.BigEndian, uint16(0xffff))
	binary.Write(b, binary.BigEndian, int32(0))
	binary.Write(b, binary.BigEndian, int32(0))
	return b.Bytes()
}

// key3 builds a scrcpy INJECT_KEYCODE message (14 bytes).
func key3(action byte, keycode int32) []byte {
	b := new(bytes.Buffer)
	b.WriteByte(0)
	b.WriteByte(action)
	binary.Write(b, binary.BigEndian, keycode)
	binary.Write(b, binary.BigEndian, int32(0))
	binary.Write(b, binary.BigEndian, int32(0))
	return b.Bytes()
}

func screenshot(ref, path string) {
	png, err := exec.Command("docker", "exec", "nuvola-agent", "adb", "-s", serial(ref), "exec-out", "screencap", "-p").Output()
	must(err)
	must(os.WriteFile(path, png, 0o644))
	log.Printf("screenshot saved (%d KB)", len(png)/1024)
}

func adbShell(ref, cmd string) string {
	out, _ := exec.Command("docker", "exec", "nuvola-agent", "adb", "-s", serial(ref), "shell", cmd).CombinedOutput()
	return string(out)
}

func serial(ref string) string {
	ip, err := exec.Command("docker", "inspect", "--format", "{{.NetworkSettings.Networks.nuvola.IPAddress}}", "nuvola-"+ref).Output()
	must(err)
	return strings.TrimSpace(string(ip)) + ":5555"
}

func expectState(ref, want string) {
	var s struct{ State string }
	must(call("GET", "/v1/devices/"+ref, nil, &s, time.Minute))
	if s.State != want {
		log.Fatalf("state of %s: want %s, got %s", ref, want, s.State)
	}
}

func call(method, path string, body, out any, timeout time.Duration) error {
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, nodeURL+path, rd)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	resp, err := (&http.Client{Timeout: timeout}).Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return fmt.Errorf("%s %s: %d %s", method, path, resp.StatusCode, data)
	}
	if out != nil {
		return json.Unmarshal(data, out)
	}
	return nil
}

func must(err error) {
	if err != nil {
		log.Fatal(err)
	}
}

func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
