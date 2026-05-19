# Changelog

## v1.1.0 — 2026-05-19
- **Route mode selection** — Tor's own outbound traffic can now be
  pinned via `/data/tor/.route_mode`:
  - `direct` (default) — uses the system default route (cellular)
  - `vpn` — fwmark-routes tor traffic through `tailscale0` only; if
    Tailscale is down, traffic is dropped (kill-switch). Implemented
    via `iptables -t mangle ... -m owner --uid-owner shell` (tor now
    runs as the shell uid, see `User shell` in torrc).
- **Transparent per-client tor** — selected hotspot clients can be
  routed entirely through Tor:
  - TCP traffic → tor `TransPort` on 192.168.0.1:9040
  - DNS (UDP/TCP :53) → tor `DNSPort` on 192.168.0.1:5354
  - Non-DNS UDP from those clients DROPPED (Tor is TCP-only; this
    prevents leaks via QUIC, WebRTC, etc.)
  - Client list at `/data/tor/through_clients.json`, format:
    `{"enabled": true, "clients": ["192.168.0.5", ...]}`
  - iptables chain `TOR_THROUGH` hooked into nat PREROUTING on br0
- `service.sh` re-applies both policies every 60s (handles Tailscale
  flap, firmware iptables reordering).
- `uninstall.sh` now cleans up the mangle marks, ip rule, route table
  and TOR_THROUGH chain.
- statusbot v2.18.1+ exposes `/tor route mode` and `/tor through`
  commands to manage this from Telegram.

## v1.0.0 — 2026-05-19
- Initial release. Tor 0.4.9.8 bridge node (NOT exit) for ZTE F50.
- Bundles tor binary (2.4 MB) + libssl 3.6.2 + libcrypto + libevent
  2.1.12 + liblzma 5.8.3 + libz 1.3.2 from Termux packages. ~9 MB total.
- `service.sh` runs tor under `LD_LIBRARY_PATH=/data/adb/modules/tor-relay/lib`
  so the bundled libs are picked up without overlay-mounting `/system`.
- Default config: bridge mode, OR port 9001, SOCKS 9050, ControlPort 9051
  (both loopback only), 256 KB/s relay bandwidth, no geoip.
- VPN-aware routing: when Tailscale is up, logs that fact; default v1
  uses system route (manual fwmark recipe documented for kill-switch
  behaviour).
- Verified live: bridge bootstraps, connects to other tor relays
  (137.74.115.48 / 109.69.66.221), identity fingerprint generated.
