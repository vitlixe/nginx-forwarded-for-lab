package main

import (
	"encoding/json"
	"log"
	"net/http"
)

type response struct {
	Path          string      `json:"path"`
	RemoteAddr    string      `json:"remote_addr"`
	XForwardedFor string      `json:"x_forwarded_for"`
	Headers       http.Header `json:"headers"`
}

func handler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	_ = enc.Encode(response{
		Path:          r.URL.Path,
		RemoteAddr:    r.RemoteAddr,
		XForwardedFor: r.Header.Get("X-Forwarded-For"),
		Headers:       r.Header,
	})
}

func main() {
	http.HandleFunc("/", handler)
	log.Println("app listening on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
