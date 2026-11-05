// Microsoft RDP ActiveX host. Never decrypts or stores passwords.
// https://learn.microsoft.com/windows/win32/termserv/imsrdpextendedsettings-property
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using AxMSTSCLib;
using MSTSCLib;

static class StableRdpClient
{
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    static Dictionary<string,string> ReadSettings(string path)
    {
        var values = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        foreach(string line in File.ReadAllLines(path))
        {
            int first=line.IndexOf(':'), second=first<0?-1:line.IndexOf(':',first+1);
            if(first<0 || second<0) continue;
            string key=line.Substring(0,first);
            // Only non-secret connection/display settings are consumed.
            if(key=="full address" || key=="username" || key=="domain" || key=="authentication level")
                values[key]=line.Substring(second+1);
        }
        if(!values.ContainsKey("full address")) throw new Exception("RDP dosyasında sunucu adresi yok.");
        return values;
    }

    [STAThread]
    static int Main(string[] args)
    {
        bool selfTest=args.Length>0 && args[0]=="--self-test";
        try
        {
            SetProcessDPIAware();
            Application.EnableVisualStyles();
            using(var form=new Form())
            using(var client=new AxMsRdpClient9NotSafeForScripting())
            {
                form.Text="OfisPC - Sabit Fare (RDP)";
                form.Size=new Size(1400,900);
                form.MinimumSize=new Size(900,650);
                form.StartPosition=FormStartPosition.CenterScreen;
                form.WindowState=FormWindowState.Maximized;
                var header=new Label { Dock=DockStyle.Top, Height=36, TextAlign=ContentAlignment.MiddleLeft,
                    Text="Bağıl fare etkin · Uzak imleç sıçramaları engelleniyor · Bağlantı hazırlanıyor…" };
                ((System.ComponentModel.ISupportInitialize)client).BeginInit();
                client.Dock=DockStyle.Fill;
                form.Controls.Add(client); form.Controls.Add(header);
                ((System.ComponentModel.ISupportInitialize)client).EndInit();
                var formHandle=form.Handle;
                var clientHandle=client.Handle;
                var extended=(IMsRdpExtendedSettings)client.GetOcx();
                object enabled=true;
                extended.set_Property("IgnoreServerGeneratedMouseMoves",ref enabled);
                client.AdvancedSettings7.RelativeMouseMode=true;
                bool allowRelative=false;
                try
                {
                    extended.set_Property("AllowRelativeMouseMode",ref enabled);
                    allowRelative=Convert.ToBoolean(extended.get_Property("AllowRelativeMouseMode"));
                }
                catch(COMException) { /* Optional on pre-24H2 clients. */ }
                bool ignore=Convert.ToBoolean(extended.get_Property("IgnoreServerGeneratedMouseMoves"));
                bool relative=client.AdvancedSettings7.RelativeMouseMode;
                if(!ignore || !relative) throw new Exception("Fare ayarları RDP denetiminde doğrulanamadı.");
                if(selfTest)
                {
                    if(args.Length>2) ReadSettings(args[2]);
                    string report="{\"IgnoreServerGeneratedMouseMoves\":"+ignore.ToString().ToLowerInvariant()+
                        ",\"RelativeMouseMode\":"+relative.ToString().ToLowerInvariant()+
                        ",\"AllowRelativeMouseMode\":"+allowRelative.ToString().ToLowerInvariant()+
                        ",\"ConnectionAttempted\":false}";
                    if(args.Length>1) File.WriteAllText(args[1],report,new UTF8Encoding(false));
                    return 0;
                }
                if(args.Length!=1) throw new Exception("Bir RDP bağlantı dosyası seçilmeli.");
                var settings=ReadSettings(args[0]);
                string server=settings["full address"];
                int port=3389, colon=server.LastIndexOf(':');
                if(colon>0 && server.IndexOf(':')==colon)
                {
                    if(!int.TryParse(server.Substring(colon+1),out port)) throw new Exception("Geçersiz RDP portu.");
                    server=server.Substring(0,colon);
                }
                client.Server=server;
                if(settings.ContainsKey("username")) client.UserName=settings["username"];
                if(settings.ContainsKey("domain")) client.Domain=settings["domain"];
                client.AdvancedSettings2.RDPPort=port;
                client.AdvancedSettings7.EnableCredSspSupport=true;
                client.AdvancedSettings6.AuthenticationLevel=2;
                client.ColorDepth=32;
                client.AdvancedSettings2.SmartSizing=false;
                client.AdvancedSettings7.EnableAutoReconnect=true;
                client.DesktopWidth=Math.Max(800,form.ClientSize.Width);
                client.DesktopHeight=Math.Max(600,form.ClientSize.Height-header.Height);
                client.OnConnected+=(sender,e)=> {
                    bool activeIgnore=Convert.ToBoolean(extended.get_Property("IgnoreServerGeneratedMouseMoves"));
                    bool activeRelative=client.AdvancedSettings7.RelativeMouseMode;
                    header.Text=activeIgnore && activeRelative ?
                        "Bağlandı · Bağıl fare etkin · Uzak imleç taşıma komutları engelleniyor" :
                        "Bağlandı; fare ayarları etkin değil. Bu pencereyi kapatıp durumu bildir.";
                    try { File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"connection-status.json"),
                        "{\"Connected\":true,\"IgnoreServerGeneratedMouseMoves\":"+activeIgnore.ToString().ToLowerInvariant()+
                        ",\"RelativeMouseMode\":"+activeRelative.ToString().ToLowerInvariant()+"}"); }
                    catch(IOException) { }
                };
                client.OnDisconnected+=(sender,e)=> { header.Text="Bağlantı kapandı (kod "+e.discReason+"). Yeniden bağlanmak için pencereyi yeniden aç."; };
                form.Shown+=(sender,e)=> {
                    // Use the final, DPI-aware viewport rather than the hidden
                    // form's initial size, so pointer and image coordinates agree.
                    client.DesktopWidth=Math.Max(800,client.ClientSize.Width);
                    client.DesktopHeight=Math.Max(600,client.ClientSize.Height);
                    client.Connect();
                };
                form.FormClosing+=(sender,e)=> { try { if(client.Connected!=0) client.Disconnect(); } catch(COMException) { } };
                Application.Run(form);
                return 0;
            }
        }
        catch(Exception ex)
        {
            if(selfTest) { if(args.Length>1) File.WriteAllText(args[1],ex.ToString()); }
            else MessageBox.Show(ex.Message,"RDP fare bağlantısı",MessageBoxButtons.OK,MessageBoxIcon.Error);
            return 1;
        }
    }
}
