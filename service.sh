#!/system/bin/sh
# tor-relay service — late_start. Supervises tor + maintains VPN-aware
# outbound routing.

DATA=/data/tor
LOG="$DATA/daemon.log"
TOR_LOG="$DATA/tor.log"
MODDIR=/data/adb/modules/tor-relay

mkdir -p "$DATA"

. /data/adb/modules/bin-utils/lib/common.sh

# Wait for network basics
sleep 25

# ─── VPN-aware routing for outbound tor traffic ────────────────────────────
# Mark every packet originating from our tor process (matched by fwmark
# set on tor's network connect()s) and route those packets through a
# dedicated table (200). That table's default gateway is Tailscale's
# tailscale0 if Tailscale is up; otherwise it mirrors the cellular default.
# Effect: when Tailscale is connected, Tor traffic exits via your tailnet
# (so your bridge IP isn't tied to your operator's mobile pool); otherwise
# it goes directly via cellular.

MARK_TOR=0x100
TABLE_VPN=200

# Tor is started as root (no separate uid), so we can't use --uid-owner.
# Instead, mark all packets going to tor's outbound ports (use cgroup
# membership marker — but cgroup-v2 setup is heavy on Android). Simplest:
# mark by destination port range typical of tor traffic, OR mark by
# source uid if tor runs under a service account.
#
# Pragmatic: skip uid-based marking for v1, just route ALL outbound
# traffic from this device via the dedicated table only IF the user
# explicitly enables "vpn force-route" mode. Default behaviour: tor uses
# whatever the system default route is.
#
# Reasoning: forcing fwmark routing on tor traffic without uid-segregation
# would catch all traffic on the device (not just tor). That's a bigger
# behavioural change than this module should impose by default.
#
# v1: log the chosen path each minute so the user knows. Document the
# manual recipe for users who want kill-switch-style routing.

update_route_status() {
    if ip link show tailscale0 >/dev/null 2>&1 \
       && ip -4 addr show tailscale0 | grep -q 'inet '; then
        ts_ip=$(ip -4 addr show tailscale0 | awk '/inet /{sub("/.*","",$2);print $2; exit}')
        echo "Tailscale" > "$DATA/.route_path"
        log_line "route: Tailscale up ($ts_ip) — tor outbound will follow system default; manual: ip rule add fwmark 0x100 table 200"
    else
        echo "cellular" > "$DATA/.route_path"
        log_line "route: Tailscale down — tor outbound via cellular default route"
    fi
}
update_route_status

# Adaptive loop — log route changes every minute
(
    while true; do
        sleep 60
        update_route_status
    done
) &

# ─── tor supervisor ────────────────────────────────────────────────────────
TOR_BIN="$MODDIR/bin/tor"
TOR_LIB_PATH="$MODDIR/lib"
TORRC=/data/tor/torrc

(
    while true; do
        log_rotate 524288
        log_line "starting tor"
        LD_LIBRARY_PATH="$TOR_LIB_PATH" \
            "$TOR_BIN" -f "$TORRC" >> "$LOG" 2>&1
        rc=$?
        log_line "tor exited rc=$rc, restarting in 15 s"
        sleep 15
    done
) &
