// ETS2 Mod Asistanı – tek dosyalık başlatıcı.
// Paketin zip'i exe'ye gömülüdür (kaynak adı "paket.zip"). Açılınca paketi C:\ETS2Konvoy'a
// (yazılamazsa %LOCALAPPDATA%\ETS2Konvoy) çıkarır ve asistanı başlatır. Her açılışta asistan
// ve araçlar yenilenir; kullanıcının verisi (asistan-durum.json, indirilen dosyalar) korunur.
// Derleme: tools\New-FriendPackage.ps1 -Exe (Windows'un kendi csc.exe'si, .NET Framework 4.5+).
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

static class Launcher
{
    const string Title = "ETS2 Mod Asistanı";

    [STAThread]
    static int Main(string[] args)
    {
        try
        {
            // Test için: --klasor <yol>
            string root = null;
            for (int i = 0; i + 1 < args.Length; i++)
                if (args[i] == "--klasor") root = Path.GetFullPath(args[i + 1]);
            if (root == null) root = PickRoot();

            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("paket.zip"))
            {
                if (s == null) throw new Exception("Exe'nin içinde paket yok.");
                Extract(s, root);
            }

            string script = Path.Combine(root, "asistan", "Start-Asistan.ps1");
            string ps = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe");
            var psi = new ProcessStartInfo(ps,
                "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + script + "\" -PackageRoot \"" + root + "\"");
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = root;
            Process.Start(psi);
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show("Asistan başlatılamadı:\r\n\r\n" + ex.Message, Title, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    static string PickRoot()
    {
        string[] candidates = {
            @"C:\ETS2Konvoy",
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ETS2Konvoy")
        };
        foreach (string d in candidates)
        {
            try
            {
                Directory.CreateDirectory(d);
                string probe = Path.Combine(d, ".yazma-testi");
                File.WriteAllText(probe, "");
                File.Delete(probe);
                return d;
            }
            catch { }
        }
        throw new Exception("Paketi açacak yazılabilir bir klasör bulunamadı.");
    }

    static void Extract(Stream zipStream, string root)
    {
        // Eski sürümden kalan asistan/araç dosyaları karışmasın
        foreach (string d in new[] { "asistan", "araclar" })
        {
            string p = Path.Combine(root, d);
            if (Directory.Exists(p)) Directory.Delete(p, true);
        }
        string rootFull = Path.GetFullPath(root).TrimEnd('\\') + "\\";
        using (var zip = new ZipArchive(zipStream, ZipArchiveMode.Read))
        {
            foreach (ZipArchiveEntry e in zip.Entries)
            {
                // PowerShell 5.1'in Compress-Archive'ı yol ayıracı olarak '\' yazabiliyor
                string rel = e.FullName.Replace('/', '\\');
                if (rel.EndsWith("\\")) continue;
                string dest = Path.GetFullPath(Path.Combine(root, rel));
                if (!dest.StartsWith(rootFull, StringComparison.OrdinalIgnoreCase)) continue;
                Directory.CreateDirectory(Path.GetDirectoryName(dest));
                using (Stream src = e.Open())
                using (Stream dst = File.Create(dest))
                    src.CopyTo(dst);
            }
        }
    }
}
