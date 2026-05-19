#!/system/bin/sh
# tor-relay service — late_start. Three jobs:
#   1. Supervise the tor daemon
#   2. Apply VPN-aware outbound routing for tor's OWN traffic (only when
#      /data/tor/.route_mode = "vpn" — default "direct")
#   3. Apply per-client transparent-tor routing on br0 (only when
#      /data/tor/through_clients.json .enabled = true)

DATA=/data/tor
LOG="$DATA/daemon.log"
TOR_LOG="$DATA/tor.log"
MODDIR=/data/adb/modules/tor-relay
ROUTE_MODE_FILE="$DATA/.route_mode"
THROUGH_FILE="$DATA/through_clients.json"

FWMARK=0x100
ROUTE_TABLE=200
TOR_TRANS_PORT=9040
TOR_DNS_PORT=5354
HOTSPOT_IF=br0
HOTSPOT_GW=192.168.0.1

mkdir -p "$DATA/state"

. /data/adb/modules/bin-utils/lib/common.sh

JQ=$(command -v jq || echo /system/bin/jq)

# Tor needs the state dir writable by uid `shell` (since torrc has `User shell`)
SHELL_UID=$(id -u shell 2>/dev/null)
if [ -n "$SHELL_UID" ]; then
    chown -R shell:shell "$DATA/state" 2>/dev/null
    chown shell:shell "$DATA/torrc" 2>/dev/null
fi

# Warm-up
sleep 25

# ─── (1) VPN-aware outbound routing for tor's own traffic ─────────────────
apply_route_mode() {
    local mode
    mode=$(cat "$ROUTE_MODE_FILE" 2>/dev/null)
    [ -z "$mode" ] && mode=direct

    # Always start by clearing our marks/rules (idempotent)
    iptables -t mangle -D OUTPUT -m owner --uid-owner "$SHELL_UID" \
             -j MARK --set-mark "$FWMARK" 2>/dev/null
    while ip rule del fwmark "$FWMARK" table "$ROUTE_TABLE" 2>/dev/null; do :; done
    ip route flush table "$ROUTE_TABLE" 2>/dev/null

    if [ "$mode" = "vpn" ]; then
        if ! ip link show tailscale0 >/dev/null 2>&1 \
           || ! ip -4 addr show tailscale0 | grep -q 'inet '; then
            log_line "route_mode=vpn but Tailscale is down — kill-switch: tor traffic DROPS"
            ip route add unreachable default table "$ROUTE_TABLE" 2>/dev/null
        else
            local ts_ip
            ts_ip=$(ip -4 addr show tailscale0 | awk '/inet /{sub("/.*","",$2);print $2; exit}')
            ip route add default dev tailscale0 table "$ROUTE_TABLE" 2>/dev/null
            log_line "route_mode=vpn — tor outbound via tailscale0 ($ts_ip)"
        fi
        # Mark all outbound from tor's uid
        iptables -t mangle -A OUTPUT -m owner --uid-owner "$SHELL_UID" \
                 -j MARK --set-mark "$FWMARK"
        ip rule add fwmark "$FWMARK" table "$ROUTE_TABLE" priority 100
        echo Tailscale > "$DATA/.route_path"
    else
        # direct mode — tor uses the system default route (cellular)
        log_line "route_mode=direct — tor outbound via system default"
        echo cellular > "$DATA/.route_path"
    fi
}

# ─── (2) Per-client transparent tor ───────────────────────────────────────
apply_through_tor() {
    [ -r "$THROUGH_FILE" ] || return 0
    local enabled
    enabled=$("$JQ" -r '.enabled // false' "$THROUGH_FILE" 2>/dev/null)

    # Wipe our chain unconditionally — we'll repopulate if enabled
    iptables -t nat -D PREROUTING -i "$HOTSPOT_IF" -j TOR_THROUGH 2>/dev/null
    iptables -t nat -F TOR_THROUGH 2>/dev/null
    iptables -t nat -X TOR_THROUGH 2>/dev/null
    iptables -D FORWARD -m mark --mark "$FWMARK"_drop 2>/dev/null

    [ "$enabled" != "true" ] && {
        log_line "through-tor: disabled"
        return 0
    }

    # (Re)create chain
    iptables -t nat -N TOR_THROUGH 2>/dev/null

    local count=0
    "$JQ" -r '.clients[]' "$THROUGH_FILE" 2>/dev/null | while read -r ip; do
        [ -z "$ip" ] && continue
        echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || continue
        # DNS first (TCP + UDP) → tor DNSPort. Without this, the client
        # leaks its real DNS even with TCP redirected.
        iptables -t nat -A TOR_THROUGH -s "$ip" -p udp --dport 53 \
                 -j REDIRECT --to-ports "$TOR_DNS_PORT"
        iptables -t nat -A TOR_THROUGH -s "$ip" -p tcp --dport 53 \
                 -j REDIRECT --to-ports "$TOR_DNS_PORT"
        # All other TCP → TransPort
        iptables -t nat -A TOR_THROUGH -s "$ip" -p tcp \
                 -j REDIRECT --to-ports "$TOR_TRANS_PORT"
        # Block non-DNS UDP from this client to prevent leaks (Tor is TCP-only)
        iptables -A FORWARD -s "$ip" -p udp ! --dport 53 -j DROP
        count=$((count+1))
        log_line "through-tor: $ip → TransPort $TOR_TRANS_PORT (DNS via $TOR_DNS_PORT)"
    done

    iptables -t nat -A PREROUTING -i "$HOTSPOT_IF" -j TOR_THROUGH 2>/dev/null
    log_line "through-tor: enabled for clients (chain TOR_THROUGH active)"
}

apply_route_mode
apply_through_tor

# Periodic re-apply (route status may change with Tailscale up/down, and
# vendor firmware sometimes reorders iptables on tethering toggle).
(
    while true; do
        sleep 60
        apply_route_mode
        apply_through_tor
    done
) &

# ─── (3) tor supervisor ────────────────────────────────────────────────────
TOR_BIN="$MODDIR/bin/tor"
TOR_LIB_PATH="$MODDIR/lib"
TORRC="$DATA/torrc"

(
    while true; do
        log_rotate 524288
        log_line "starting tor"
        LD_LIBRARY_PATH="$TOR_LIB_PATH" \
            "$TOR_BIN" -f "$TORRC" >> "$LOG" 2>&1
        log_line "tor exited rc=$?, restarting in 15 s"
        sleep 15
    done
) &
