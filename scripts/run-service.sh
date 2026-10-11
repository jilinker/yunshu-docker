#!/bin/bash
set -euo pipefail
exec 2>&1
as_user() { exec setpriv --reuid=yunshu --regid=yunshu --init-groups "$@"; }
wait_x11() {
    until setpriv --reuid=yunshu --regid=yunshu --init-groups xdpyinfo >/dev/null 2>&1; do sleep 1; done
}
case ${1:?Service name required} in
    system-dbus)
        exec dbus-daemon --system --nofork --nopidfile
        ;;
    session-dbus)
        as_user dbus-daemon --session --nofork --address="$DBUS_SESSION_BUS_ADDRESS"
        ;;
    yunshu-daemon|yunshu-updater)
        until [[ -S /run/dbus/system_bus_socket ]]; do sleep 1; done
        export HOME=/root
        unset DBUS_SESSION_BUS_ADDRESS DISPLAY XAUTHORITY XDG_RUNTIME_DIR
        cd /
        exec "/opt/apps/yunshu/files/bin/$1"
        ;;
    x11)
        as_user Xtigervnc :1 -rfbport 5901 -localhost no -SecurityTypes VncAuth \
            -rfbauth /home/yunshu/.vnc/passwd -geometry "$VNC_SIZE" -depth 24 \
            -auth "$XAUTHORITY" -nolisten tcp -AlwaysShared
        ;;
    window-manager)
        wait_x11
        as_user flwm
        ;;
    screenshot)
        wait_x11
        until [[ -S /run/user/1000/bus ]]; do sleep 1; done
        export LD_LIBRARY_PATH=/opt/apps/yunshu/files/plugin
        as_user /opt/apps/yunshu/files/bin/screenshot_server
        ;;
    gui)
        wait_x11
        until [[ -S /run/user/1000/bus ]] && pgrep -f '^/opt/apps/yunshu/files/bin/yunshu-daemon$' >/dev/null; do sleep 1; done
        # Docker blocks the namespace creation used by Chromium's setuid sandbox.
        # The vendor's own user service uses this same no-sandbox flag.
        as_user /opt/apps/yunshu/files/yunshu-cross --disable-http2 --no-sandbox
        ;;
    browser)
        exec easy-novnc --addr :6080 --host 127.0.0.1 --port 5901 --basic-ui
        ;;
    dante)
        exec /usr/local/bin/start-dante.sh
        ;;
    *) echo "Unknown service: $1" >&2; exit 1 ;;
esac
