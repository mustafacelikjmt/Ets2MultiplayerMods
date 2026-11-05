"""Prepare experimental version-gate probes; does NOT convert map/model formats.

Only ZIP and unencrypted HashFS v1 are supported. Originals are never modified.
Usage: python tools/prepare_compat_probe.py SOURCE OUTPUT --target 1.62
Without --build, only inspect manifests. Output must be outside SOURCE.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import zipfile
import zlib

ENTRY = struct.Struct('<QQIIII')


def hashfs_manifest(path):
    archive_size = path.stat().st_size
    with path.open('rb') as f:
        header = f.read(32)
        if header[:12] != b'SCS#\x01\x00\x00\x00CITY':
            raise ValueError('Only unsalted HashFS v1 CITY archives supported')
        count, table = struct.unpack_from('<II', header, 12)
        if table + count * ENTRY.size > archive_size:
            raise ValueError('Invalid HashFS entry table')
        f.seek(table)
        entries = f.read(count * ENTRY.size)
        matches = []
        for i in range(count):
            entry = ENTRY.unpack_from(entries, i * ENTRY.size)
            _, offset, flags, crc, size, packed = entry
            if flags & 1 or size > 65536 or size < 20:
                continue
            if flags & ~7 or offset + packed > archive_size:
                raise ValueError('Unsupported flags or invalid entry')
            f.seek(offset)
            raw = f.read(packed)
            data = zlib.decompress(raw) if flags & 2 else raw
            if len(data) != size or zlib.crc32(data) != crc:
                raise ValueError('HashFS entry length/CRC mismatch')
            if re.search(rb'\bmod_package\s*:', data) and data.lstrip().startswith(b'SiiNunit'):
                matches.append((data, table + i * ENTRY.size, entry))
        if len(matches) != 1:
            raise ValueError(f'Expected one manifest, found {len(matches)}')
        return matches[0]


def manifest(path):
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as z:
            items = [i for i in z.infolist() if i.filename.lower() == 'manifest.sii']
            if len(items) != 1:
                raise ValueError('Missing or duplicate ZIP manifest')
            return z.read(items[0]), None
    data, position, entry = hashfs_manifest(path)
    return data, (position, entry)


def update_manifest(data, target):
    text = data.decode('utf-8-sig').replace('\r\r\n', '\r\n')
    versions = re.findall(r'^\s*compatible_versions\[\d*\]\s*:\s*"([^"]+)"', text, re.M)
    if not versions or any(re.fullmatch(v.replace('.', r'\.').replace('*', '.*'), target + '.0') for v in versions):
        return None
    if versions != ['1.61.*']:
        raise ValueError(f'Unexpected source versions: {versions}')
    newline = '\r\n' if '\r\n' in text else '\n'
    # Keep the original restriction and add ONLY the requested test version.
    text = re.sub(r'(^[ \t]*compatible_versions\[\d*\][^\r\n]*)(\r?\n)',
                  lambda m: m[1] + m[2] + f'\tcompatible_versions[]: "{target}.*" # EXPERIMENTAL; runtime unverified' + newline,
                  text, count=1, flags=re.M)
    text = re.sub(r'(^\s*display_name\s*:\s*")([^"]+)(")',
                  lambda m: m[1] + m[2] + f' [TEST {target}]' + m[3], text, count=1, flags=re.M)
    return text.encode('utf-8')


def copy_n(source, dest, size):
    while size:
        block = source.read(min(size, 8 * 1024 * 1024))
        if not block:
            raise ValueError('Truncated archive')
        dest.write(block)
        size -= len(block)


def build_zip(source, dest, data):
    # Preserve every other local record verbatim, including compressed payloads,
    # descriptors and ZIP64 fields. zipfile regenerates only the central directory.
    with zipfile.ZipFile(source) as zin, source.open('rb') as raw, zipfile.ZipFile(dest, 'x', allowZip64=True) as zout:
        items = sorted(zin.infolist(), key=lambda i: i.header_offset)
        for index, info in enumerate(items):
            if info.filename.lower() == 'manifest.sii':
                continue
            end = items[index + 1].header_offset if index + 1 < len(items) else zin.start_dir
            cloned = copy.copy(info)
            cloned.header_offset = zout.fp.tell()
            raw.seek(info.header_offset)
            copy_n(raw, zout.fp, end - info.header_offset)
            zout.filelist.append(cloned)
            zout.NameToInfo[cloned.filename] = cloned
            zout.start_dir = zout.fp.tell()
            zout._didModify = True
        zout.comment = zin.comment
        zout.writestr('manifest.sii', data, compress_type=zipfile.ZIP_DEFLATED)


def build_hashfs(source, dest, data, metadata):
    position, entry = metadata
    # Exclusive creation prevents accidental overwrites or in-place edits.
    with source.open('rb') as src, dest.open('xb') as dst:
        shutil.copyfileobj(src, dst, 8 * 1024 * 1024)
        padding = (-dst.tell()) % 4096
        dst.write(b'\0' * padding)
        offset = dst.tell()
        packed = zlib.compress(data) if entry[2] & 2 else data
        dst.write(packed)
        dst.seek(position)
        dst.write(ENTRY.pack(entry[0], offset, entry[2], zlib.crc32(data), len(data), len(packed)))


def sha256(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--target', required=True)
    parser.add_argument('--build', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+', args.target):
        parser.error('Target must be major.minor')
    source, output = args.source.resolve(), args.output.resolve()
    if output == source or source in output.parents or output in source.parents:
        parser.error('Source and output must be separate directories')
    plans = []
    for path in sorted(source.iterdir()):
        if path.suffix.lower() not in ('.scs', '.zip'):
            continue
        original, metadata = manifest(path)
        updated = update_manifest(original, args.target)
        if updated:
            plans.append((path, updated, metadata))
    if args.build:
        output.mkdir(parents=True, exist_ok=True)
        if any((output / path.name).exists() for path, _, _ in plans):
            raise FileExistsError('Output already contains a planned archive')
    report = []
    for path, updated, metadata in plans:
        print(f'{"BUILD" if args.build else "PLAN"} {path.name}', flush=True)
        row = {'name': path.name, 'format': 'hashfs-v1' if metadata else 'zip',
               'target': args.target, 'status': 'experimental-version-gate-only'}
        if args.build:
            dest = output / path.name
            before = sha256(path)
            if metadata:
                build_hashfs(path, dest, updated, metadata)
            else:
                build_zip(path, dest, updated)
            if manifest(dest)[0] != updated:
                raise ValueError(f'Output manifest verification failed: {path.name}')
            if sha256(path) != before:
                raise ValueError(f'Source changed during build: {path.name}')
            row.update(original_sha256=before, output_sha256=sha256(dest))
        report.append(row)
    if args.build:
        (output / 'probe-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(f'{len(report)} experimental packages; map/model contents unchanged. Runtime test REQUIRED.')


if __name__ == '__main__':
    main()
