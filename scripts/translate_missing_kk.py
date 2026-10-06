#!/usr/bin/env python3
import json
import re
import sys
import time
from pathlib import Path

import translators as ts

INPUT = Path('/tmp/domly_missing_kk.json')
OUTPUT = Path('/tmp/domly_kk_updates.json')
CACHE = Path('/tmp/domly_kk_translation_cache.json')

KK_CHARS = re.compile(r'[ӘәІіҢңҒғҮүҰұҚқӨөҺһ]')
RU_LETTERS = re.compile(r'[А-Яа-яЁё]')
ONLY_SAFE = re.compile(r'^[\d\s.,:;+/()№%₸KZTм²a-zA-Z_-]+$')


def should_keep(source: str) -> bool:
    text = source.strip()
    if not text:
        return True
    if KK_CHARS.search(text):
        return True
    if not RU_LETTERS.search(text):
        return True
    if ONLY_SAFE.match(text):
        return True
    if text.startswith('http://') or text.startswith('https://'):
        return True
    return False


def translate(source: str) -> str:
    if should_keep(source):
        return source
    last_error = None
    for engine in ('google', 'alibaba'):
        for attempt in range(3):
            try:
                result = ts.translate_text(
                    source,
                    translator=engine,
                    from_language='ru',
                    to_language='kk',
                    timeout=20,
                )
                result = str(result or '').strip()
                if result:
                    return result
            except Exception as exc:
                last_error = exc
                time.sleep(1.5 + attempt)
    raise RuntimeError(f'{source} -> {last_error}')


def save(cache, updates):
    CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=2), 'utf-8')
    OUTPUT.write_text(json.dumps(updates, ensure_ascii=False, indent=2), 'utf-8')


def main():
    rows = json.loads(INPUT.read_text('utf-8'))
    cache = json.loads(CACHE.read_text('utf-8')) if CACHE.exists() else {}
    updates = json.loads(OUTPUT.read_text('utf-8')) if OUTPUT.exists() else []
    done_ids = {row['id'] for row in updates}

    for index, row in enumerate(rows, 1):
        doc_id = row['id']
        source = row['source'].strip()
        if doc_id in done_ids:
            continue
        if source in cache:
            kk = cache[source]
        else:
            kk = translate(source)
            cache[source] = kk
            time.sleep(0.35)
        updates.append({'id': doc_id, 'source': source, 'kk': kk})
        done_ids.add(doc_id)
        if len(updates) % 25 == 0:
            save(cache, updates)
            print(f'{len(updates)}/{len(rows)}', flush=True)

    save(cache, updates)
    print(f'done {len(updates)}/{len(rows)}', flush=True)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
