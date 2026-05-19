#!/system/bin/sh
pkill -f /data/adb/modules/tor-relay/bin/tor 2>/dev/null
pkill -f /data/adb/modules/tor-relay/service.sh 2>/dev/null
# /data/tor kept — torrc + state + log preserved. Wipe manually if needed:
#   rm -rf /data/tor
