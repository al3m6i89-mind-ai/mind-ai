// Nuvola node agent: runs Android phones (Redroid containers) on one server and
// streams their screens. The backend is its only API client; phone apps connect
// to the stream endpoint with a short-lived ticket signed by the backend.
package main

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type Config struct {
	Token        string
	Listen       string
	MaxDevices   int
	ImageRepo    string
	Network      string
	ScrcpyServer string
	BootTimeout  time.Duration
	// Optional: report this node's address to the backend (see heartbeat.go).
	BackendURL    string
	PublicURL     string
	TunnelMetrics string
}

func loadConfig() Config {
	c := Config{
		Token:         os.Getenv("NODE_TOKEN"),
		Listen:        env("LISTEN", "127.0.0.1:7100"),
		MaxDevices:    envInt("MAX_DEVICES", 4),
		ImageRepo:     env("IMAGE_REPO", "nuvola/android"),
		Network:       env("DOCKER_NETWORK", "nuvola"),
		ScrcpyServer:  env("SCRCPY_SERVER", "/opt/nuvola/scrcpy-server"),
		BootTimeout:   time.Duration(envInt("BOOT_TIMEOUT_SECONDS", 300)) * time.Second,
		BackendURL:    os.Getenv("BACKEND_URL"),
		PublicURL:     os.Getenv("PUBLIC_URL"),
		TunnelMetrics: os.Getenv("TUNNEL_METRICS"),
	}
	if len(c.Token) < 32 {
		log.Fatal("NODE_TOKEN must be set to a random value of at least 32 characters")
	}
	return c
}

func main() {
	cfg := loadConfig()
	nodes := NewNode(cfg)
	if err := nodes.Prepare(context.Background()); err != nil {
		log.Fatalf("prepare: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) { writeJSON(w, 200, map[string]string{"status": "ok"}) })
	api := func(h http.HandlerFunc) http.HandlerFunc { return requireToken(cfg.Token, h) }
	mux.HandleFunc("GET /v1/node", api(func(w http.ResponseWriter, r *http.Request) {
		info, err := nodes.Info(r.Context())
		respond(w, info, err)
	}))
	mux.HandleFunc("POST /v1/devices", api(func(w http.ResponseWriter, r *http.Request) {
		var spec Spec
		if err := json.NewDecoder(r.Body).Decode(&spec); err != nil {
			respond(w, nil, badRequest("invalid body"))
			return
		}
		ref, err := nodes.Create(r.Context(), spec)
		respond(w, map[string]string{"ref": ref}, err)
	}))
	mux.HandleFunc("GET /v1/devices/{ref}", api(func(w http.ResponseWriter, r *http.Request) {
		state, err := nodes.State(r.Context(), r.PathValue("ref"))
		respond(w, map[string]string{"state": state}, err)
	}))
	mux.HandleFunc("POST /v1/devices/{ref}/{action}", api(func(w http.ResponseWriter, r *http.Request) {
		ref := r.PathValue("ref")
		var err error
		switch r.PathValue("action") {
		case "start":
			err = nodes.Start(r.Context(), ref)
		case "stop":
			err = nodes.Stop(r.Context(), ref)
		case "restart":
			err = nodes.Restart(r.Context(), ref)
		case "root":
			var body struct{ Enabled bool }
			if json.NewDecoder(r.Body).Decode(&body) != nil {
				err = badRequest("invalid body")
			} else {
				err = nodes.SetRoot(r.Context(), ref, body.Enabled)
			}
		default:
			err = &apiError{404, "not_found", "unknown action"}
		}
		respond(w, map[string]bool{"ok": true}, err)
	}))
	mux.HandleFunc("DELETE /v1/devices/{ref}", api(func(w http.ResponseWriter, r *http.Request) {
		respond(w, map[string]bool{"ok": true}, nodes.Destroy(r.Context(), r.PathValue("ref")))
	}))
	// Phone apps connect here directly; the ticket replaces the node token.
	mux.HandleFunc("GET /v1/stream/{ref}", func(w http.ResponseWriter, r *http.Request) {
		ref := r.PathValue("ref")
		if !verifyTicket(cfg.Token, r.URL.Query().Get("ticket"), ref, time.Now()) {
			respond(w, nil, &apiError{401, "invalid_ticket", "the stream ticket is invalid or expired"})
			return
		}
		nodes.Stream(w, r, ref)
	})

	go heartbeat(context.Background(), cfg)

	srv := &http.Server{Addr: cfg.Listen, Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	go func() {
		log.Printf("nuvola node agent listening on %s (%s, max %d phones)", cfg.Listen, runtime.GOARCH, cfg.MaxDevices)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal(err)
		}
	}()
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
}

type apiError struct {
	Status  int    `json:"-"`
	Code    string `json:"error"`
	Message string `json:"message"`
}

func (e *apiError) Error() string { return e.Code + ": " + e.Message }

func badRequest(msg string) error { return &apiError{400, "bad_request", msg} }

func respond(w http.ResponseWriter, body any, err error) {
	if err == nil {
		writeJSON(w, 200, body)
		return
	}
	var ae *apiError
	if !errors.As(err, &ae) {
		log.Printf("internal error: %v", err)
		ae = &apiError{500, "internal", err.Error()}
	}
	writeJSON(w, ae.Status, ae)
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func requireToken(token string, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		got := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if subtle.ConstantTimeCompare([]byte(got), []byte(token)) != 1 {
			respond(w, nil, &apiError{401, "unauthorized", "missing or wrong node token"})
			return
		}
		h(w, r)
	}
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if v, err := strconv.Atoi(os.Getenv(key)); err == nil {
		return v
	}
	return def
}
