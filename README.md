# tor-relay

A Tor **bridge** node — *not* an exit relay — for the ZTE F50 cep çakısı.
Contributes anonymous bandwidth to the Tor network from your cellular SIM,
helping users in censored regions reach the open internet. Default
bandwidth cap is intentionally low (256 KB/s) so it doesn't burn your
mobile data plan.

## Why a bridge, not an exit?

- **Bridge** = a "first hop" entry into the Tor network used by people
  whose ISP/government blocks the public Tor relays. Bridges are not
  publicly listed in directories. Traffic exiting a bridge goes to other
  Tor relays, not directly to the user's destination.
- **Exit** = the final hop that connects to the open internet. Exit
  operators occasionally get abuse complaints (or legal letters). On a
  cellular SIM tied to your personal identity, you do **not** want this.
  We hardcode `ExitRelay 0` and `ExitPolicy reject *:*`.

## VPN-aware routing

If Tailscale (or any other VPN that creates a `tailscale0` interface) is
up on this device, the module logs and reports the active path. With the
default v1 behaviour, tor traffic uses the system's default route — same
as everything else.

If you want a kill-switch-style "tor *only* exits via Tailscale", apply
this manual recipe after install:

```sh
# Inside /data/adb/modules/tor-relay/service.sh — or as a one-shot:
iptables -t mangle -I OUTPUT -m owner --uid-owner $(id -u inet) \
    -j MARK --set-mark 0x100
ip rule add fwmark 0x100 table 200
ip route add default dev tailscale0 table 200
```

(Default v1 leaves this disabled because forcing all outbound traffic
through a marked table can break other services if Tailscale flaps.)

## Requires

- Magisk 26.0+
- Android arm64 (Unisoc UMS9620 / ZTE F50)
- **bin-utils v1.3.0+** (`lib/common.sh`)
- Open port 9001/TCP outbound from your operator (most operators allow
  this — some block; check `/tor log` after install)

## Files

```
/data/adb/modules/tor-relay/
├── bin/tor                          static aarch64 tor 0.4.9.8 (2.4 MB)
├── lib/libssl.so.3                  OpenSSL bundled (854 KB)
├── lib/libcrypto.so.3               OpenSSL bundled (5.0 MB)
└── etc/torrc.template               seed config (bridge mode)

/data/tor/
├── torrc                            user-editable config (seeded on install)
├── tor.log                          tor's own log
├── daemon.log                       supervisor log
├── .route_path                      current routing path: "Tailscale" or "cellular"
└── state/                           tor's data dir (keys, descriptors, cache)
```

## Bot commands

statusbot v2.18+ adds:

- `/tor status` — daemon up? circuit count? current route path?
- `/tor on|off`
- `/tor route` — show current routing decision (Tailscale vs cellular)
- `/tor fingerprint` — your bridge's identity fingerprint (share this
  with people who need a private bridge to reach you)
- `/tor log` — last 20 lines of tor.log

## Install

```sh
# From the bot:
/install_module tor-relay

# Or manually:
adb push tor-relay-vX.Y.Z.zip /sdcard/
adb shell su -c "magisk --install-module /sdcard/tor-relay-vX.Y.Z.zip"
reboot
```

## Configuration

Edit `/data/tor/torrc` to tune:

- `Nickname` — your bridge's display name (publicly visible)
- `ContactInfo` — empty for fully private bridge, or email to be
  contacted about abuse / decommissioning
- `RelayBandwidthRate` / `RelayBandwidthBurst` — caps on relay
  bandwidth; tune to your data plan
- `BridgeRelay 1` / `ExitRelay 0` — **don't change these** unless you
  understand the legal implications

After editing, restart: `kill $(pgrep tor)` — supervisor respawns it.

## Why no GeoIP?

Tor's full GeoIP databases (`geoip` + `geoip6`) are ~26 MB combined. For
a private bridge mode they're not strictly required — they only affect
country-statistics reporting and some advanced exit-relay features. We
skip them to keep the module small. Add them manually to
`/data/tor/state/` if you want them.

## Uninstall

Magisk Manager → Modules → Remove. `uninstall.sh` stops the daemon; the
state at `/data/tor/` is kept (your bridge identity keys persist so a
reinstall keeps the same fingerprint). Wipe manually: `rm -rf /data/tor`.

## License

GPL-3.0. Tor itself is BSD-3-Clause.
