#!/bin/bash
set -u
services=(/run/service/*)
for service in "${services[@]}"; do
    s6-svc -d "$service" || true
done
if ! s6-svwait -d -a -t 20000 "${services[@]}"; then
    echo 'Service shutdown exceeded 20s; terminating remaining service processes' >&2
    for service in "${services[@]}"; do
        s6-svc -k "$service" || true
    done
fi
exec s6-svscanctl -t /run/service
