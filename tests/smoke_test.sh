#!/usr/bin/env bash
# End-to-end smoke test for a built app image.
#
#   tests/smoke_test.sh IMAGE
#
# Starts the image the way the Supervisor does (options in /data, init, the
# Supervisor's /services/mqtt answered by a stand-in) next to a real
# Mosquitto broker, then checks:
#   1. token mode: /health, 401 without the token, 200 with it, the UI,
#      MQTT discovery (presence, and link score as a diagnostic), persisted
#      state, no secret in the log, clean stop;
#   2. default mode: HTTP stays inside the container;
#   3. a bad option stops the app with exit code 64.
# Needs docker, curl and jq.
set -euo pipefail

image="${1:?usage: tests/smoke_test.sh IMAGE}"
net="ruview-smoke-$$"
work="$(mktemp -d)"
token="smoke-api-token-$$-do-not-use"
supervisor_token="smoke-supervisor-token"
mqtt_pass="smoke-mqtt-password"
containers=()

cleanup() {
    for c in "${containers[@]}"; do docker rm -f "$c" >/dev/null 2>&1 || true; done
    docker network rm "$net" >/dev/null 2>&1 || true
    rm -rf "$work"
}
trap cleanup EXIT

step() { printf '\n== %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
run_bg() { containers+=("$1"); docker run -d --name "$@" >/dev/null; }

wait_for() {
    # wait_for SECONDS COMMAND...: retry until the command succeeds.
    local deadline=$((SECONDS + $1))
    shift
    until "$@" >/dev/null 2>&1; do
        [ "$SECONDS" -lt "$deadline" ] || return 1
        sleep 1
    done
}

docker network create "$net" >/dev/null

step "Broker and Supervisor stand-in"
run_bg broker --network "$net" eclipse-mosquitto:2.0.18 \
    mosquitto -c /mosquitto-no-auth.conf
mkdir -p "$work/www/services"
jq -n --arg p "$mqtt_pass" \
    '{result: "ok", data: {host: "broker", port: 1883, ssl: false,
      protocol: "3.1.1", username: "addons", password: $p}}' \
    > "$work/www/services/mqtt"
chmod -R a+rX "$work/www"
run_bg supervisor --network "$net" -v "$work/www:/www:ro" busybox:1.36 \
    httpd -f -p 80 -h /www
wait_for 30 docker run --rm --network "$net" busybox:1.36 \
    wget -q -O /dev/null http://supervisor/services/mqtt \
    || fail "Supervisor stand-in did not start"

# ── 1. Token mode with MQTT from the Supervisor ───────────────────────────
step "Token mode"
mkdir -p "$work/data1"
jq -n --arg t "$token" '{csi_source: "simulated", udp_allow: ["172.16.0.0/12"],
    udp_insecure_lan: false, mqtt: true, trusted_network: false,
    privacy_mode: false, publish_heart_rate: false, publish_fall: false,
    log_level: "info", api_token: $t}' > "$work/data1/options.json"
chmod -R a+rwX "$work/data1"

# Discovery messages are retained, but subscribe first anyway.
containers+=(sub)
docker run -d --name sub --network "$net" eclipse-mosquitto:2.0.18 \
    mosquitto_sub -h broker -v -W 120 -t 'homeassistant/#' >/dev/null

run_bg app1 --init --network "$net" -p 127.0.0.1:3000:3000 \
    -v "$work/data1:/data" -e SUPERVISOR_TOKEN="$supervisor_token" "$image"
wait_for 90 curl -fsS http://127.0.0.1:3000/health \
    || { docker logs app1 >&2 || true; fail "/health never answered"; }
echo "health: $(curl -fsS http://127.0.0.1:3000/health)"

code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/api/v1/info)
[ "$code" = 401 ] || fail "API without the token returned $code, expected 401"
curl -fsS -H "Authorization: Bearer $token" http://127.0.0.1:3000/api/v1/info >/dev/null \
    || fail "API with the token failed"
code=$(curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer wrong' \
    http://127.0.0.1:3000/api/v1/info)
[ "$code" = 401 ] || fail "API with a wrong token returned $code, expected 401"
curl -fsS http://127.0.0.1:3000/ui/index.html >/dev/null || fail "UI not served"
echo "auth and UI: ok"

step "MQTT discovery"
discovered() { docker logs sub 2>&1 | grep -q "$1"; }
wait_for 60 discovered '^homeassistant/binary_sensor/[^ ]*/presence/config ' \
    || { docker logs app1 >&2; fail "no presence discovery config"; }
wait_for 30 discovered '^homeassistant/sensor/[^ ]*/link_score/config ' \
    || fail "no link score discovery config"
docker logs sub 2>&1 | grep '^homeassistant/sensor/[^ ]*/link_score/config ' | head -1 \
    | grep -q '"entity_category":"diagnostic"' || fail "link score is not a diagnostic entity"
echo "discovery: $(docker logs sub 2>&1 | grep -c '/config ') config messages"

step "State, logs and stop"
docker exec app1 test -s /data/mqtt_client_id || fail "MQTT client id not persisted in /data"
logs="$(docker logs app1 2>&1)"
grep -q 'MQTT=broker from the Supervisor' <<<"$logs" || fail "broker was not taken from the Supervisor"
grep -q 'web UI/API=token' <<<"$logs" || fail "token mode not reported"
for secret in "$token" "$supervisor_token" "$mqtt_pass"; do
    grep -qF "$secret" <<<"$logs" && fail "a secret appeared in the log"
done
# The password must not be on the server's command line either.
docker exec app1 sh -c 'cat /proc/1/cmdline /proc/[0-9]*/cmdline 2>/dev/null | tr "\0" " "' \
    | grep -qF "$mqtt_pass" && fail "the MQTT password is on a command line"
start=$SECONDS
docker stop -t 20 app1 >/dev/null
[ $((SECONDS - start)) -lt 15 ] || fail "the app took $((SECONDS - start)) s to stop"
echo "stopped in $((SECONDS - start)) s"

# ── 2. Defaults: HTTP stays inside the container ──────────────────────────
step "Default mode"
mkdir -p "$work/data2"
jq -n '{csi_source: "simulated", udp_allow: [], udp_insecure_lan: false,
    mqtt: false, trusted_network: false, privacy_mode: false,
    publish_heart_rate: false, publish_fall: false, log_level: "info"}' \
    > "$work/data2/options.json"
chmod -R a+rwX "$work/data2"
run_bg app2 --init -p 127.0.0.1:3100:3000 -v "$work/data2:/data" "$image"
wait_for 90 docker exec app2 curl -fsS http://127.0.0.1:3000/health \
    || { docker logs app2 >&2; fail "/health never answered inside the container"; }
curl -fsS --max-time 5 http://127.0.0.1:3100/health >/dev/null 2>&1 \
    && fail "HTTP is reachable from outside without a token"
grep -q 'kept inside the app' <<<"$(docker logs app2 2>&1)" || fail "default mode not explained in the log"
echo "HTTP stays inside the container: ok"

# ── 3. A bad option stops the app ─────────────────────────────────────────
step "Bad option"
mkdir -p "$work/data3"
jq -n '{csi_source: "wifi", mqtt: false}' > "$work/data3/options.json"
chmod -R a+rwX "$work/data3"
rc=0
docker run --rm --init -v "$work/data3:/data" "$image" >/dev/null 2>&1 || rc=$?
[ "$rc" = 64 ] || fail "bad option exited with $rc, expected 64"
echo "bad option refused: ok"

printf '\nSmoke test passed for %s\n' "$image"
