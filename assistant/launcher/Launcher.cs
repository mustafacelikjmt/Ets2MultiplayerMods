// ETS2 Mod Asistanı – tek dosyalık başlatıcı.
// Paketin zip'i exe'ye gömülüdür (kaynak adı "paket.zip"). Açılınca paketi C:\ETS2Konvoy'a
// (yazılamazsa %LOCALAPPDATA%\ETS2Konvoy) çıkarır ve asistanı başlatır. Kullanıcının
// verisi (asistan-durum.json, indirilen dosyalar) her durumda korunur.
// Derleme: tools\New-FriendPackage.ps1 -Exe (Windows'un kendi csc.exe'si, .NET Framework 4.5+).
//
// ⚠️ SÜRÜM KARŞILAŞTIRMASI — BU EXE ARTIK TEK GÜNCELLEME YOLU DEĞİL.
// Asistan kendini MServer'dan güncelleyebiliyor (asistan\lib\Asistan.Update.ps1).
// Eskiden bu başlatıcı her açılışta asistan\ ve araclar\ klasörlerini SİLİP gömülü
// paketi yeniden açıyordu; o davranış kalsaydı kullanıcının indirdiği her güncelleme
// bir sonraki çift tıklamada GERİ ALINIRDI ve kimse sebebini anlamazdı (asistan
// "güncel" der, bir dahaki sefere yine eski sürüm açılır). Bu yüzden artık kurulu
// sürümün versionCode'u gömülü paketinkinden küçük DEĞİLSE açma adımı atlanıyor.
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
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

            // Test için: --baslatma — paketi aç ama asistanı çalıştırma.
            // Sürüm karşılaştırmasının doğruluğu (kendini güncellemiş bir kurulumun
            // GERİ ALINMAMASI) ancak böyle sınanabiliyor: asistan başlatılsaydı test
            // bir pencere açar ve orada beklerdi.
            bool start = Array.IndexOf(args, "--baslatma") < 0;

            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("paket.zip"))
            {
                if (s == null) throw new Exception("Exe'nin içinde paket yok.");
                Extract(s, root);
            }

            if (!start) return 0;

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
        string rootFull = Path.GetFullPath(root).TrimEnd('\\') + "\\";
        using (var zip = new ZipArchive(zipStream, ZipArchiveMode.Read))
        {
            // Gömülü paketin sürümü, kurulu olanınkinden YENİ değilse hiçbir şeye
            // dokunma: kullanıcı kendini sunucudan güncellemiş olabilir.
            int embedded = VersionCodeOf(ReadEntryText(zip, "asistan/version.json"));
            int installed = VersionCodeOf(ReadFileText(Path.Combine(root, "asistan\\version.json")));
            if (installed > 0 && embedded > 0 && installed >= embedded) return;

            // Eski sürümden kalan asistan/araç dosyaları karışmasın.
            foreach (string d in new[] { "asistan", "araclar" })
            {
                string p = Path.Combine(root, d);
                if (Directory.Exists(p)) Directory.Delete(p, true);
            }

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

    // version.json'dan versionCode'u okur. Tam bir JSON ayrıştırıcı yerine düzenli
    // ifade: dosyayı bizim araçlarımız üretiyor (tools\Publish-Assistant.ps1) ve tek
    // bir sayı için .NET Framework'e JSON bağımlılığı eklemenin karşılığı yok.
    // Alan yoksa 0 döner — güncelleme yeteneğinden ÖNCEKİ paketlerde yoktu ve o durumda
    // eski davranış (her açılışta aç) doğru olanı.
    static int VersionCodeOf(string json)
    {
        if (string.IsNullOrEmpty(json)) return 0;
        Match m = Regex.Match(json, "\"versionCode\"\\s*:\\s*(\\d+)");
        int value;
        return m.Success && int.TryParse(m.Groups[1].Value, out value) ? value : 0;
    }

    static string ReadEntryText(ZipArchive zip, string path)
    {
        foreach (ZipArchiveEntry e in zip.Entries)
        {
            if (string.Equals(e.FullName.Replace('\\', '/'), path, StringComparison.OrdinalIgnoreCase))
            {
                using (var reader = new StreamReader(e.Open(), Encoding.UTF8))
                    return reader.ReadToEnd();
            }
        }
        return null;
    }

    static string ReadFileText(string path)
    {
        try { return File.Exists(path) ? File.ReadAllText(path, Encoding.UTF8) : null; }
        catch { return null; }
    }
}
