# Changelog

## 0.1.0

First release (experimental).

- Runs RuView's sensing server, built from
  [Justinwold88/RuView@1f6ad56d](https://github.com/Justinwold88/RuView/commit/1f6ad56d5842857a9e8d7c2e8a44f74178b2586f),
  with MQTT discovery for Home Assistant.
- Finds the Mosquitto broker through the Supervisor, or uses a broker you set.
- Hears ESP32 nodes only from the addresses you allow (or, if you choose,
  from any sender).
- Keeps the web UI and REST API inside the app unless you set a token or mark
  your network as trusted.
- Heart rate and fall detection stay off unless you opt in; both are
  unvalidated.
- Images for `amd64` and `aarch64`.
