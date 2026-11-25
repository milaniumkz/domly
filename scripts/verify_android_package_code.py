#!/usr/bin/env python3
"""Reject APK/AAB files containing stale Flutter native code after Gradle merging."""
import argparse
import hashlib
import struct
import zipfile
from pathlib import Path


def code_sections(data):
    if data[:6] != b'\x7fELF\x02\x01':
        raise ValueError('Expected a little-endian ELF64 library')
    header = struct.unpack_from('<16sHHIQQQIHHHHHH', data)
    offset, size, count, names_index = header[6], header[11], header[12], header[13]
    sections = [struct.unpack_from('<IIQQQQIIQQ', data, offset + i * size)
                for i in range(count)]
    names_section = sections[names_index]
    names = data[names_section[4]:names_section[4] + names_section[5]]
    result = {}
    for section in sections:
        name = names[section[0]:].split(b'\0', 1)[0].decode()
        if name in ('.text', '.rodata'):
            result[name] = hashlib.sha256(
                data[section[4]:section[4] + section[5]]).hexdigest()
    if len(result) != 2:
        raise ValueError('Missing Flutter code or snapshot section')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected', type=Path, required=True,
                        help='Fresh Flutter arm64-v8a/app.so before Gradle merging')
    parser.add_argument('--package', type=Path, required=True, help='Final APK or AAB')
    args = parser.parse_args()
    expected = code_sections(args.expected.read_bytes())
    with zipfile.ZipFile(args.package) as archive:
        candidates = [name for name in archive.namelist()
                      if name in ('lib/arm64-v8a/libapp.so',
                                  'base/lib/arm64-v8a/libapp.so')]
        if len(candidates) != 1:
            raise SystemExit('FAIL: expected exactly one arm64 Flutter library')
        actual = code_sections(archive.read(candidates[0]))
    if actual != expected:
        raise SystemExit('FAIL: packaged Flutter code differs from current AOT output; '
                         'rebuild in a clean directory before publishing')
    print('PASS: packaged Flutter code and snapshot match current AOT output')


if __name__ == '__main__':
    main()
