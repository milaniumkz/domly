"""Owner-approved cleanup: only generated web bundles from old releases."""
import json
from pathlib import Path
import re
import shutil
import sys

root = Path(sys.argv[1]).resolve(strict=True)
requested = sys.argv[2]
if not re.fullmatch(r'[0-9a-f]{40}', requested):
    raise SystemExit('invalid release hash')
releases = (root / 'releases').resolve(strict=True)
current = (root / 'current').resolve(strict=True)
if current.parent != releases or root == Path('/'):
    raise SystemExit('unexpected current release path')
versions = [p for p in releases.iterdir() if re.fullmatch(r'[0-9a-f]{40}', p.name) and p.is_dir() and not p.is_symlink()]
keep = {current.name, requested, *[p.name for p in sorted(versions, key=lambda p: p.stat().st_mtime, reverse=True)[:5]]}
targets = []
for version in versions:
    if version.name in keep:
        continue
    generated = version / 'frontend' / 'releases' / 'current'
    if not generated.is_dir() or generated.is_symlink():
        continue
    if generated.resolve() != generated:
        raise SystemExit('generated path traverses a symlink')
    targets.append(generated)
if '--apply' not in sys.argv:
    raise SystemExit('explicit --apply required')
before = shutil.disk_usage(root).free
for generated in targets:
    shutil.rmtree(generated)
print(json.dumps({'removedGeneratedWebBundles': len(targets), 'retainedReleases': len(keep), 'freedBytes': shutil.disk_usage(root).free - before, 'databaseAndBackupsUntouched': True}))
