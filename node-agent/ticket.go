package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"strconv"
	"strings"
	"time"
)

// A ticket is "v1.<ref>.<unix expiry>.<base64url HMAC-SHA256 of the first three parts>",
// signed with the node token. The backend issues it after checking the user may open the phone.
func signTicket(key, ref string, exp time.Time) string {
	payload := "v1." + ref + "." + strconv.FormatInt(exp.Unix(), 10)
	return payload + "." + mac(key, payload)
}

func verifyTicket(key, ticket, ref string, now time.Time) bool {
	i := strings.LastIndexByte(ticket, '.')
	if i < 0 {
		return false
	}
	payload, sig := ticket[:i], ticket[i+1:]
	if !hmac.Equal([]byte(sig), []byte(mac(key, payload))) {
		return false
	}
	parts := strings.Split(payload, ".")
	if len(parts) != 3 || parts[0] != "v1" || parts[1] != ref {
		return false
	}
	exp, err := strconv.ParseInt(parts[2], 10, 64)
	return err == nil && now.Unix() <= exp
}

func mac(key, payload string) string {
	m := hmac.New(sha256.New, []byte(key))
	m.Write([]byte(payload))
	return base64.RawURLEncoding.EncodeToString(m.Sum(nil))
}
