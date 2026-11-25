#!/usr/bin/env python3
"""Compare Flutter Mach-O code/snapshot sections before and after IPA export."""
import hashlib
import struct
import argparse
import zipfile
from pathlib import Path


def code_sections(data):
    if data[:4] == bytes.fromhex('cafebabe'):
        count = struct.unpack_from('>I', data, 4)[0]
        if count != 1:
            raise ValueError('Expected one iOS architecture')
        _, _, offset, size, _ = struct.unpack_from('>IIIII', data, 8)
        data = data[offset:offset + size]
    if data[:4] != bytes.fromhex('cffaedfe'):
        raise ValueError('Expected little-endian 64-bit Mach-O')
    count = struct.unpack_from('<I', data, 16)[0]
    offset = 32
    result = {}
    for _ in range(count):
        command, size = struct.unpack_from('<II', data, offset)
        if command == 0x19:
            section_count = struct.unpack_from('<I', data, offset + 64)[0]
            for index in range(section_count):
                section = struct.unpack_from('<16s16sQQIIIIIIII', data, offset + 72 + index * 80)
                name = section[0].split(b'\0')[0]
                segment = section[1].split(b'\0')[0]
                if segment == b'__TEXT' and name in (b'__text', b'__const', b'__cstring', b'__ustring'):
                    result[name.decode()] = hashlib.sha256(
                        data[section[4]:section[4] + section[3]]).hexdigest()
        offset += size
    if '__text' not in result or '__const' not in result:
        raise ValueError('Missing Flutter code or snapshot section')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected', type=Path, required=True)
    parser.add_argument('--package', type=Path, required=True)
    args = parser.parse_args()
    expected = code_sections(args.expected.read_bytes())
    with zipfile.ZipFile(args.package) as archive:
        candidates = [name for name in archive.namelist()
                      if name.endswith('/App.framework/App')]
        if len(candidates) != 1:
            raise SystemExit('FAIL: expected one Flutter App framework')
        actual = code_sections(archive.read(candidates[0]))
    if expected != actual:
        raise SystemExit('FAIL: packaged iOS code differs from current AOT output')
    print('PASS: packaged iOS code and snapshot match current AOT output')


if __name__ == '__main__':
    main()
