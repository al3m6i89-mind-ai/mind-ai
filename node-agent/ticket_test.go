package main

import (
	"testing"
	"time"
)

func TestTicket(t *testing.T) {
	key := "0123456789abcdef0123456789abcdef"
	now := time.Unix(1_800_000_000, 0)
	tk := signTicket(key, "nv0123456789", now.Add(time.Minute))
	if !verifyTicket(key, tk, "nv0123456789", now) {
		t.Fatal("valid ticket rejected")
	}
	if verifyTicket(key, tk, "nv0123456789", now.Add(2*time.Minute)) {
		t.Fatal("expired ticket accepted")
	}
	if verifyTicket(key, tk, "nvaaaaaaaaaa", now) {
		t.Fatal("ticket accepted for another phone")
	}
	if verifyTicket("another-key-another-key-another-key", tk, "nv0123456789", now) {
		t.Fatal("ticket accepted with another key")
	}
	if verifyTicket(key, tk+"x", "nv0123456789", now) {
		t.Fatal("tampered ticket accepted")
	}
}
