// Deterministic local patch reader. No mod content is included in this source.
using System;
using System.IO;
using System.Text;

namespace Ets2Mods
{
    public static class CompatibilityPatch
    {
        static void Copy(Stream source, Stream output, long length)
        {
            byte[] buffer = new byte[4 * 1024 * 1024];
            while (length > 0)
            {
                int read = source.Read(buffer, 0, (int)Math.Min(length, buffer.Length));
                if (read == 0) throw new InvalidDataException("Yama kaynağı eksik.");
                output.Write(buffer, 0, read);
                length -= read;
            }
        }

        public static void Apply(string source, string patch, string destination, long expectedSize)
        {
            using (var original = File.Open(source, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (var recipe = File.OpenRead(patch))
            using (var reader = new BinaryReader(recipe, Encoding.ASCII))
            using (var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                if (Encoding.ASCII.GetString(reader.ReadBytes(8)) != "ETSPAT01")
                    throw new InvalidDataException("Geçersiz uyumluluk yaması.");
                uint count = reader.ReadUInt32();
                if (count == 0 || count > 1000000 || expectedSize < 0)
                    throw new InvalidDataException("Geçersiz yama uzunluğu.");
                for (uint i = 0; i < count; i++)
                {
                    byte kind = reader.ReadByte();
                    long offset = kind == 0 ? reader.ReadInt64() : recipe.Position + 8;
                    long length = reader.ReadInt64();
                    Stream input = kind == 0 ? original : recipe;
                    if (kind > 1 || offset < 0 || length < 0 || offset > input.Length ||
                        length > input.Length - offset || length > expectedSize - output.Position)
                        throw new InvalidDataException("Yama aralığı dosya dışında.");
                    input.Position = offset;
                    Copy(input, output, length);
                }
                if (output.Position != expectedSize || recipe.Position != recipe.Length)
                    throw new InvalidDataException("Yama sonucu beklenen uzunlukta değil.");
                output.Flush(true);
            }
        }
    }
}
