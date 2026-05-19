#!/system/bin/sh
ui_print " "
ui_print "  Tor Bridge (VPN-aware) v1.0.0"
ui_print "  =============================="
ui_print " "
ui_print "  • Bridge mode (NOT exit) — anonymous bandwidth contribution"
ui_print "  • VPN-aware routing — uses Tailscale if up, cellular if not"
ui_print "  • Default rate limit: 256 KB/s relay bandwidth"
ui_print "  • SOCKS 9050 + control 9051 (loopback only)"
ui_print " "
ui_print "  Bundled: tor 0.4.9.8 + libssl.so.3 + libcrypto.so.3 (~8MB)"
ui_print " "

if [ "$ARCH" != "arm64" ]; then
    abort "  Tor binary is arm64-only. Aborting."
fi

# Hard dep: bin-utils v1.3.0+
if [ ! -r /data/adb/modules/bin-utils/lib/common.sh ] \
   && [ ! -r /data/adb/modules_update/bin-utils/lib/common.sh ]; then
    abort "  ❌ bin-utils v1.3.0+ required (lib/common.sh missing)."
fi

mkdir -p /data/tor/state
chmod 755 /data/tor /data/tor/state

# Seed torrc on first install
if [ ! -f /data/tor/torrc ]; then
    ui_print "  Seeding initial torrc (bridge mode)"
    cp "$MODPATH/etc/torrc.template" /data/tor/torrc
    chmod 600 /data/tor/torrc
else
    ui_print "  Keeping existing /data/tor/torrc"
fi

set_perm "$MODPATH/bin/tor"           0 0 0755
set_perm "$MODPATH/lib/libssl.so.3"   0 0 0644
set_perm "$MODPATH/lib/libcrypto.so.3" 0 0 0644
set_perm "$MODPATH/service.sh"        0 0 0755

ui_print "  [OK] Installed. Reboot to start the bridge."
ui_print "  Bot commands (statusbot v2.18+): /tor {status|on|off|route|fingerprint}"
ui_print " "
