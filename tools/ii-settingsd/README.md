# ii-settingsd

`ii-settingsd` is the native Linux service behind Illogical Impulse's custom
settings UI. It keeps system integration out of the QML process without routing
settings through KDE System Settings or GNOME Control Center.

The service is intentionally small:

- one long-running Rust process;
- direct `/proc` and `/sys` reads for hardware and resource state;
- direct system D-Bus calls for BlueZ, NetworkManager, power-profiles-daemon,
  systemd-hostnamed, systemd-timedated, and systemd-logind;
- a versioned newline-delimited JSON API on a user-private Unix socket;
- an allowlist of typed, reversible actions—there is no arbitrary command
  execution API.

Quickshell remains the sole owner of the user's persistent settings JSON.
`ii-settingsd` reads live operating-system state and performs explicit native
actions; it does not read or rewrite the shell configuration.

## Build

```sh
cargo build --release --locked
cargo test --locked
```

The release profile enables LTO, uses one code-generation unit, strips symbols,
and aborts on panic to keep the resident binary compact.

## Run and query

The default socket is:

```text
$XDG_RUNTIME_DIR/ii-settingsd/daemon.sock
```

Start the service in one terminal:

```sh
ii-settingsd serve
```

The same binary has a lightweight client mode suitable for a Quickshell
`Process` integration:

```sh
ii-settingsd call ping
ii-settingsd call snapshot
ii-settingsd call bluetooth.snapshot
ii-settingsd call bluetooth.set_powered '{"adapter":"hci0","powered":true}'
ii-settingsd call power.set_profile '{"profile":"balanced"}'
ii-settingsd call time.set_timezone '{"timezone":"Europe/London"}'
ii-settingsd call hostname.set \
  '{"hostname":"studio-pc","pretty_hostname":"Studio PC"}'
```

Client mode prints only the successful `result` as formatted JSON. For a custom
socket, place `--socket /absolute/path` anywhere after the subcommand.

## Protocol

Each request and response is one JSON object followed by `\n`. Connections may
remain open for multiple requests. IDs may be strings, numbers, or `null` and
are returned unchanged.

Request:

```json
{"id":"ui-18","method":"power.profile","params":{}}
```

Successful response:

```json
{"id":"ui-18","ok":true,"result":{"available":true,"active_profile":"balanced","profiles":["balanced","performance","power-saver"],"performance_degraded":""}}
```

Error response:

```json
{"id":"ui-19","ok":false,"error":{"code":"invalid_params","message":"profile must be power-saver, balanced, or performance"}}
```

Call `protocol.describe` to discover the protocol version, size limit, and
method shapes. Version 1 exposes:

| Method | Purpose |
| --- | --- |
| `ping` | Service/version/uptime health check |
| `protocol.describe` | Machine-readable API description |
| `snapshot` | Partial-failure system, hardware, resource, session, and native-service state |
| `capabilities` | Kernel interfaces, D-Bus services, optional tools, and available feature flags |
| `bluetooth.snapshot` | BlueZ adapters and devices, including pairing, connection, signal, and battery state |
| `bluetooth.set_powered` | Power one validated `hciN` adapter on or off |
| `bluetooth.set_discoverable` | Set discoverability and an optional 0–3600 second timeout |
| `bluetooth.set_pairable` | Set pairability and an optional 0–3600 second timeout |
| `network.set_wireless_enabled` | Toggle NetworkManager wireless state |
| `power.profile` | Read the native active and available power profiles |
| `power.set_profile` | Select `power-saver`, `balanced`, or `performance` |
| `time.set_ntp` | Enable or disable systemd-timedated network time |
| `time.set_timezone` | Select a verified binary IANA zoneinfo entry |
| `hostname.set` | Set the static DNS-style hostname, pretty hostname, or both |
| `session.lock` | Lock only the daemon's own logind session |

The broad `snapshot` method caches its response for 750 ms; capabilities cache
for 15 seconds. Actions invalidate the snapshot. This avoids repeated sysfs and
D-Bus walks while controls still respond immediately.

### Snapshot coverage

- OS, kernel, CPU, DMI hardware, hostname, boot ID, and uptime;
- memory, swap, load averages, and root filesystem usage;
- batteries, external power supplies, backlights, and thermal zones;
- DRM connectors and supported modes;
- network interfaces and counters;
- EFI, kernel lockdown, Linux security modules, AppArmor, and SELinux presence;
- session environment plus logind's current-session state;
- partial native snapshots from BlueZ, NetworkManager, power profiles,
  hostnamed, and timedated.

Missing files, hardware, or optional services appear as `null`, empty lists, or
an object with `"available": false`; they do not make the whole snapshot fail.

## Security model

- The runtime directory is created with mode `0700`; the socket is mode `0600`.
- Linux `SO_PEERCRED` rejects clients whose effective UID differs from the
  daemon's UID, even if socket permissions are accidentally loosened.
- Requests are capped at 1 MiB and active clients at 32.
- Method names and action parameters are allowlisted and validated. Bluetooth
  adapter paths accept only `hci` followed by digits.
- Time zones reject absolute paths, empty components, traversal, non-IANA
  characters, targets outside `/usr/share/zoneinfo`, non-regular files, and
  files without a `TZif` header.
- Static hostnames use conservative DNS-label validation with a 64-byte limit.
  Pretty hostnames permit readable Unicode but reject controls, bidi overrides,
  surrounding whitespace, and values longer than 64 characters or 256 bytes.
- The daemon never receives passwords and never invokes a shell or arbitrary
  executable.
- Privileged D-Bus services retain final authority. A desktop polkit agent may
  request confirmation for an action such as changing NTP.

## systemd user service

The hardened unit is in [`systemd/ii-settingsd.service`](systemd/ii-settingsd.service).
One conventional local installation is:

```sh
install -Dm755 target/release/ii-settingsd "$HOME/.local/bin/ii-settingsd"
install -Dm644 systemd/ii-settingsd.service \
  "$HOME/.config/systemd/user/ii-settingsd.service"
systemctl --user daemon-reload
systemctl --user enable --now ii-settingsd.service
```

The checked-in unit expects the binary at `%h/.local/bin/ii-settingsd`.
