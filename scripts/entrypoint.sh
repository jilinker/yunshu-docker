#!/bin/bash
set -euo pipefail
umask 022
mkdir -p /run/yunshu /run/dbus /run/user/1000 /home/yunshu/.vnc /var/lib/yunshu
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
chmod 700 /run/user/1000 /home/yunshu/.vnc
chown yunshu:yunshu /run/user/1000 /home/yunshu/.vnc /run/yunshu
if [[ ! -s /var/lib/yunshu/machine-id ]]; then
    dbus-uuidgen > /var/lib/yunshu/machine-id
fi
cp /var/lib/yunshu/machine-id /etc/machine-id
mkdir -p /var/lib/dbus
ln -sf /etc/machine-id /var/lib/dbus/machine-id

for name in config db logs tmp; do
    source=/opt/apps/yunshu/files/$name
    target=/var/lib/yunshu/$name
    if [[ ! -e "$target" ]]; then
        cp -a "/usr/local/share/yunshu-state-defaults/$name" "$target"
    fi
    if [[ ! -L "$source" ]]; then
        rm -rf "$source"
        ln -s "$target" "$source"
    fi
done
# Package version is image metadata, not a remembered login preference.
cp /usr/local/share/yunshu-state-defaults/config/version.ini /var/lib/yunshu/config/version.ini
chown -R yunshu:yunshu /var/lib/yunshu/logs /var/lib/yunshu/tmp

if [[ -n ${VNC_PASSWORD_FILE:-} ]]; then
    VNC_PASSWORD=$(cat "$VNC_PASSWORD_FILE")
fi
if [[ -n ${VNC_PASSWORD:-} ]]; then
    printf %s "$VNC_PASSWORD" | tigervncpasswd -f > /home/yunshu/.vnc/passwd
    rm -f /home/yunshu/.vnc/initial-password
elif [[ ! -s /home/yunshu/.vnc/passwd ]]; then
    # Store the initial password locally instead of printing it into Docker logs.
    head -c 6 /dev/urandom | base64 > /home/yunshu/.vnc/initial-password
    tigervncpasswd -f < /home/yunshu/.vnc/initial-password > /home/yunshu/.vnc/passwd
    echo 'Generated VNC password: /home/yunshu/.vnc/initial-password'
fi
chmod 600 /home/yunshu/.vnc/*
chown -R yunshu:yunshu /home/yunshu/.vnc
unset VNC_PASSWORD
rm -f /run/yunshu/Xauthority
touch /run/yunshu/Xauthority
xauth -f /run/yunshu/Xauthority add :1 MIT-MAGIC-COOKIE-1 "$(mcookie)"
chown yunshu:yunshu /run/yunshu/Xauthority
chmod 600 /run/yunshu/Xauthority
rm -rf /run/service
cp -a /etc/yunshu/services /run/service
mkdir -p /run/service/.s6-svscan
printf '#!/bin/sh\nexec /usr/local/bin/stop-services.sh\n' > /run/service/.s6-svscan/SIGTERM
chmod +x /run/service/.s6-svscan/SIGTERM
echo 'Starting Yunshu, GUI :6080, VNC :5901, SOCKS5 :7171'
exec s6-svscan /run/service
