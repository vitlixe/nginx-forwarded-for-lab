#!/usr/bin/env bash
# Automated XFF correctness and anti-spoofing checks.
# Exit code 0 = all passed. Exit code 1 = at least one failure.
set -euo pipefail

PASS=0
FAIL=0

# ── helpers ──────────────────────────────────────────────────────────────────

ok()   { printf '  PASS  %s\n        XFF: %s\n' "$1" "$2"; PASS=$((PASS+1)); }
fail() { printf '  FAIL  %s\n        XFF: %s\n' "$1" "$2" >&2; FAIL=$((FAIL+1)); }

xff_of() {
    curl -sf "$@" | jq -r '.x_forwarded_for // ""'
}

assert_no_spoofed() {
    local label="$1"; shift
    local xff
    xff=$(xff_of "$@")
    if printf '%s' "$xff" | grep -qE '1\.2\.3\.4|5\.6\.7\.8'; then
        fail "$label (spoofed IP leaked)" "$xff"
    else
        ok "$label" "$xff"
    fi
}

assert_hop_count() {
    local label="$1"
    local expected_hops="$2"; shift 2
    local xff
    xff=$(xff_of "$@")
    # Count comma-separated entries (n commas = n+1 entries)
    local count
    count=$(printf '%s' "$xff" | awk -F',' '{print NF}')
    if [ "$count" -ne "$expected_hops" ]; then
        fail "$label (expected $expected_hops hops, got $count)" "$xff"
    else
        ok "$label" "$xff"
    fi
}

assert_suffix() {
    local label="$1"
    local expected_suffix="$2"; shift 2
    local xff
    xff=$(xff_of "$@")
    if [[ "$xff" == *"$expected_suffix" ]]; then
        ok "$label" "$xff"
    else
        fail "$label (expected suffix: $expected_suffix)" "$xff"
    fi
}

# ── wait for readiness ────────────────────────────────────────────────────────

echo "Checking service readiness..."
for port in 8081 8082 8083; do
    for i in $(seq 1 10); do
        if curl -sf "http://localhost:${port}/app" >/dev/null 2>&1; then
            break
        fi
        if [ "$i" -eq 10 ]; then
            echo "ERROR: port $port not ready after 10s" >&2
            exit 1
        fi
        sleep 1
    done
done
echo "All services ready."
echo ""

# ── 1. Direct paths (1 hop each) ──────────────────────────────────────────────

echo "=== Direct paths (user → nginxN → app) ==="

assert_hop_count "user → nginx1 → app" 2 http://localhost:8081/app
assert_hop_count "user → nginx2 → app" 2 http://localhost:8082/app
assert_hop_count "user → nginx3 → app" 2 http://localhost:8083/app

assert_suffix "direct chain includes nginx1" "172.30.0.11" http://localhost:8081/app
assert_suffix "direct chain includes nginx2" "172.30.0.12" http://localhost:8082/app
assert_suffix "direct chain includes nginx3" "172.30.0.13" http://localhost:8083/app

# ── 2. Chain paths ────────────────────────────────────────────────────────────

echo ""
echo "=== Chain paths ==="

assert_hop_count "user → nginx1 → nginx2 → app"           3 http://localhost:8081/via-nginx2
assert_hop_count "user → nginx1 → nginx2 → nginx3 → app"  4 http://localhost:8081/via-nginx2-nginx3
assert_hop_count "user → nginx2 → nginx3 → app"           3 http://localhost:8082/via-nginx3

assert_suffix "ordered chain: nginx1 → nginx2" \
    "172.30.0.11, 172.30.0.12" \
    http://localhost:8081/via-nginx2

assert_suffix "ordered chain: nginx1 → nginx2 → nginx3" \
    "172.30.0.11, 172.30.0.12, 172.30.0.13" \
    http://localhost:8081/via-nginx2-nginx3

assert_suffix "ordered chain: nginx2 → nginx3" \
    "172.30.0.12, 172.30.0.13" \
    http://localhost:8082/via-nginx3

# ── 3. Anti-spoofing ──────────────────────────────────────────────────────────

echo ""
echo "=== Anti-spoofing (spoofed header must not reach the app) ==="

assert_no_spoofed \
    "spoofed XFF → nginx1 → app" \
    -H 'X-Forwarded-For: 1.2.3.4, 5.6.7.8' http://localhost:8081/app

assert_no_spoofed \
    "spoofed XFF → nginx2 → app" \
    -H 'X-Forwarded-For: 1.2.3.4, 5.6.7.8' http://localhost:8082/app

assert_no_spoofed \
    "spoofed XFF → nginx1 → nginx2 → nginx3 → app" \
    -H 'X-Forwarded-For: 1.2.3.4, 5.6.7.8' http://localhost:8081/via-nginx2-nginx3

assert_no_spoofed \
    "spoofed XFF → nginx2 → nginx3 → app" \
    -H 'X-Forwarded-For: 1.2.3.4, 5.6.7.8' http://localhost:8082/via-nginx3

# ── summary ───────────────────────────────────────────────────────────────────

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
