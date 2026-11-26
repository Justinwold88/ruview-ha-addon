# RuView app

RuView senses whether a room is occupied from the Wi-Fi signals between your
router and small ESP32-S3 boards (channel state information, or CSI). It uses
no cameras and no microphones. This app runs RuView's sensing server inside
Home Assistant and announces its sensors over MQTT, so they appear as devices
on their own.

> **Experimental.** RuView is not camera-grade and has not yet been measured
> in a real home. Its accuracy figures so far come from simulated rooms
> (SYNTHETIC). Heart rate and fall detection are unvalidated and stay off
> unless you turn them on. Do not use RuView for health, safety or security
> decisions.

## What you need

- **Home Assistant OS.** Apps (add-ons) need it. On a Windows PC, run Home
  Assistant OS in a virtual machine (Hyper-V on Windows Pro, or VirtualBox).
- **ESP32-S3 boards running RuView's firmware**, on the same network. See the
  [hardware guide](https://github.com/Justinwold88/RuView/blob/main/docs/user-guide.md).
- **An MQTT broker.** The easiest is the official Mosquitto broker app. This
  app finds it automatically.

You can try the app before the boards arrive: set **Signal source** to
`simulated`. Those readings are synthetic, so don't build automations on them.

## Installation

1. In Home Assistant, open the app store, then the menu in the top right, then
   **Repositories**. Add `https://github.com/Justinwold88/ruview-ha-addon`.
2. Find **RuView** in the store and install it.
3. Install and start the **Mosquitto broker** app, if you don't have a broker.
4. Set this app's options (below), then start it and open its **Log** tab.
   The last line it writes at startup says how it is running, for example:
   `Starting RuView: source=esp32, web UI/API=token, nodes=allow-list,
   MQTT=broker from the Supervisor`.
5. Point each ESP32 node at your Home Assistant host's IP address, UDP port
   5005 (set during provisioning; see the hardware guide).

RuView's devices then appear under **Settings → Devices & services → MQTT**,
one per node. The
[entity reference](https://github.com/Justinwold88/RuView/blob/main/docs/integrations/home-assistant.md#entity-reference)
lists each sensor and when it is available.

## Options

| Option | Default | What it does |
|---|---|---|
| Signal source | `esp32` | `esp32` listens for your nodes. `simulated` makes synthetic data for trying the app. |
| Allowed node addresses | empty | Addresses or CIDR blocks your nodes send from, such as `192.168.1.0/24`. **No node is heard until this is set** (or the next option is on). |
| Accept nodes from any address | off | Accepts CSI from any sender. Anyone on your network could feed fake data, so prefer the list. |
| Publish to Home Assistant over MQTT | on | Announces the sensors with MQTT discovery. |
| MQTT broker host, port, username, password | empty | Only needed for a broker other than the Mosquitto app. Leave the host empty to use the Supervisor's broker. |
| Web UI and API token | empty | Opens RuView's web UI and REST API on your network, protected by this token. Use a long random value. |
| Web UI addresses | empty | The IP address you open the web UI at, for example `192.168.1.10`. Your host name and its `.local` name are added for you. |
| Open the web UI without a token | off | Opens the UI and API to anyone who can reach the host. Only on a network you fully trust. |
| Privacy mode | off | Removes heart rate, breathing rate and pose from every output. |
| Announce heart rate | off | Unvalidated: it scores at chance in RuView's synthetic tests. |
| Announce fall detection | off | Unvalidated. Do not rely on it to detect a fall. |
| Log level | `info` | `trace`, `debug`, `info`, `warn` or `error`. |

### Web UI and API

Without a token, and without the trusted-network switch, the UI and REST API
stay inside the app. MQTT and your nodes still work, but **Open Web UI** will
not load. This matches RuView's own rule: it refuses to serve live sensing data
on a network without authentication.

To open them, set **Web UI and API token**. If you open Home Assistant by IP
address, add that address to **Web UI addresses**. RuView answers only to
addresses on its list, which blocks DNS-rebinding attacks from other websites;
any other address gets `421 Misdirected Request`. Your Home Assistant host name
(`homeassistant`, `homeassistant.local`) is on the list automatically.

Then open the web UI and enter the same token in its settings panel (the
"Bearer token" field). Keep ports 3000 and 3001 as they are: the UI finds its
live stream on the port after the web port.

## Calibrate each room

A one-minute calibration of the empty room sets each node's presence threshold
and gives it a 0–100 link score, shown in Home Assistant as the node's
**Link score** diagnostic sensor. Without it, a noisy link can read an empty
room as occupied. It needs the token.

Add a button for it in Home Assistant. In `configuration.yaml`:

```yaml
rest_command:
  ruview_calibrate:
    url: "http://YOUR-HOME-ASSISTANT-IP:3000/api/v1/calibration/motion/start"
    method: post
    headers:
      authorization: !secret ruview_bearer
```

and in `secrets.yaml`:

```yaml
ruview_bearer: "Bearer YOUR-TOKEN"
```

Restart Home Assistant, then run the `rest_command.ruview_calibrate` action.
Leave the room within 10 seconds and keep it empty and still for the next 60:
no people, no pets, no fan or moving curtain. Calibrate again whenever you move
a node.

## Alexa

RuView's guide describes three ways to use its presence in Alexa routines,
including a free one over Matter for Matter-capable Echo devices:
[Alexa (through Home Assistant)](https://github.com/Justinwold88/RuView/blob/main/docs/integrations/home-assistant.md#alexa-through-home-assistant).

## Network ports

| Port | Used for |
|---|---|
| 5005/udp | CSI frames from your ESP32 nodes |
| 3000/tcp | Web UI and REST API (only reachable with a token or trusted network) |
| 3001/tcp | The live sensing stream the web UI reads |

## Data and privacy

The app keeps its state in its own data folder, which Home Assistant includes
in backups:
- the MQTT client id that keeps your device ids stable;
- each node's calibration;
- runtime settings.

It does not record raw CSI unless you start a recording through the API. It
turns off RuView's only built-in online lookup (an app registry it would
fetch on request), so it makes no internet requests of its own. MQTT
messages go only to your broker.

## Troubleshooting

- **No devices in Home Assistant:** check the log for `MQTT=off (no broker
  found)`. Install the Mosquitto app, or set the broker options.
- **Devices appear but nothing changes:** the log says `nodes=loopback (no nodes
  heard)` until you allow your nodes' addresses. Also check that each node sends
  to your Home Assistant host's IP on UDP 5005.
- **Every room always reads occupied:** calibrate each room (above).
- **Open Web UI doesn't load:** set a token (see Web UI and API).
- **The web UI says `421 Misdirected Request`:** add the address in your
  browser's address bar (without `http://` or the port) to Web UI addresses.

## Support

Report problems at
[Justinwold88/ruview-ha-addon issues](https://github.com/Justinwold88/ruview-ha-addon/issues).
Problems with sensing itself belong in
[RuView's issues](https://github.com/Justinwold88/RuView/issues).
