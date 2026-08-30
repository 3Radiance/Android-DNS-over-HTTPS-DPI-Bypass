#!/system/bin/sh

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 3
done

NFQWS_DIR="/data/adb/modules/nfqws_custom"
NFQWS_BIN="$NFQWS_DIR/nfqws"
HOST_LIST="/data/local/tmp/hosts.txt"
QNUM=300

apply_iptables() {
    V2RAY_UID=$(pm list packages -U | grep com.v2ray.ang.fdroid | sed 's/.*uid://')

    if [ -z "$V2RAY_UID" ]; then
        return
    fi

    if ! iptables -t mangle -C OUTPUT -p tcp -m owner --uid-owner nobody -j ACCEPT 2>/dev/null; then
        iptables -t mangle -D OUTPUT -p tcp -m owner --uid-owner nobody -j ACCEPT 2>/dev/null
        iptables -t mangle -I OUTPUT -p tcp -m owner --uid-owner nobody -j ACCEPT
    fi

    if ! iptables -t mangle -C OUTPUT -p tcp -m multiport --dports 80,443 -m owner --uid-owner "$V2RAY_UID" -j NFQUEUE --queue-num $QNUM 2>/dev/null; then
        iptables -t mangle -D OUTPUT -p tcp -m multiport --dports 80,443 -m owner --uid-owner "$V2RAY_UID" -j NFQUEUE --queue-num $QNUM 2>/dev/null
        iptables -t mangle -A OUTPUT -p tcp -m multiport --dports 80,443 -m owner --uid-owner "$V2RAY_UID" -j NFQUEUE --queue-num $QNUM
    fi
}

start_nfqws() {
    if ! pgrep -f "$NFQWS_BIN" >/dev/null; then
        nohup $NFQWS_BIN --qnum=$QNUM \
          --user=nobody \
          --bind-fix4 \
          --bind-fix6 \
          --hostlist=$HOST_LIST \
          --dpi-desync=fake,multisplit \
          --dpi-desync-split-seqovl=345 \
          --dpi-desync-split-pos=1 \
          --dpi-desync-fooling=ts \
          --dpi-desync-repeats=4 \
          --dpi-desync-fake-tls-mod=rnd,dupsid,sni=cloudflare.com > /data/local/tmp/nfqws_log.log 2>&1 &
    fi
}

while true; do
    start_nfqws
    apply_iptables
    sleep 10
done
