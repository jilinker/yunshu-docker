#!/bin/bash
set -euo pipefail
for service in system-dbus session-dbus x11 window-manager yunshu-daemon yunshu-updater screenshot gui browser dante; do
    s6-svstat -o up /run/service/"$service" | grep -qx true
done
pgrep -f '^/opt/apps/yunshu/files/yunshu-cross' >/dev/null
timeout 3 bash -c 'exec 3<>/dev/tcp/127.0.0.1/7171'
curl --noproxy '*' --fail --silent --max-time 3 http://127.0.0.1:6080/ >/dev/null
