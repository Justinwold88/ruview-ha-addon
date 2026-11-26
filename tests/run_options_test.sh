#!/usr/bin/env bash
# Tests for ruview/rootfs/usr/local/bin/ruview-run.
#
# Each case writes an options.json, runs the script with RUVIEW_DRY_RUN=1
# and checks the server arguments and environment it would use. A fake
# `curl` on PATH stands in for the Supervisor's /services/mqtt endpoint.
# Needs bash and jq. Run: tests/run_options_test.sh
#
# `check && ok || bad` is safe in this file: ok and bad always return 0.
# shellcheck disable=SC2015
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../ruview/rootfs/usr/local/bin/ruview-run"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0
current=""

# Fake curl: answers /services/mqtt from $FAKE_SERVICE (a file), records
# that it was called, and fails like `curl -f` when FAKE_SERVICE_FAIL=1.
mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'EOF'
#!/bin/sh
echo called >> "$FAKE_CURL_LOG"
url=""
auth=""
prev=""
for a in "$@"; do
    [ "$prev" = "-H" ] && auth="$a"
    case "$a" in http*://*) url="$a" ;; esac
    prev="$a"
done
[ "${FAKE_SERVICE_FAIL:-0}" = 1 ] && exit 22
[ "$auth" = "Authorization: Bearer test-supervisor-token" ] || exit 22
case "$url" in
    */services/mqtt) cat "$FAKE_SERVICE" ;;
    */info) [ -f "$FAKE_INFO" ] && cat "$FAKE_INFO" || exit 22 ;;
    *) exit 22 ;;
esac
EOF
chmod +x "$work/bin/curl"

defaults='{"csi_source":"esp32","udp_allow":[],"udp_insecure_lan":false,"mqtt":true,"allowed_hosts":[],
"trusted_network":false,"privacy_mode":false,"publish_heart_rate":false,
"publish_fall":false,"log_level":"info"}'

# run_case NAME JSON_PATCH [ENV...]: merge the patch into the defaults, run
# the script, and keep stdout in $out, stderr in $err and the exit code in $rc.
run_case() {
    current="$1"
    local patch="$2"
    shift 2
    printf '%s' "$defaults" | jq --argjson p "$patch" '. + $p' > "$work/options.json"
    : > "$work/curl.log"
    rc=0
    env -i PATH="$work/bin:/usr/bin:/bin" \
        RUVIEW_OPTIONS_FILE="$work/options.json" RUVIEW_DATA_DIR=/data \
        RUVIEW_DRY_RUN=1 FAKE_CURL_LOG="$work/curl.log" \
        FAKE_SERVICE="$work/service.json" FAKE_INFO="$work/info.json" "$@" \
        sh "$script" > "$work/out" 2> "$work/err" || rc=$?
    out="$(cat "$work/out")"
    err="$(cat "$work/err")"
}

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL [%s]: %s\n' "$current" "$*"; }
has() { grep -qxF -- "$1" <<<"$out" && ok || bad "missing line: $1"; }
lacks() { grep -qxF -- "$1" <<<"$out" && bad "unexpected line: $1" || ok; }
says() { grep -qF -- "$1" <<<"$err" && ok || bad "log lacks: $1"; }
never() { grep -qF -- "$1" <<<"$out$err" && bad "secret leaked: $1" || ok; }
exits() { [ "$rc" = "$1" ] && ok || bad "exit $rc, expected $1"; }
args_after() {
    # The value that follows flag $1 in the argument list.
    grep -A1 -xF "ARG=$1" <<<"$out" | sed -n 2p | sed 's/^ARG=//'
}
curl_calls() { wc -l < "$work/curl.log" | tr -d ' '; }

# ── Defaults: safe, quiet about what is missing ───────────────────────────
run_case "defaults" '{}'
exits 0
has "SERVER=/app/sensing-server"
[ "$(args_after --source)" = esp32 ] && ok || bad "source"
[ "$(args_after --bind-addr)" = 127.0.0.1 ] && ok || bad "HTTP must stay inside the app"
[ "$(args_after --data-dir)" = /data ] && ok || bad "data dir"
has "ARG=--no-edge-registry"
lacks "ARG=--udp-bind"
lacks "ARG=--mqtt"
has "ENV RUVIEW_API_TOKEN=unset"
has "ENV RUVIEW_ALLOW_UNAUTHENTICATED=unset"
has "ENV RUST_LOG=info"
says "no ESP32 node will be heard"
says "no broker was found"
says "kept inside the app"
[ "$(curl_calls)" = 0 ] && ok || bad "no Supervisor token, so no Supervisor call"

# ── Token opens HTTP; allow-list opens UDP; the token is never printed ─────
run_case "token and allow-list" \
    '{"api_token":"s3cret-token-value","udp_allow":["192.168.1.0/24","10.0.0.5"]}'
exits 0
[ "$(args_after --bind-addr)" = 0.0.0.0 ] && ok || bad "HTTP bind with token"
has "ENV RUVIEW_API_TOKEN=set"
has "ENV RUVIEW_ALLOW_UNAUTHENTICATED=unset"
[ "$(grep -cxF 'ARG=--udp-allow' <<<"$out")" = 2 ] && ok || bad "one --udp-allow per entry"
has "ARG=192.168.1.0/24"
has "ARG=10.0.0.5"
[ "$(args_after --udp-bind)" = 0.0.0.0 ] && ok || bad "UDP bind with allow-list"
lacks "ARG=--udp-insecure-lan"
never "s3cret-token-value"

# ── Web UI addresses: from the options, plus the Supervisor's host name ───
run_case "allowed hosts from options" '{"api_token":"t","allowed_hosts":["192.168.1.10","ha.lan"]}'
has "ENV SENSING_ALLOWED_HOSTS=192.168.1.10,ha.lan"
says "Web UI answers at: 192.168.1.10,ha.lan"

printf '%s' '{"result":"ok","data":{"hostname":"homeassistant","machine":"qemux86-64"}}' > "$work/info.json"
run_case "host name from the Supervisor" '{"api_token":"t","allowed_hosts":["192.168.1.10"],"mqtt":false}' \
    SUPERVISOR_TOKEN=test-supervisor-token
has "ENV SENSING_ALLOWED_HOSTS=192.168.1.10,homeassistant,homeassistant.local"
[ "$(curl_calls)" = 1 ] && ok || bad "one /info call"

printf '%s' '{"result":"ok","data":{"hostname":"bad host;rm -rf"}}' > "$work/info.json"
run_case "odd host name ignored" '{"api_token":"t","mqtt":false}' SUPERVISOR_TOKEN=test-supervisor-token
has "ENV SENSING_ALLOWED_HOSTS=unset"
says "Add the IP address you open Home Assistant at"
rm -f "$work/info.json"

run_case "no /info answer" '{"api_token":"t","allowed_hosts":["192.168.1.10"],"mqtt":false}' \
    SUPERVISOR_TOKEN=test-supervisor-token
has "ENV SENSING_ALLOWED_HOSTS=192.168.1.10"

run_case "HTTP closed: no host list" '{"allowed_hosts":["192.168.1.10"]}' SUPERVISOR_TOKEN=test-supervisor-token FAKE_SERVICE_FAIL=1
has "ENV SENSING_ALLOWED_HOSTS=unset"

# ── Trusted network: open HTTP without a token ────────────────────────────
run_case "trusted network" '{"trusted_network":true}'
exits 0
[ "$(args_after --bind-addr)" = 0.0.0.0 ] && ok || bad "HTTP bind"
has "ENV RUVIEW_ALLOW_UNAUTHENTICATED=1"
has "ENV RUVIEW_API_TOKEN=unset"

# ── A token wins over the trusted-network switch ──────────────────────────
run_case "token wins" '{"api_token":"t0k","trusted_network":true}'
has "ENV RUVIEW_API_TOKEN=set"
has "ENV RUVIEW_ALLOW_UNAUTHENTICATED=unset"
never "t0k"

# ── Insecure LAN without an allow-list ────────────────────────────────────
run_case "insecure LAN" '{"udp_insecure_lan":true}'
has "ARG=--udp-insecure-lan"
[ "$(args_after --udp-bind)" = 0.0.0.0 ] && ok || bad "UDP bind"
[ "$(grep -cxF 'ARG=--udp-bind' <<<"$out")" = 1 ] && ok || bad "one --udp-bind"
says "ANY sender"

# ── Broker from the Supervisor (Mosquitto app) ────────────────────────────
printf '%s' '{"result":"ok","data":{"host":"core-mosquitto","port":1883,"ssl":false,
"protocol":"3.1.1","username":"addons","password":"supervisor-pass-123"}}' > "$work/service.json"
run_case "Supervisor broker" '{}' SUPERVISOR_TOKEN=test-supervisor-token
exits 0
has "ARG=--mqtt"
[ "$(args_after --mqtt-host)" = core-mosquitto ] && ok || bad "host"
[ "$(args_after --mqtt-port)" = 1883 ] && ok || bad "port"
[ "$(args_after --mqtt-username)" = addons ] && ok || bad "username"
lacks "ARG=--mqtt-tls"
has "ENV MQTT_PASSWORD=set"
never "supervisor-pass-123"
never "test-supervisor-token"
says "MQTT=broker from the Supervisor"
[ "$(curl_calls)" = 1 ] && ok || bad "one Supervisor call"

# ── Supervisor broker over TLS ────────────────────────────────────────────
printf '%s' '{"result":"ok","data":{"host":"core-mosquitto","port":8883,"ssl":true,
"username":"addons","password":"p"}}' > "$work/service.json"
run_case "Supervisor TLS" '{}' SUPERVISOR_TOKEN=test-supervisor-token
has "ARG=--mqtt-tls"
[ "$(args_after --mqtt-port)" = 8883 ] && ok || bad "TLS port"

# ── Options override what the Supervisor provides ─────────────────────────
printf '%s' '{"result":"ok","data":{"host":"core-mosquitto","port":1883,"ssl":false,
"username":"addons","password":"p"}}' > "$work/service.json"
run_case "manual broker" \
    '{"mqtt_host":"192.168.1.20","mqtt_port":1884,"mqtt_username":"ruview","mqtt_password":"manual-pass"}' \
    SUPERVISOR_TOKEN=test-supervisor-token
[ "$(args_after --mqtt-host)" = 192.168.1.20 ] && ok || bad "manual host"
[ "$(args_after --mqtt-port)" = 1884 ] && ok || bad "manual port"
[ "$(args_after --mqtt-username)" = ruview ] && ok || bad "manual user"
has "ENV MQTT_PASSWORD=set"
never "manual-pass"
[ "$(curl_calls)" = 0 ] && ok || bad "a manual host skips the Supervisor"

# ── Supervisor has no broker: run without MQTT, say why ───────────────────
run_case "no broker installed" '{}' SUPERVISOR_TOKEN=test-supervisor-token FAKE_SERVICE_FAIL=1
exits 0
lacks "ARG=--mqtt"
has "ENV MQTT_PASSWORD=unset"
says "no broker was found"

# ── MQTT off: no broker lookup at all ─────────────────────────────────────
run_case "MQTT off" '{"mqtt":false}' SUPERVISOR_TOKEN=test-supervisor-token
lacks "ARG=--mqtt"
[ "$(curl_calls)" = 0 ] && ok || bad "MQTT off must not call the Supervisor"
says "MQTT=off"

# ── Simulated source: labelled, no node warning ───────────────────────────
run_case "simulated" '{"csi_source":"simulated"}'
[ "$(args_after --source)" = simulated ] && ok || bad "source"
says "SIMULATED"
grep -qF "no ESP32 node will be heard" <<<"$err" && bad "simulated needs no nodes" || ok

# ── Opt-in outputs and privacy ────────────────────────────────────────────
run_case "opt-ins" '{"privacy_mode":true,"publish_heart_rate":true,"publish_fall":true,"log_level":"warn"}'
has "ARG=--privacy-mode"
has "ARG=--mqtt-publish-heart-rate"
has "ARG=--mqtt-publish-fall"
has "ENV RUST_LOG=warn"
says "NOT validated"

# ── Bad input fails closed ────────────────────────────────────────────────
run_case "bad source" '{"csi_source":"wifi"}'
exits 64
says "csi_source must be"

run_case "bad log level" '{"log_level":"verbose"}'
exits 64

current="missing options"
rc=0
env -i PATH=/usr/bin:/bin RUVIEW_OPTIONS_FILE="$work/nope.json" RUVIEW_DRY_RUN=1 \
    sh "$script" > /dev/null 2> "$work/err" || rc=$?
err="$(cat "$work/err")"
exits 64
says "cannot read options file"

current="options not an object"
printf '[]' > "$work/list.json"
rc=0
env -i PATH=/usr/bin:/bin RUVIEW_OPTIONS_FILE="$work/list.json" RUVIEW_DRY_RUN=1 \
    sh "$script" > /dev/null 2> "$work/err" || rc=$?
err="$(cat "$work/err")"
exits 64
says "not a JSON object"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
