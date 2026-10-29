package main

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/coder/websocket"
)

// The stream bridges one phone-app WebSocket to a scrcpy server running inside Android.
//
// Agent -> app: first a text message {"type":"meta",...}, then one binary message per
// video packet: the 12-byte scrcpy frame header (u64 pts with flags, u32 size) and the H.264 data.
// App -> agent: binary scrcpy control messages (touch, keys, text, scroll), forwarded as-is
// after a type check.
const (
	scrcpyVersion = "2.7"
	deviceJar     = "/data/local/tmp/nuvola-scrcpy.jar"
	maxPacket     = 8 << 20
)

// Control message types the app may send (scrcpy 2.7 numbering). Clipboard reads,
// UHID and the rest stay closed.
var allowedControl = map[byte]bool{0: true, 1: true, 2: true, 3: true, 4: true, 5: true, 6: true, 7: true, 11: true}

type streamMeta struct {
	Type       string `json:"type"`
	Codec      string `json:"codec"`
	Width      int    `json:"width"`
	Height     int    `json:"height"`
	DeviceName string `json:"deviceName"`
}

func (n *Node) Stream(w http.ResponseWriter, r *http.Request, ref string) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	serial, err := n.serial(ctx, ref)
	if err != nil {
		respond(w, nil, err)
		return
	}
	ws, err := websocket.Accept(w, r, nil)
	if err != nil {
		return
	}
	ws.SetReadLimit(1 << 16)
	defer ws.CloseNow()

	sess, err := startScrcpy(ctx, serial, n.cfg.ScrcpyServer, n.maxFps(ctx, ref))
	if err != nil {
		log.Printf("stream %s: %v", ref, err)
		ws.Close(websocket.StatusInternalError, "could not start the screen stream")
		return
	}
	defer sess.close()
	log.Printf("stream %s: started %dx%d", ref, sess.meta.Width, sess.meta.Height)

	meta, _ := json.Marshal(sess.meta)
	if err := ws.Write(ctx, websocket.MessageText, meta); err != nil {
		return
	}
	go func() { // video: device -> app
		defer cancel()
		header := make([]byte, 12)
		for {
			if _, err := io.ReadFull(sess.video, header); err != nil {
				return
			}
			size := binary.BigEndian.Uint32(header[8:])
			if size > maxPacket {
				return
			}
			packet := make([]byte, 12+int(size))
			copy(packet, header)
			if _, err := io.ReadFull(sess.video, packet[12:]); err != nil {
				return
			}
			wctx, wcancel := context.WithTimeout(ctx, 10*time.Second)
			err := ws.Write(wctx, websocket.MessageBinary, packet)
			wcancel()
			if err != nil {
				return
			}
		}
	}()
	go func() { // device messages (clipboard etc.) are not forwarded
		defer cancel()
		_, _ = io.Copy(io.Discard, sess.control)
	}()
	go func() { // control: app -> device
		defer cancel()
		for {
			typ, msg, err := ws.Read(ctx)
			if err != nil {
				return
			}
			if typ != websocket.MessageBinary || len(msg) == 0 || !allowedControl[msg[0]] {
				continue
			}
			if _, err := sess.control.Write(msg); err != nil {
				return
			}
		}
	}()
	<-ctx.Done()
	ws.Close(websocket.StatusNormalClosure, "")
	log.Printf("stream %s: ended", ref)
}

func (n *Node) maxFps(ctx context.Context, ref string) int {
	if s, err := n.spec(ctx, ref); err == nil && s.Fps > 0 {
		return s.Fps
	}
	return 30
}

type scrcpySession struct {
	serial  string
	port    int
	cmd     *exec.Cmd
	video   net.Conn
	control net.Conn
	meta    streamMeta
}

func startScrcpy(ctx context.Context, serial, serverJar string, fps int) (*scrcpySession, error) {
	if _, err := run(ctx, "adb", "connect", serial); err != nil {
		return nil, err
	}
	if _, err := run(ctx, "adb", "-s", serial, "push", serverJar, deviceJar); err != nil {
		return nil, err
	}
	scid := randomScid()
	port, err := freePort()
	if err != nil {
		return nil, err
	}
	s := &scrcpySession{serial: serial, port: port}
	if _, err := run(ctx, "adb", "-s", serial, "forward", "tcp:"+strconv.Itoa(port), "localabstract:scrcpy_"+scid); err != nil {
		return nil, err
	}
	args := []string{
		"CLASSPATH=" + deviceJar, "app_process", "/", "com.genymobile.scrcpy.Server", scrcpyVersion,
		"scid=" + scid, "log_level=info", "tunnel_forward=true", "audio=false", "control=true", "cleanup=true",
		"video_codec=h264", "max_size=1280", "max_fps=" + strconv.Itoa(fps), "video_bit_rate=4000000",
		"send_device_meta=true", "send_frame_meta=true", "send_dummy_byte=true", "send_codec_meta=true",
	}
	s.cmd = exec.CommandContext(ctx, "adb", "-s", serial, "shell", strings.Join(args, " "))
	if err := s.cmd.Start(); err != nil {
		s.close()
		return nil, err
	}
	if s.video, err = dialScrcpy(ctx, port, true); err != nil {
		s.close()
		return nil, err
	}
	if s.control, err = dialScrcpy(ctx, port, false); err != nil {
		s.close()
		return nil, err
	}
	head := make([]byte, 64+12)
	_ = s.video.SetReadDeadline(time.Now().Add(15 * time.Second))
	if _, err := io.ReadFull(s.video, head); err != nil {
		s.close()
		return nil, fmt.Errorf("reading stream header: %w", err)
	}
	_ = s.video.SetReadDeadline(time.Time{})
	codec := head[64:68]
	if string(codec) != "h264" {
		s.close()
		return nil, fmt.Errorf("unexpected codec %x", codec)
	}
	s.meta = streamMeta{
		Type:       "meta",
		Codec:      "h264",
		Width:      int(binary.BigEndian.Uint32(head[68:72])),
		Height:     int(binary.BigEndian.Uint32(head[72:76])),
		DeviceName: strings.TrimRight(string(head[:64]), "\x00"),
	}
	return s, nil
}

// dialScrcpy connects through the adb forward. adb accepts the TCP connection even before the
// server listens, so the first socket waits for scrcpy's dummy byte to know it is really there.
func dialScrcpy(ctx context.Context, port int, expectDummy bool) (net.Conn, error) {
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		conn, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(port), 2*time.Second)
		if err == nil {
			if !expectDummy {
				return conn, nil
			}
			b := make([]byte, 1)
			_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
			if _, err := io.ReadFull(conn, b); err == nil {
				_ = conn.SetReadDeadline(time.Time{})
				return conn, nil
			}
			conn.Close()
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(200 * time.Millisecond):
		}
	}
	return nil, fmt.Errorf("scrcpy server did not start")
}

func (s *scrcpySession) close() {
	if s.video != nil {
		s.video.Close()
	}
	if s.control != nil {
		s.control.Close()
	}
	if s.cmd != nil && s.cmd.Process != nil {
		_ = s.cmd.Process.Kill()
		_ = s.cmd.Wait()
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_, _ = run(ctx, "adb", "-s", s.serial, "forward", "--remove", "tcp:"+strconv.Itoa(s.port))
}

func randomScid() string {
	b := make([]byte, 4)
	_, _ = rand.Read(b)
	return fmt.Sprintf("%08x", binary.BigEndian.Uint32(b)&0x7fffffff)
}

func freePort() (int, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return 0, err
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port, nil
}
