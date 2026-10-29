package main

import (
	"bytes"
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"time"
)

// heartbeat tells the backend where this node can be reached, every minute. The address is
// PUBLIC_URL when set, or the hostname of a Cloudflare quick tunnel, which changes on every restart.
func heartbeat(ctx context.Context, cfg Config) {
	if cfg.BackendURL == "" {
		return
	}
	client := &http.Client{Timeout: 90 * time.Second} // a sleeping free backend can take a minute to wake
	last := ""
	for {
		url := cfg.PublicURL
		if url == "" && cfg.TunnelMetrics != "" {
			url = tunnelURL(client, cfg.TunnelMetrics)
		}
		if url != "" {
			body, _ := json.Marshal(map[string]string{"url": url})
			req, _ := http.NewRequestWithContext(ctx, "POST", strings.TrimRight(cfg.BackendURL, "/")+"/nodes/heartbeat", bytes.NewReader(body))
			req.Header.Set("Content-Type", "application/json")
			req.Header.Set("X-Node-Token", cfg.Token)
			resp, err := client.Do(req)
			switch {
			case err != nil:
				log.Printf("heartbeat: %v", err)
			case resp.StatusCode != http.StatusNoContent:
				log.Printf("heartbeat: backend answered %d (check REDROID_NODE_TOKEN on the backend)", resp.StatusCode)
			case url != last:
				log.Printf("heartbeat: backend knows this node as %s", url)
				last = url
			}
			if resp != nil {
				resp.Body.Close()
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(time.Minute):
		}
	}
}

func tunnelURL(client *http.Client, metrics string) string {
	resp, err := client.Get("http://" + metrics + "/quicktunnel")
	if err != nil {
		return ""
	}
	defer resp.Body.Close()
	var t struct{ Hostname string }
	if json.NewDecoder(resp.Body).Decode(&t) != nil || t.Hostname == "" {
		return ""
	}
	return "https://" + t.Hostname
}
