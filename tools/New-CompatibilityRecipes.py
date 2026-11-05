"""Build local-only deterministic patch recipes from original/user-tested probes.

This developer tool needs Python; the shipped assistant does not. Recipe literals
contain third-party archive metadata: keep the output outside the public source.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile


def build_recipe(source, target, destination):
    operations = []

    def copy(offset, length):
        if not length:
            return
        if operations and operations[-1][0] == 0 and operations[-1][1] + operations[-1][2] == offset:
            previous = operations.pop()
            operations.append((0, previous[1], previous[2] + length))
        else:
            operations.append((0, offset, length))

    def literal(offset, length):
        if length:
            operations.append((1, offset, length))

    if zipfile.is_zipfile(source):
        with zipfile.ZipFile(source) as original, zipfile.ZipFile(target) as patched:
            old = sorted(original.infolist(), key=lambda i: i.header_offset)
            new = sorted(patched.infolist(), key=lambda i: i.header_offset)
            old_ranges = {item.filename: (item.header_offset,
                          (old[index + 1].header_offset if index + 1 < len(old) else original.start_dir) - item.header_offset)
                          for index, item in enumerate(old)}
            for index, item in enumerate(new):
                length = (new[index + 1].header_offset if index + 1 < len(new) else patched.start_dir) - item.header_offset
                if item.filename.lower() == 'manifest.sii':
                    literal(item.header_offset, length)
                else:
                    offset, old_length = old_ranges[item.filename]
                    if old_length != length:
                        raise ValueError('Unexpected changed archive payload')
                    copy(offset, length)
            literal(patched.start_dir, target.stat().st_size - patched.start_dir)
    else:
        # Probe builder changed exactly one 32-byte HashFS v1 table entry and
        # appended the new manifest. Locate that entry without embedding assets.
        with source.open('rb') as a, target.open('rb') as b:
            header = a.read(32)
            if header[:12] != b'SCS#\x01\0\0\0CITY':
                raise ValueError('Unsupported source archive')
            count, table = struct.unpack_from('<II', header, 12)
            a.seek(table)
            b.seek(table)
            changes = [table + i * 32 for i in range(count) if a.read(32) != b.read(32)]
            if len(changes) != 1:
                raise ValueError('Expected one changed HashFS table entry')
            position = changes[0]
            copy(0, position)
            literal(position, 32)
            copy(position + 32, source.stat().st_size - position - 32)
            literal(source.stat().st_size, target.stat().st_size - source.stat().st_size)

    digest = hashlib.sha256()
    size = 0
    with destination.open('xb') as recipe, source.open('rb') as a, target.open('rb') as b:
        recipe.write(b'ETSPAT01' + struct.pack('<I', len(operations)))
        for kind, offset, length in operations:
            recipe.write(bytes([kind]))
            recipe.write(struct.pack('<qq', offset, length) if kind == 0 else struct.pack('<q', length))
            stream = a if kind == 0 else b
            stream.seek(offset)
            remaining = length
            while remaining:
                block = stream.read(min(remaining, 8 * 1024 * 1024))
                if not block:
                    raise ValueError('Truncated source')
                digest.update(block)
                if kind == 1:
                    recipe.write(block)
                size += len(block)
                remaining -= len(block)
    with target.open('rb') as stream:
        expected = hashlib.file_digest(stream, 'sha256').hexdigest()
    if digest.hexdigest() != expected or size != target.stat().st_size:
        raise ValueError('Recipe does not reproduce user-tested output')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('originals', type=Path)
    parser.add_argument('probes', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if not any(part in ('local', 'work', 'dist') for part in output.parts):
        parser.error('Recipe output must be under an ignored local/work/dist directory')
    output.mkdir(parents=True, exist_ok=False)
    report = json.loads((args.probes / 'probe-report.json').read_text(encoding='utf-8'))
    files = []
    for index, row in enumerate(report):
        source, target = args.originals / row['name'], args.probes / row['name']
        with source.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != row['original_sha256']:
                raise ValueError('Original hash mismatch')
        recipe = output / f'{index + 1:02}.etspatch'
        print(f"Recipe: {row['name']}", flush=True)
        build_recipe(source, target, recipe)
        with recipe.open('rb') as stream:
            patch_hash = hashlib.file_digest(stream, 'sha256').hexdigest()
        files.append({'File': row['name'], 'OriginalSha256': row['original_sha256'],
                      'PatchedSha256': row['output_sha256'], 'OriginalSize': source.stat().st_size,
                      'PatchedSize': target.stat().st_size, 'Patch': recipe.name, 'PatchSha256': patch_hash})
    profile = {'Id': 'promods-161-to-162', 'GameVersion': '1.62', 'Schema': 1,
               'UserTested': '2026-11-05', 'Files': files}
    (output / 'profile.json').write_text(json.dumps(profile, indent=2, ensure_ascii=False), encoding='utf-8')


if __name__ == '__main__':
    main()
