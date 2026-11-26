# Changelog

## 0.1.0

First release (experimental).

- Runs RuView's sensing server, built from
  [Justinwold88/RuView@de4a8c54](https://github.com/Justinwold88/RuView/commit/de4a8c54d1cd89bd2fc5a34e0e2bab808c0ce344),
  with MQTT discovery for Home Assistant.
- Finds the Mosquitto broker through the Supervisor, or uses a broker you set.
- Hears ESP32 nodes only from the addresses you allow (or, if you choose,
  from any sender).
- Keeps the web UI and REST API inside the app unless you set a token or mark
  your network as trusted. Once open, it answers only at your Home Assistant
  host name and the addresses you list (RuView's DNS-rebinding guard).
- Heart rate and fall detection stay off unless you opt in; both are
  unvalidated.
- Images for `amd64` and `aarch64`.
