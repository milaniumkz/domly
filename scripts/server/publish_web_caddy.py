#!/usr/bin/env python3
"""Add application routes while preserving existing Caddy site configuration."""
import os
import pathlib
import re
import shutil
import subprocess
app = pathlib.Path(os.environ.get('APP_DIR', '/opt/domly-backend'))
config = pathlib.Path('/etc/caddy/Caddyfile')
source = config.read_text()
marker = 'import /etc/caddy/domly-apps.caddy'
if marker not in source:
    match = re.search(r'(?m)^[ \t]*domly\.kz[^\n{]*\{', source)
    if not match:
        raise SystemExit('Existing domly.kz Caddy site not found; configuration preserved')
    source = source[:match.end()] + '\n\t' + marker + source[match.end():]
snippet = pathlib.Path('/etc/caddy/domly-apps.caddy')
snippet.write_text((app / 'current/backend/caddy-apps.caddy').read_text().replace('DOMLY_APP_DIR', str(app)))
snippet.chmod(0o644)
candidate = config.with_name('Caddyfile.domly-candidate')
candidate.write_text(source)
candidate.chmod(0o644)
subprocess.run(['caddy', 'validate', '--config', str(candidate), '--adapter', 'caddyfile'], check=True)
backup = app / 'backups' / ('Caddyfile-' + os.environ['GITHUB_SHA'])
shutil.copy2(config, backup)
os.replace(candidate, config)
try:
    subprocess.run(['systemctl', 'reload', 'caddy'], check=True)
except subprocess.CalledProcessError:
    shutil.copy2(backup, config)
    subprocess.run(['systemctl', 'reload', 'caddy'], check=True)
    raise
print('Customer, Pro and admin web routes published through Caddy')
