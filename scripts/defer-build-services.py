"""Defer specific service actions during dpkg configure, with an audit record."""
from pathlib import Path
import re
import sys

record = Path(sys.argv[1])
manifest = []
for path in (Path('/var/lib/dpkg/info/yunshu.postinst'),
             Path('/opt/apps/yunshu/files/script/daemon.sh')):
    text = path.read_text()
    # Match complete, reviewed commands, including the vendor's quoted shell bodies.
    pattern = re.compile(
        r'systemctl (?:(?:--user )?daemon-reload|'
        r'(?:enable|start|restart) \$\{PROCESS_NAME\}-(?:daemon|updater))'
    )
    def replace(match):
        manifest.append(f'{path}: {match.group(0)}')
        return "printf '[Docker build] service action deferred to runtime\\n'"
    path.write_text(pattern.sub(replace, text))
if len(manifest) != 11:
    raise SystemExit(f'Unexpected installer service calls: {len(manifest)}; review this DEB')
(record / 'deferred-services.txt').write_text('\n'.join(manifest) + '\n')
print('\n'.join(manifest))
