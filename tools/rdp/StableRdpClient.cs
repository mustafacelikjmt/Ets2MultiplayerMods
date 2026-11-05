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
    static float uiScale=1;
    static int Ui(int pixels) { return (int)Math.Round(pixels*uiScale); }

    sealed class DesktopWindow : Form
    {
        [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr window,int id,uint modifiers,uint key);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr window,int id);
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr window,int attribute,ref int value,int size);
        const int FullscreenHotkey=71;
        Rectangle windowedBounds;
        public bool IsFullscreen { get; private set; }
        public event EventHandler DisplayModeChanged;

        public DesktopWindow()
        {
            Text="OfisPC · Sabit Fare";
            BackColor=Color.FromArgb(18,22,30);
            Font=new Font("Segoe UI",10);
            AutoScaleMode=AutoScaleMode.None;
            StartPosition=FormStartPosition.Manual;
            var screen=Screen.FromPoint(Cursor.Position);
            windowedBounds=new Rectangle(screen.WorkingArea.Left+60,screen.WorkingArea.Top+60,
                Math.Min(1400,screen.WorkingArea.Width-120),Math.Min(900,screen.WorkingArea.Height-120));
            Bounds=windowedBounds;
            SetFullscreen(true);
        }
        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            // Dark native title bar is used only in windowed mode.
            int dark=1;
            try { DwmSetWindowAttribute(Handle,20,ref dark,sizeof(int)); } catch(DllNotFoundException) { }
        }
        protected override void OnActivated(EventArgs e)
        {
            base.OnActivated(e);
            RegisterHotKey(Handle,FullscreenHotkey,0x4003,(uint)Keys.F11); // Ctrl+Alt, no repeat
        }
        protected override void OnDeactivate(EventArgs e)
        {
            UnregisterHotKey(Handle,FullscreenHotkey);
            base.OnDeactivate(e);
        }
        protected override void OnHandleDestroyed(EventArgs e)
        {
            UnregisterHotKey(Handle,FullscreenHotkey);
            base.OnHandleDestroyed(e);
        }
        protected override void WndProc(ref Message message)
        {
            if(message.Msg==0x0312 && message.WParam.ToInt32()==FullscreenHotkey)
            { SetFullscreen(!IsFullscreen); return; }
            base.WndProc(ref message);
        }
        public void SetFullscreen(bool enabled)
        {
            if(enabled==IsFullscreen) return;
            SuspendLayout();
            if(enabled)
            {
                if(WindowState==FormWindowState.Normal) windowedBounds=Bounds;
                var screen=Screen.FromRectangle(Bounds);
                WindowState=FormWindowState.Normal;
                FormBorderStyle=FormBorderStyle.None;
                Bounds=screen.Bounds;
            }
            else
            {
                FormBorderStyle=FormBorderStyle.Sizable;
                WindowState=FormWindowState.Normal;
                Bounds=windowedBounds;
            }
            IsFullscreen=enabled;
            ResumeLayout(true);
            if(DisplayModeChanged!=null) DisplayModeChanged(this,EventArgs.Empty);
        }
    }

    static Button ToolbarButton(string text,int width)
    {
        var button=new Button { Text=text, Width=Ui(width), Height=Ui(32), FlatStyle=FlatStyle.Flat,
            ForeColor=Color.FromArgb(230,235,245), BackColor=Color.FromArgb(42,51,68),
            Margin=new Padding(Ui(4),Ui(4),0,Ui(4)), TabStop=false, Cursor=Cursors.Hand };
        button.FlatAppearance.BorderSize=0;
        button.FlatAppearance.MouseOverBackColor=Color.FromArgb(62,78,104);
        return button;
    }
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
            using(var graphics=Graphics.FromHwnd(IntPtr.Zero)) uiScale=graphics.DpiX/96f;
            Application.EnableVisualStyles();
            using(var form=new DesktopWindow())
            using(var client=new AxMsRdpClient9NotSafeForScripting())
            using(var displayTimer=new Timer { Interval=350 })
            using(var toolbarTimer=new Timer { Interval=150 })
            {
                // The toolbar overlays the image; it never reduces the RDP viewport.
                var toolbar=new FlowLayoutPanel { Height=Ui(40), Width=Ui(660), WrapContents=false,
                    BackColor=Color.FromArgb(25,31,43), Visible=true };
                var status=new Label { Width=Ui(402), Height=Ui(40), TextAlign=ContentAlignment.MiddleLeft,
                    Padding=new Padding(Ui(12),0,0,0), ForeColor=Color.FromArgb(134,211,255),
                    Text="●  OfisPC · Bağlantı hazırlanıyor…", Margin=Padding.Empty };
                var toggle=ToolbarButton("Pencere",90);
                var minimize=ToolbarButton("Küçült",76);
                var close=ToolbarButton("Kapat",72);
                toolbar.Controls.AddRange(new Control[] { status,toggle,minimize,close });
                ((System.ComponentModel.ISupportInitialize)client).BeginInit();
                client.Dock=DockStyle.Fill;
                form.Controls.Add(client); form.Controls.Add(toolbar);
                ((System.ComponentModel.ISupportInitialize)client).EndInit();
                toolbar.BringToFront();
                Action positionToolbar=()=> { toolbar.Left=Math.Max(0,(form.ClientSize.Width-toolbar.Width)/2); toolbar.Top=0; };
                positionToolbar();
                DateTime toolbarUntil=DateTime.UtcNow.AddSeconds(5);
                toggle.Click+=(sender,e)=> { form.SetFullscreen(!form.IsFullscreen); client.Focus(); };
                minimize.Click+=(sender,e)=> { form.WindowState=FormWindowState.Minimized; };
                close.Click+=(sender,e)=> { form.Close(); };
                toolbarTimer.Tick+=(sender,e)=> {
                    var point=form.PointToClient(Cursor.Position);
                    bool atTop=point.Y>=0 && point.Y<=3 && point.X>=0 && point.X<form.ClientSize.Width;
                    bool over=toolbar.Visible && toolbar.Bounds.Contains(point);
                    if((form.ContainsFocus || form.Focused) && (atTop || over)) toolbarUntil=DateTime.UtcNow.AddSeconds(2);
                    toolbar.Visible=!form.IsFullscreen || DateTime.UtcNow<toolbarUntil;
                    if(toolbar.Visible) toolbar.BringToFront();
                };
                form.DisplayModeChanged+=(sender,e)=> {
                    toggle.Text=form.IsFullscreen?"Pencere":"Tam ekran";
                    toolbarUntil=DateTime.UtcNow.AddSeconds(3); positionToolbar();
                };
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
                client.ColorDepth=32;
                // Scale only while the server is applying a new display size.
                // Dynamic resolution below restores a 1:1 image after login/resize.
                client.AdvancedSettings2.SmartSizing=true;
                client.AdvancedSettings9.EnableSuperPan=false;
                client.AdvancedSettings2.DisplayConnectionBar=false;
                form.PerformLayout();
                if(selfTest)
                {
                    if(args.Length>2) ReadSettings(args[2]);
                    var screen=Screen.FromControl(form).Bounds;
                    bool fillsScreen=form.Bounds==screen && client.ClientSize==screen.Size;
                    form.SetFullscreen(false); form.PerformLayout();
                    bool windowed=form.FormBorderStyle==FormBorderStyle.Sizable && client.ClientSize==form.ClientSize;
                    form.SetFullscreen(true); form.PerformLayout();
                    fillsScreen=fillsScreen && form.Bounds==screen && client.ClientSize==screen.Size;
                    if(!fillsScreen || !windowed) throw new Exception("Tam ekran/pencere yerleşim testi başarısız.");
                    if(client.Handle!=clientHandle || !Convert.ToBoolean(extended.get_Property("IgnoreServerGeneratedMouseMoves")) ||
                        !client.AdvancedSettings7.RelativeMouseMode)
                        throw new Exception("Ekran geçişi fare denetimini değiştirdi.");
                    if(args.Length>1)
                    {
                        using(var preview=new Bitmap(toolbar.Width,toolbar.Height))
                        {
                            toolbar.DrawToBitmap(preview,new Rectangle(Point.Empty,toolbar.Size));
                            preview.Save(Path.Combine(Path.GetDirectoryName(Path.GetFullPath(args[1])),"toolbar-preview.png"));
                        }
                    }
                    string report="{\"IgnoreServerGeneratedMouseMoves\":"+ignore.ToString().ToLowerInvariant()+
                        ",\"RelativeMouseMode\":"+relative.ToString().ToLowerInvariant()+
                        ",\"AllowRelativeMouseMode\":"+allowRelative.ToString().ToLowerInvariant()+
                        ",\"Fullscreen\":true,\"ViewportFillsScreen\":true,\"WindowedToggle\":true"+
                        ",\"SmartSizing\":"+client.AdvancedSettings2.SmartSizing.ToString().ToLowerInvariant()+
                        ",\"SuperPan\":"+client.AdvancedSettings9.EnableSuperPan.ToString().ToLowerInvariant()+
                        ",\"ScreenWidth\":"+screen.Width+",\"ScreenHeight\":"+screen.Height+
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
                client.AdvancedSettings7.EnableAutoReconnect=true;
                bool loggedIn=false, displayApplied=false;
                int attempts=0, remoteWidth=0, remoteHeight=0, requestedWidth=0, requestedHeight=0;
                string displayError="";
                Action saveStatus=()=> {
                    try { File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"connection-status.json"),
                        "{\"Connected\":"+(client.Connected!=0).ToString().ToLowerInvariant()+
                        ",\"LoggedIn\":"+loggedIn.ToString().ToLowerInvariant()+
                        ",\"IgnoreServerGeneratedMouseMoves\":"+Convert.ToBoolean(extended.get_Property("IgnoreServerGeneratedMouseMoves")).ToString().ToLowerInvariant()+
                        ",\"RelativeMouseMode\":"+client.AdvancedSettings7.RelativeMouseMode.ToString().ToLowerInvariant()+
                        ",\"Fullscreen\":"+form.IsFullscreen.ToString().ToLowerInvariant()+
                        ",\"ViewportWidth\":"+client.ClientSize.Width+",\"ViewportHeight\":"+client.ClientSize.Height+
                        ",\"RequestedWidth\":"+requestedWidth+",\"RequestedHeight\":"+requestedHeight+
                        ",\"RemoteWidth\":"+remoteWidth+",\"RemoteHeight\":"+remoteHeight+
                        ",\"DisplayUpdateApplied\":"+displayApplied.ToString().ToLowerInvariant()+
                        ",\"DisplayError\":\""+displayError+"\"}",new UTF8Encoding(false)); }
                    catch(IOException) { } catch(UnauthorizedAccessException) { } catch(COMException) { }
                };
                Action scheduleDisplay=()=> {
                    if(!loggedIn || form.WindowState==FormWindowState.Minimized) return;
                    if(displayApplied && requestedWidth==Math.Max(800,client.ClientSize.Width) &&
                        requestedHeight==Math.Max(600,client.ClientSize.Height)) return;
                    attempts=0; displayApplied=false; displayTimer.Stop(); displayTimer.Start();
                };
                client.SizeChanged+=(sender,e)=> { positionToolbar(); scheduleDisplay(); };
                // Resumed sessions may retain their previous resolution. Apply after
                // login, with bounded retries while the server's display channel starts.
                // https://learn.microsoft.com/previous-versions/windows/desktop/legacy/mt703457(v=vs.85)
                displayTimer.Tick+=(sender,e)=> {
                    if(!loggedIn || client.Connected==0 || form.WindowState==FormWindowState.Minimized)
                    { displayTimer.Stop(); return; }
                    requestedWidth=Math.Max(800,client.ClientSize.Width);
                    requestedHeight=Math.Max(600,client.ClientSize.Height);
                    attempts++;
                    try {
                        // Physical size in millimetres at 96 DPI; neutral desktop/device scaling.
                        client.UpdateSessionDisplaySettings((uint)requestedWidth,(uint)requestedHeight,
                            (uint)Math.Round(requestedWidth*25.4/96),(uint)Math.Round(requestedHeight*25.4/96),0,100,100);
                        displayApplied=true; displayError=""; displayTimer.Stop();
                        status.Text="●  OfisPC · Fare sabit · "+requestedWidth+" × "+requestedHeight;
                    }
                    catch(COMException ex) {
                        displayError="0x"+ex.ErrorCode.ToString("X8");
                        if(attempts>=20) { displayTimer.Stop(); status.Text="●  OfisPC · Ekrana sığdırıldı · Fare sabit"; }
                    }
                    saveStatus();
                };
                client.OnRemoteDesktopSizeChange+=(sender,e)=> { remoteWidth=e.width; remoteHeight=e.height; saveStatus(); };
                client.OnConnected+=(sender,e)=> {
                    bool activeIgnore=Convert.ToBoolean(extended.get_Property("IgnoreServerGeneratedMouseMoves"));
                    bool activeRelative=client.AdvancedSettings7.RelativeMouseMode;
                    status.Text=activeIgnore && activeRelative ? "●  OfisPC · Fare sabit · Oturum açılıyor…" : "Fare ayarları doğrulanamadı";
                    saveStatus();
                };
                client.OnLoginComplete+=(sender,e)=> { loggedIn=true; scheduleDisplay(); };
                client.OnDisconnected+=(sender,e)=> {
                    loggedIn=false; displayTimer.Stop();
                    status.Text="Bağlantı kapandı ("+e.discReason+") · Yeniden açabilirsin";
                    toolbarUntil=DateTime.MaxValue; toolbar.Visible=true; saveStatus();
                };
                form.Shown+=(sender,e)=> {
                    // Use the final, DPI-aware viewport rather than the hidden
                    // form's initial size, so pointer and image coordinates agree.
                    client.DesktopWidth=Math.Max(800,client.ClientSize.Width);
                    client.DesktopHeight=Math.Max(600,client.ClientSize.Height);
                    toolbarTimer.Start();
                    client.Connect();
                };
                form.FormClosing+=(sender,e)=> {
                    displayTimer.Stop(); toolbarTimer.Stop();
                    try { if(client.Connected!=0) client.Disconnect(); } catch(COMException) { }
                };
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
