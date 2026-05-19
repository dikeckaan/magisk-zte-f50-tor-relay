# Changelog

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
