# Security policy

## Reporting a vulnerability

Please report security problems privately, through GitHub's
[private vulnerability reporting](https://github.com/Justinwold88/ruview-ha-addon/security/advisories/new),
not in a public issue. Include the app version (from the app's info page), what
you found and how to reproduce it. You'll get a reply within a week.

Vulnerabilities in RuView's sensing server itself belong to
[RuView](https://github.com/Justinwold88/RuView/security).

## What this app does to stay safe by default

- The web UI and REST API stay inside the app until you set a token or say
  your network is trusted. RuView refuses to serve live sensing data on a
  network without authentication.
- CSI frames are accepted only from addresses you allow, unless you choose
  otherwise.
- The start script never logs a token or password. The MQTT password reaches
  the server through an environment variable, not the command line.
- Images are built only by this repository's CI, from a pinned RuView commit,
  and published to GitHub Container Registry. A published version is never
  overwritten.
