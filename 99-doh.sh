#!/system/bin/sh

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 3
done

DOH_BIN="/data/local/tmp/doh-stub-rust"
LOG_FILE="/data/local/tmp/dns_log.log"
NOBODY_UID="9999"
LISTEN_PORT="5300"

export LD_LIBRARY_PATH="/data/local/tmp"

check_and_kill_ipv6() {
    local needs_fix=0
    for f in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
        if [ "$(cat "$f" 2>/dev/null)" = "0" ]; then
            needs_fix=1
            break
        fi
    done

    if [ "$needs_fix" = "1" ]; then
        for f in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
            echo 1 > "$f" 2>/dev/null
        done
        
        apply_iptables
    fi
}

apply_iptables() {
    
    if ! iptables -t nat -C OUTPUT -m owner --uid-owner $NOBODY_UID -j ACCEPT 2>/dev/null; then
        iptables -t nat -D OUTPUT -m owner --uid-owner $NOBODY_UID -j ACCEPT 2>/dev/null
        iptables -t nat -I OUTPUT 1 -m owner --uid-owner $NOBODY_UID -j ACCEPT
    fi

    if ! iptables -t nat -C OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $LISTEN_PORT 2>/dev/null; then
        iptables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-ports $LISTEN_PORT 2>/dev/null
        iptables -t nat -I OUTPUT 2 -p udp --dport 53 -j REDIRECT --to-ports $LISTEN_PORT
    fi

    
    if ! iptables -t nat -C OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $LISTEN_PORT 2>/dev/null; then
        iptables -t nat -D OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports $LISTEN_PORT 2>/dev/null
        iptables -t nat -I OUTPUT 2 -p tcp --dport 53 -j REDIRECT --to-ports $LISTEN_PORT
    fi
}

start_doh() {
    if ! pgrep -f "$DOH_BIN" >/dev/null; then
        pkill -9 -f "doh-stub-rust" 2>/dev/null
        su $NOBODY_UID:3003,3004,3005 -s /system/bin/sh -c "export LD_LIBRARY_PATH=/data/local/tmp && cd /data/local/tmp && nohup $DOH_BIN -p $LISTEN_PORT -d https://dns.google/dns-query > $LOG_FILE 2>&1 &"
    fi
}


while true; do
    check_and_kill_ipv6
    start_doh
    apply_iptables
    sleep 10
done
