#!/bin/bash
set -euo pipefail
config=/run/yunshu/danted.conf
render() {
    cat /etc/yunshu/danted.conf
    ip -o address show | awk '{print $2}' | sort -u | while IFS= read -r interface; do
        printf 'external: %s\n' "$interface"
    done
    cat /etc/yunshu/danted.rules
}
render > "$config"
/usr/sbin/danted -V -f "$config"
/usr/sbin/danted -f "$config" &
dante_pid=$!
sleep_pid=
stop() {
    trap - EXIT TERM INT
    [[ -z "$sleep_pid" ]] || kill "$sleep_pid" 2>/dev/null || true
    kill "$dante_pid" 2>/dev/null || true
    wait "$dante_pid" 2>/dev/null || true
    exit 0
}
trap stop TERM INT
while kill -0 "$dante_pid" 2>/dev/null; do
    sleep 5 &
    sleep_pid=$!
    wait "$sleep_pid"
    sleep_pid=
    render > "$config.next"
    if ! cmp -s "$config" "$config.next"; then
        /usr/sbin/danted -V -f "$config.next"
        mv "$config.next" "$config"
        kill -HUP "$dante_pid"
        echo 'Reloaded Dante after an interface/address change'
    fi
done
wait "$dante_pid"
