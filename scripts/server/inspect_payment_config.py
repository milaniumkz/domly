"""Read-only audit of payment configuration presence; never emits values."""
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
keys = (
    'BCC_MERCHANT_ID', 'BCC_TERMINAL_ID', 'BCC_PRIVATE_KEY', 'BCC_PUBLIC_KEY',
    'BCC_NOTIFY_URL', 'BCC_RETURN_URL', 'BCC_ECOMMERCE_URL',
    'BCC_ECOMMERCE_MERCHANT', 'BCC_ECOMMERCE_TERMINAL',
    'BCC_ECOMMERCE_MAC_KEY', 'BCC_ECOMMERCE_BACKREF', 'BCC_ECOMMERCE_NOTIFY_URL',
)
candidates = [root / 'shared/backend.env', root / 'backend/.env', root / 'current/backend/.env']
for folder in ('backups', 'releases'):
    candidates.extend(sorted((root / folder).glob('*/backend.env')))
    candidates.extend(sorted((root / folder).glob('*/backend/.env')))
candidates.extend(root.glob('functions/.env*'))
seen = set()
for path in candidates:
    if not path.is_file() or path.resolve() in seen:
        continue
    seen.add(path.resolve())
    values = {}
    for line in path.read_text().splitlines():
        name, separator, value = line.partition('=')
        if separator and name.strip() in keys:
            values[name.strip()] = bool(value.strip().strip('\"\''))
    print(json.dumps({'file': str(path.relative_to(root)), 'configured': values}))
print(json.dumps({'files_checked': len(seen)}))
