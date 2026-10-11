#!/bin/bash
set -euo pipefail
package=${1:?DEB path is required}
expected=${2:?SHA256 is required}
printf '%s  %s\n' "$expected" "$package" | sha256sum -c -
test "$(dpkg-deb -f "$package" Architecture)" = arm64
test "$(dpkg-deb -f "$package" Package)" = yunshu
record=/usr/local/share/yunshu-install
mkdir -p "$record" /etc/systemd/system /etc/systemd/user /var/log
dpkg --unpack "$package"
cp /var/lib/dpkg/info/yunshu.postinst "$record/postinst.original"
cp /opt/apps/yunshu/files/script/daemon.sh "$record/daemon.sh.original"
# Patch only reviewed build-time service calls; keep the original files for runtime.
python3 /usr/local/bin/defer-build-services.py "$record"
# The vendor backend uses a relative log path, so configure from the filesystem root.
cd /
# This package's postinst refers to PROCESS_NAME without defining it.
PROCESS_NAME=yunshu dpkg --configure yunshu
cp "$record/postinst.original" /var/lib/dpkg/info/yunshu.postinst
cp "$record/daemon.sh.original" /opt/apps/yunshu/files/script/daemon.sh
chmod 755 /opt/apps/yunshu/files/script/daemon.sh
cp /var/log/yunshu.install.log "$record/backend-install.log"
test -x /opt/apps/yunshu/files/bin/yunshu-daemon
test -x /opt/apps/yunshu/files/bin/yunshu-updater
test -x /opt/apps/yunshu/files/yunshu-cross
test -f /etc/systemd/system/yunshu-daemon.service
test -f /etc/systemd/system/yunshu-updater.service
test -f /etc/ld.so.conf.d/yunshu.conf
test -f /usr/lib/aarch64-linux-gnu/libeagleaudithook.so
test "$(stat -c %a /opt/apps/yunshu/files/chrome-sandbox)" = 4755
ldconfig
for program in /opt/apps/yunshu/files/yunshu-cross \
    /opt/apps/yunshu/files/bin/yunshu-daemon \
    /opt/apps/yunshu/files/bin/yunshu-updater \
    /opt/apps/yunshu/files/bin/screenshot_server; do
    ldd "$program" > "$record/$(basename "$program").ldd"
    if grep -q 'not found' "$record/$(basename "$program").ldd"; then
        echo "Missing libraries for $program:" >&2
        grep 'not found' "$record/$(basename "$program").ldd" >&2
        exit 1
    fi
done
defaults=/usr/local/share/yunshu-state-defaults
mkdir -p "$defaults"
for name in config db logs tmp; do
    mkdir -p "/opt/apps/yunshu/files/$name"
    cp -a "/opt/apps/yunshu/files/$name" "$defaults/$name"
done
dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' yunshu > "$record/package.txt"
