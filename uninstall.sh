#!/system/bin/sh
# Stop daemons + clean up iptables / ip rule entries we added.

pkill -f /data/adb/modules/tor-relay/bin/tor 2>/dev/null
pkill -f /data/adb/modules/tor-relay/service.sh 2>/dev/null

# Remove fwmark routing (route_mode=vpn legacy)
iptables -t mangle -D OUTPUT -m owner --uid-owner shell -j MARK --set-mark 0x100 2>/dev/null
while ip rule del fwmark 0x100 table 200 2>/dev/null; do :; done
ip route flush table 200 2>/dev/null

# Remove transparent-proxy chain
iptables -t nat -D PREROUTING -i br0 -j TOR_THROUGH 2>/dev/null
iptables -t nat -F TOR_THROUGH 2>/dev/null
iptables -t nat -X TOR_THROUGH 2>/dev/null

# /data/tor kept — torrc + state + log preserved.
# rm -rf /data/tor to wipe.
