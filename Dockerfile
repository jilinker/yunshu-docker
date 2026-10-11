# syntax=docker/dockerfile:1
FROM golang:1.25-bookworm AS browser-builder
ARG EASY_NOVNC_COMMIT=406c38a3ccfdd4170ab6c59b089d9f211b26517c
RUN git clone https://github.com/pgaskin/easy-novnc.git /src/easy-novnc \
    && cd /src/easy-novnc \
    && git checkout "$EASY_NOVNC_COMMIT" \
    && CGO_ENABLED=0 go build -mod=readonly -trimpath -ldflags='-s -w' -o /out/easy-novnc .
RUN apt-get update \
    && apt-get install -y --no-install-recommends libjpeg62-turbo \
    && dpkg-query -W -f='${Package} ${Version} ${Architecture}\n' libjpeg62-turbo > /out/libjpeg62-turbo.txt \
    && mkdir -p /out/libjpeg \
    && cp -a /usr/lib/aarch64-linux-gnu/libjpeg.so.62* /out/libjpeg/

FROM ubuntu:24.04
ARG TARGETARCH
ARG YUNSHU_DEB_SHA256=2a1318ae2b4fa519645e864eb5aca608d158eff90b38b9040f02ea4f8e5a3025
ENV DEBIAN_FRONTEND=noninteractive
RUN test "$TARGETARCH" = arm64 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       x11-apps libglib2.0-bin libnss3 libnspr4 \
       libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libgtk-3-0t64 \
       libpango-1.0-0 libcairo2 libxcomposite1 libxdamage1 libxrandr2 \
       libgbm1 libdrm2 libxkbcommon0 libasound2t64 libatspi2.0-0t64 \
       libx11-xcb1 libxtst6 libxss1 libsecret-1-0 libcurl4t64 libfuse2t64 \
       dante-server tigervnc-standalone-server tigervnc-tools flwm \
       dbus dbus-x11 xauth x11-utils fonts-wqy-microhei ca-certificates \
       s6 tini sudo bc iproute2 iptables procps psmisc curl file python3-minimal util-linux \
    && rm -rf /var/lib/apt/lists/*
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 at-spi2-core \
    && rm -rf /var/lib/apt/lists/*
# Yunshu's screenshot binary requires LIBJPEGTURBO_6.2; Ubuntu's libjpeg62 lacks it.
# Debian bookworm ARM64 uses an older compatible glibc and supplies this ABI.
COPY --from=browser-builder /out/libjpeg/ /usr/local/lib/
COPY --from=browser-builder /out/libjpeg62-turbo.txt /usr/local/share/yunshu-install/libjpeg62-turbo.txt
COPY --from=browser-builder /usr/share/doc/libjpeg62-turbo/copyright /usr/local/share/yunshu-install/libjpeg62-turbo.copyright
RUN if id ubuntu >/dev/null 2>&1; then \
        usermod -l yunshu -d /home/yunshu -m ubuntu && groupmod -n yunshu ubuntu; \
    else \
        useradd -m -u 1000 -s /bin/bash yunshu; \
    fi \
    && mkdir -p /home/yunshu/.config /etc/systemd/user /etc/xdg/autostart \
    && chown -R yunshu:yunshu /home/yunshu \
    && (getent passwd socks >/dev/null || useradd -r -s /usr/sbin/nologin socks)
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh
COPY installers/yunshu.deb /var/tmp/yunshu.deb
RUN /usr/local/bin/install-yunshu.sh /var/tmp/yunshu.deb "$YUNSHU_DEB_SHA256" \
    && rm /var/tmp/yunshu.deb
COPY --from=browser-builder /out/easy-novnc /usr/local/bin/easy-novnc
COPY config/ /etc/yunshu/
RUN for name in system-dbus session-dbus x11 window-manager yunshu-daemon yunshu-updater screenshot gui browser dante; do \
        mkdir -p "/etc/yunshu/services/$name"; \
        printf '#!/bin/sh\nexec /usr/local/bin/run-service.sh %s\n' "$name" > "/etc/yunshu/services/$name/run"; \
        printf '#!/bin/sh\nsleep 5\n' > "/etc/yunshu/services/$name/finish"; \
        chmod +x "/etc/yunshu/services/$name/run" "/etc/yunshu/services/$name/finish"; \
    done
ENV DISPLAY=:1 HOME=/home/yunshu XDG_RUNTIME_DIR=/run/user/1000 \
    XAUTHORITY=/run/yunshu/Xauthority \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
    XDG_SESSION_TYPE=x11 VNC_SIZE=1280x800
EXPOSE 7171/tcp 6080/tcp 5901/tcp
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
