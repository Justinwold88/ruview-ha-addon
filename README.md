# RuView apps for Home Assistant

[![CI](https://github.com/Justinwold88/ruview-ha-addon/actions/workflows/ci.yml/badge.svg)](https://github.com/Justinwold88/ruview-ha-addon/actions/workflows/ci.yml)
[![Build image](https://github.com/Justinwold88/ruview-ha-addon/actions/workflows/build.yml/badge.svg)](https://github.com/Justinwold88/ruview-ha-addon/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Stage: experimental](https://img.shields.io/badge/stage-experimental-orange.svg)

A Home Assistant app (formerly called an add-on) that runs
[RuView](https://github.com/Justinwold88/RuView). RuView senses whether a room is
occupied from the Wi-Fi signals between your router and small ESP32-S3 boards,
with no cameras or microphones. The app puts its sensors in Home Assistant
through MQTT discovery.

> **Experimental.** RuView is not camera-grade and has not yet been measured in
> a real home; its accuracy figures so far come from simulated rooms. Don't use
> it for health, safety or security decisions.

## Why an app

Before this, using RuView with Home Assistant meant running a Docker container
by hand, choosing a dozen flags and wiring up MQTT. The app turns that into an
install and a short options form:
- It finds the Mosquitto broker on its own.
- It keeps RuView's secure defaults.
- It updates like any other app.

## Install

1. In Home Assistant, open the app store, then the menu in the top right, then
   **Repositories**, and add:

   ```
   https://github.com/Justinwold88/ruview-ha-addon
   ```

2. Install **RuView**, then follow its **Documentation** tab
   ([ruview/DOCS.md](ruview/DOCS.md)).

Needs Home Assistant OS on `amd64` or `aarch64` (for example a PC, a VM, or a
Raspberry Pi 4/5), and ESP32-S3 boards running RuView's firmware. Set the
signal source to `simulated` to try it without boards.

## How it works

```
ESP32-S3 nodes ──UDP 5005 (CSI)──▶ RuView app ──MQTT discovery──▶ Mosquitto ──▶ Home Assistant
                                      │                                         (devices and
                                      └─ web UI / REST API on 3000–3001          sensors)
                                         (only with a token or trusted network)
```

- [`ruview/config.yaml`](ruview/config.yaml): the app manifest, with options
  and their schema.
- [`ruview/rootfs/usr/local/bin/ruview-run`](ruview/rootfs/usr/local/bin/ruview-run):
  turns the options into server flags.
  - It asks the Supervisor for the MQTT broker.
  - It refuses invalid input.
  - It never logs a secret.
- [`ruview/Dockerfile`](ruview/Dockerfile): builds RuView's sensing server, at
  the commit pinned in [`ruview/RUVIEW_COMMIT`](ruview/RUVIEW_COMMIT), into a
  small Debian image.

## Secure by default

| Surface | Default | To open it |
|---|---|---|
| Web UI and REST API | Inside the app only | Set a token, or mark the network as trusted |
| Web UI addresses | Host name only (DNS-rebinding guard) | List the IP address you use |
| CSI from nodes | Nobody heard | List your nodes' addresses (or accept any sender) |
| Heart rate, fall detection | Not announced | Opt in; both are unvalidated |
| Internet | No requests from the app | — |

See [SECURITY.md](SECURITY.md) for reporting a vulnerability.

## Development

```bash
tests/run_options_test.sh        # start-script tests (bash + jq), no Docker needed
scripts/fetch-ruview.sh          # RuView source at the pinned commit, into ruview-src/
docker build -f ruview/Dockerfile -t ruview-addon:dev .
tests/smoke_test.sh ruview-addon:dev
```

CI on every pull request:
- **CI** ([`ci.yml`](.github/workflows/ci.yml)):
  - lints the app manifest with the Home Assistant app linter;
  - checks that the version, changelog and pinned RuView commit agree;
  - runs ShellCheck and the start-script tests under `dash`, the image's shell.
- **Build image** ([`build.yml`](.github/workflows/build.yml)): builds natively
  on amd64 and arm64 runners and runs [`tests/smoke_test.sh`](tests/smoke_test.sh)
  against each image, next to a real Mosquitto broker and a stand-in
  Supervisor. The smoke test checks:
  - MQTT discovery;
  - token auth;
  - that secrets stay out of logs and process lists;
  - the secure default;
  - option validation;
  - a clean stop.

On `main`, a version that isn't published yet is pushed to
`ghcr.io/justinwold88/ruview-addon` as one multi-arch tag. A published version
is never overwritten. Releasing is described in
[CONTRIBUTING.md](CONTRIBUTING.md#releasing-a-new-version).

## License and credits

MIT, see [LICENSE](LICENSE). RuView is by rUv and contributors
([ruvnet/RuView](https://github.com/ruvnet/RuView), MIT). This app is built
from [Justinwold88/RuView](https://github.com/Justinwold88/RuView), a fork that
adds the calibration, link-score and Home Assistant work this app relies on.
