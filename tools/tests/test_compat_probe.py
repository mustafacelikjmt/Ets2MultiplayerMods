import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
import zlib

spec = importlib.util.spec_from_file_location('probe', Path(__file__).parents[1] / 'prepare_compat_probe.py')
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)
MANIFEST = b'SiiNunit\r\r\n{\r\r\nmod_package : .test {\r\r\n display_name: "Test"\r\r\n compatible_versions[]: "1.61.*"\r\r\n}\r\r\n}'


class ProbeTests(unittest.TestCase):
    def test_zip_keeps_payload_and_one_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            src, dst = Path(directory) / 'original.scs', Path(directory) / 'probe.scs'
            with zipfile.ZipFile(src, 'w', compression=zipfile.ZIP_DEFLATED) as z:
                z.writestr('manifest.sii', MANIFEST)
                z.writestr('map/test.base', b'unchanged map' * 1000)
                z.comment = b'preserved'
            before = src.read_bytes()
            updated = probe.update_manifest(MANIFEST, '1.62')
            self.assertIn(b'"1.62.*"', updated)
            probe.build_zip(src, dst, updated)
            with zipfile.ZipFile(dst) as z:
                self.assertIsNone(z.testzip())
                self.assertEqual(z.read('map/test.base'), b'unchanged map' * 1000)
                self.assertEqual(z.namelist().count('manifest.sii'), 1)
                self.assertEqual(z.comment, b'preserved')
            self.assertEqual(src.read_bytes(), before)
            self.assertEqual(probe.manifest(dst)[0], updated)

    def test_hashfs_preserves_other_entry_and_original(self):
        for flags in (4, 6):
            with self.subTest(flags=flags), tempfile.TemporaryDirectory() as directory:
                src, dst = Path(directory) / 'original.scs', Path(directory) / 'probe.scs'
                packed = zlib.compress(MANIFEST) if flags & 2 else MANIFEST
                header = b'SCS#' + struct.pack('<HH4sII', 1, 0, b'CITY', 2, 4096)
                raw = bytearray(header.ljust(4096, b'\0'))
                raw += probe.ENTRY.pack(10, 8192, flags, zlib.crc32(MANIFEST), len(MANIFEST), len(packed))
                raw += probe.ENTRY.pack(11, 8000, 4, zlib.crc32(b'unchanged'), 9, 9)
                raw = raw.ljust(8000, b'\0') + b'unchanged'
                raw = raw.ljust(8192, b'\0') + packed
                src.write_bytes(raw)
                data, metadata = probe.manifest(src)
                updated = probe.update_manifest(data, '1.62')
                probe.build_hashfs(src, dst, updated, metadata)
                result = dst.read_bytes()
                self.assertEqual(probe.manifest(dst)[0], updated)
                self.assertEqual(result[:4096], raw[:4096])
                self.assertEqual(result[4128:len(raw)], raw[4128:])
                self.assertEqual(src.read_bytes(), raw)


if __name__ == '__main__':
    unittest.main()
