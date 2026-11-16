using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace SlimMD;

internal sealed class MainForm : Form
{
    private const string DocHost = "doc";
    private const string AppHost = "app";

    private readonly AppSettings _settings;
    private readonly IReadOnlyList<string> _startupFiles;
    private readonly EditorBox _editor = new();
    private readonly WebView2 _preview = new();
    private readonly Label _previewFallback = new();
    private readonly SplitContainer _split = new();
    private readonly ToolStrip _toolStrip = new();
    private readonly StatusStrip _statusStrip = new();
    private readonly ToolStripStatusLabel _statusLeft = new();
    private readonly ToolStripStatusLabel _statusRight = new();
    private readonly System.Windows.Forms.Timer _debounce = new() { Interval = 250 };

    private ToolStripButton _btnNew = null!;
    private ToolStripButton _btnOpen = null!;
    private ToolStripButton _btnSave = null!;
    private ToolStripButton _btnSaveAs = null!;
    private ToolStripDropDownButton _btnExport = null!;
    private ToolStripMenuItem _exportPdf = null!;
    private ToolStripMenuItem _exportHtml = null!;
    private ToolStripButton _btnEdit = null!;
    private ToolStripDropDownButton _btnLanguage = null!;
    private ToolStripButton _btnAbout = null!;
    private ToolStripMenuItem _langEn = null!;
    private ToolStripMenuItem _langZh = null!;

    private string? _filePath;
    private Encoding _encoding = new UTF8Encoding(false);
    private string _eol = "\r\n";
    private bool _dirty;
    private bool _loading;
    private bool _normalizing;
    private bool _showEditor;
    private bool _previewReady;
    private bool _renderReset;
    private bool _syncingScroll;
    private DateTime _scrollSyncUntil;

    // One entry per open document; the editor/preview always show _docs[_active].
    private sealed class DocTab
    {
        public TabPage Page = null!;
        public string? FilePath;
        public Encoding Encoding = new UTF8Encoding(false);
        public string Eol = "\r\n";
        public bool Dirty;
        public string Text = "";
        public int Caret;
    }

    private readonly List<DocTab> _docs = new();
    private int _active;
    private bool _switchingTabs;
    private readonly TabControl _tabs = new();
    private readonly ContextMenuStrip _tabMenu = new();
    private ToolStripMenuItem _tabClose = null!;
    private int _tabContextIndex = -1;

    public MainForm(IReadOnlyList<string>? startupFiles = null)
    {
        _startupFiles = startupFiles ?? Array.Empty<string>();
        _settings = AppSettings.Load();
        L.Current = _settings.Language == "zh" ? Lang.Zh : Lang.En;

        Text = "SlimMD";
        Icon = LoadAppIcon();
        StartPosition = FormStartPosition.Manual;
        MinimumSize = new Size(640, 420);
        Size = new Size(Math.Max(640, _settings.Width), Math.Max(420, _settings.Height));
        BackColor = Color.FromArgb(246, 248, 250);
        Font = new Font("Segoe UI", 9.5f);
        KeyPreview = true;
        AllowDrop = true;

        BuildUi();
        RestoreWindowBounds();
        ApplyStrings();
        UpdateTitle();
        UpdateStatus();
        UpdateEditorVisibility(animated: false);

        _debounce.Tick += (_, _) =>
        {
            _debounce.Stop();
            RenderPreview();
        };

        FormClosing += OnFormClosing;
        Load += async (_, _) =>
        {
            await InitPreviewAsync();
            var opened = false;
            foreach (var f in _startupFiles)
            {
                if (File.Exists(f))
                {
                    OpenFile(f, newTab: opened || _docs.Count > 1);
                    opened = true;
                }
            }
        };
    }

    // ---------------------------------------------------------------- UI

    private void BuildUi()
    {
        _toolStrip.Dock = DockStyle.Top;
        _toolStrip.GripStyle = ToolStripGripStyle.Hidden;
        _toolStrip.Padding = new Padding(6, 4, 6, 4);
        _toolStrip.BackColor = Color.FromArgb(246, 248, 250);
        _toolStrip.Font = Font;

        _btnNew = NewButton("btnNew", "act.new", "tip.new");
        _btnOpen = NewButton("btnOpen", "act.open", "tip.open");
        _btnSave = NewButton("btnSave", "act.save", "tip.save");
        _btnSaveAs = NewButton("btnSaveAs", "act.saveAs", "tip.saveAs");
        _btnEdit = NewButton("btnEdit", "act.edit", "tip.edit");
        _btnAbout = NewButton("btnAbout", "act.about", "tip.about");

        _btnLanguage = new ToolStripDropDownButton { DisplayStyle = ToolStripItemDisplayStyle.Text, Name = "btnLanguage" };
        _langEn = new ToolStripMenuItem("English") { Tag = "en", Name = "langEn" };
        _langZh = new ToolStripMenuItem("中文") { Tag = "zh", Name = "langZh" };
        _langEn.Click += (_, _) => SetLanguage(Lang.En);
        _langZh.Click += (_, _) => SetLanguage(Lang.Zh);
        _btnLanguage.DropDownItems.Add(_langEn);
        _btnLanguage.DropDownItems.Add(_langZh);

        _btnExport = new ToolStripDropDownButton { DisplayStyle = ToolStripItemDisplayStyle.Text, Name = "btnExport" };
        _exportPdf = new ToolStripMenuItem { Name = "exportPdf" };
        _exportHtml = new ToolStripMenuItem { Name = "exportHtml" };
        _exportPdf.Click += async (_, _) => await ExportAsync(pdf: true);
        _exportHtml.Click += async (_, _) => await ExportAsync(pdf: false);
        _btnExport.DropDownItems.Add(_exportPdf);
        _btnExport.DropDownItems.Add(_exportHtml);

        _toolStrip.Items.Add(_btnNew);
        _toolStrip.Items.Add(_btnOpen);
        _toolStrip.Items.Add(_btnSave);
        _toolStrip.Items.Add(_btnSaveAs);
        _toolStrip.Items.Add(_btnExport);
        _toolStrip.Items.Add(new ToolStripSeparator());
        _toolStrip.Items.Add(_btnEdit);
        _toolStrip.Items.Add(new ToolStripSeparator());
        _toolStrip.Items.Add(_btnLanguage);
        _toolStrip.Items.Add(new ToolStripSeparator());
        _toolStrip.Items.Add(_btnAbout);

        // Document tabs sit above the preview (browse area); the single editor
        // pane below always shows the active tab's content.
        _tabs.Dock = DockStyle.Top;
        _tabs.Height = Font.Height + 12;
        _tabs.Padding = new Point(8, 4);
        _tabs.MouseUp += OnTabsMouseUp;
        _tabs.SelectedIndexChanged += OnTabSelected;

        _tabClose = new ToolStripMenuItem { Name = "tabClose" };
        _tabClose.Click += (_, _) => CloseTab(_tabContextIndex);
        _tabMenu.Items.Add(_tabClose);

        // Editor pane
        _editor.Multiline = true;
        _editor.AcceptsTab = true;
        _editor.AcceptsReturn = true;
        _editor.ScrollBars = ScrollBars.Both;
        _editor.WordWrap = false;
        _editor.BorderStyle = BorderStyle.FixedSingle;
        _editor.Font = new Font("Consolas", 11.5f);
        _editor.BackColor = Color.White;
        _editor.ForeColor = Color.FromArgb(30, 33, 37);
        _editor.Dock = DockStyle.Fill;
        _editor.MaxLength = int.MaxValue;
        _editor.TextChanged += OnEditorTextChanged;
        _editor.MouseUp += (_, _) =>
        {
            UpdateCursorStatus();
            SyncScrollToPreview();
        };
        _editor.KeyUp += (_, _) =>
        {
            UpdateCursorStatus();
            SyncScrollToPreview();
        };
        _editor.Scrolled += SyncScrollToPreview;

        // The first focus in a freshly loaded document selects all of it (Win32 EDIT
        // behaviour). Collapse that back to a caret - otherwise the first keystroke in
        // the editor would silently replace the whole file. Deferred with BeginInvoke
        // so it runs after focus processing has fully settled.
        _editor.Enter += (_, _) => _editor.BeginInvoke((Action)(() =>
        {
            if (_editor.IsHandleCreated && _editor.TextLength > 0 &&
                _editor.SelectionLength == _editor.TextLength)
            {
                _editor.Select(0, 0);
            }
        }));

        // Preview pane
        _preview.Dock = DockStyle.Fill;
        _preview.BackColor = Color.White;

        _previewFallback.Dock = DockStyle.Fill;
        _previewFallback.TextAlign = ContentAlignment.MiddleCenter;
        _previewFallback.ForeColor = Color.FromArgb(87, 96, 106);
        _previewFallback.Padding = new Padding(32);
        _previewFallback.Visible = false;

        _split.Dock = DockStyle.Fill;
        _split.Size = ClientSize;   // real dimensions before min-size validation runs
        _split.Orientation = Orientation.Vertical;
        _split.SplitterWidth = 6;
        _split.BackColor = Color.FromArgb(220, 224, 228);
        _split.Panel1.BackColor = Color.FromArgb(246, 248, 250);
        _split.Panel2.BackColor = Color.White;
        _split.Panel1.Padding = new Padding(4, 4, 0, 4);
        _split.Panel1MinSize = 220;
        _split.Panel2MinSize = 260;
        _split.Panel1.Controls.Add(_editor);
        _split.Panel2.Controls.Add(_preview);
        _split.Panel2.Controls.Add(_previewFallback);
        _split.Panel2.Controls.Add(_tabs);

        _statusStrip.Dock = DockStyle.Bottom;
        _statusStrip.BackColor = Color.FromArgb(246, 248, 250);
        _statusStrip.Font = Font;
        _statusStrip.SizingGrip = false;
        _statusLeft.Spring = true;
        _statusLeft.TextAlign = ContentAlignment.MiddleLeft;
        _statusLeft.BorderSides = ToolStripStatusLabelBorderSides.None;
        _statusRight.TextAlign = ContentAlignment.MiddleRight;
        _statusRight.BorderSides = ToolStripStatusLabelBorderSides.None;
        _statusStrip.Items.Add(_statusLeft);
        _statusStrip.Items.Add(_statusRight);

        Controls.Add(_split);
        Controls.Add(_toolStrip);
        Controls.Add(_statusStrip);

        _btnNew.Click += (_, _) => NewFile();
        _btnOpen.Click += (_, _) => OpenFile();
        _btnSave.Click += (_, _) => SaveFile();
        _btnSaveAs.Click += (_, _) => SaveFileAs();
        _btnEdit.Click += (_, _) => ToggleEditor();
        _btnAbout.Click += (_, _) => ShowAbout();

        // One untitled document to start with (the tab strip stays hidden
        // until a second document is opened).
        var first = new DocTab();
        first.Page = new TabPage(TabLabel(first));
        _docs.Add(first);
        _tabs.TabPages.Add(first.Page);
        _active = 0;
        _tabs.SelectedIndex = 0;
        UpdateTabHeaders();
    }

    private ToolStripButton NewButton(string name, string textKey, string tipKey)
    {
        return new ToolStripButton
        {
            Name = name,
            Text = L.T(textKey),
            DisplayStyle = ToolStripItemDisplayStyle.Text,
            ToolTipText = L.T(tipKey),
            Padding = new Padding(6, 2, 6, 2),
        };
    }

    private void ApplyStrings()
    {
        _btnNew.Text = L.T("act.new");
        _btnOpen.Text = L.T("act.open");
        _btnSave.Text = L.T("act.save");
        _btnSaveAs.Text = L.T("act.saveAs");
        _btnExport.Text = L.T("act.export");
        _btnAbout.Text = L.T("act.about");
        _btnLanguage.ToolTipText = L.T("tip.language");
        _btnLanguage.Text = L.T("act.language");
        _btnNew.ToolTipText = L.T("tip.new");
        _btnOpen.ToolTipText = L.T("tip.open");
        _btnSave.ToolTipText = L.T("tip.save");
        _btnSaveAs.ToolTipText = L.T("tip.saveAs");
        _btnExport.ToolTipText = L.T("tip.export");
        _btnEdit.ToolTipText = L.T("tip.edit");
        _btnAbout.ToolTipText = L.T("tip.about");
        _exportPdf.Text = L.T("export.pdf");
        _exportHtml.Text = L.T("export.html");
        _langEn.Checked = L.Current == Lang.En;
        _langZh.Checked = L.Current == Lang.Zh;
        _tabClose.Text = L.T("tab.close");
        UpdateEditorVisibility(animated: false);
        UpdateTitle();
        UpdateStatus();
    }

    private void SetLanguage(Lang lang)
    {
        if (L.Current == lang) return;
        L.Current = lang;
        _settings.Language = lang == Lang.Zh ? "zh" : "en";
        _settings.Save();
        ApplyStrings();
    }

    // ---------------------------------------------------------------- window state

    private void RestoreWindowBounds()
    {
        var bounds = new Rectangle(_settings.X, _settings.Y, _settings.Width, _settings.Height);
        var onScreen = Screen.AllScreens.Any(s => s.WorkingArea.IntersectsWith(bounds));
        if (_settings.X >= 0 && _settings.Y >= 0 && onScreen)
        {
            Bounds = bounds;
        }

        if (_settings.Maximized)
        {
            WindowState = FormWindowState.Maximized;
        }
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        // Prompt for unsaved changes in every open tab; Cancel (or a failed
        // save) must keep the window open.
        if (!ConfirmAllDiscarded())
        {
            e.Cancel = true;
            return;
        }

        if (WindowState == FormWindowState.Normal)
        {
            _settings.X = Bounds.X;
            _settings.Y = Bounds.Y;
            _settings.Width = Bounds.Width;
            _settings.Height = Bounds.Height;
        }

        _settings.Maximized = WindowState == FormWindowState.Maximized;
        _settings.Save();
    }

    // ---------------------------------------------------------------- file operations

    private string DisplayName => _filePath == null ? L.T("file.untitled") : Path.GetFileName(_filePath);

    private void NewFile()
    {
        if (IsBlankUntitled())
        {
            _editor.Focus();
            return;
        }

        AddTab(null, "", new UTF8Encoding(false), "\r\n", dirty: false);
        _editor.Focus();
    }

    private void OpenFile(string? path = null, bool newTab = false)
    {
        if (path == null)
        {
            using var dlg = new OpenFileDialog
            {
                Title = L.T("dialog.open"),
                Filter = L.T("filter.markdown") + "|" + L.T("filter.all"),
                CheckFileExists = true,
                Multiselect = true,
            };
            if (!string.IsNullOrEmpty(_settings.LastDirectory) && Directory.Exists(_settings.LastDirectory))
            {
                dlg.InitialDirectory = _settings.LastDirectory;
            }

            if (dlg.ShowDialog(this) != DialogResult.OK) return;
            var files = dlg.FileNames;
            for (var i = 0; i < files.Length; i++)
            {
                OpenFile(files[i], newTab: i > 0 || !IsBlankUntitled());
            }

            return;
        }

        string full;
        try
        {
            full = Path.GetFullPath(path);
        }
        catch (Exception ex)
        {
            MsgDialog.Show(this, L.T("msg.error"), L.T("msg.openFailed", ex.Message), MessageBoxIcon.Error, L.T("btn.ok"));
            return;
        }

        // Already open in a tab? Just switch to it.
        var existing = _docs.FindIndex(d =>
            d.FilePath != null && string.Equals(d.FilePath, full, StringComparison.OrdinalIgnoreCase));
        if (existing >= 0)
        {
            ActivateTab(existing);
            return;
        }

        try
        {
            var (text, encoding) = ReadAllTextAuto(full);
            var eol = text.Contains("\r\n") ? "\r\n" : (text.Contains("\n") ? "\n" : "\r\n");
            var editorText = ToEditorEol(text);
            _settings.LastDirectory = Path.GetDirectoryName(full) ?? "";
            _settings.Save();

            if (!newTab && IsBlankUntitled())
            {
                // Fill the single empty tab instead of stacking a blank one.
                StashActive();
                _active = 0;
                _filePath = full;
                _encoding = encoding;
                _eol = eol;
                _dirty = false;
                _loading = true;
                _editor.Text = editorText;
                _loading = false;
                _editor.SelectionStart = 0;
                _renderReset = true;
                _lastPushedRatio = -1;
                UpdateDocRoot();
                UpdateTitle();
                UpdateStatus();
                UpdateTabHeaders();
                ScheduleRender();
                return;
            }

            AddTab(full, editorText, encoding, eol, dirty: false);
        }
        catch (Exception ex)
        {
            MsgDialog.Show(this, L.T("msg.error"), L.T("msg.openFailed", ex.Message), MessageBoxIcon.Error, L.T("btn.ok"));
        }
    }

    private bool SaveFile()
    {
        if (_filePath == null)
        {
            return SaveFileAs();
        }

        try
        {
            // The editor always holds CRLF; write the file with its original EOL style.
            var content = _editor.Text;
            if (_eol != "\r\n")
            {
                content = content.Replace("\r\n", _eol);
            }

            File.WriteAllText(_filePath, content, _encoding);
            _dirty = false;
            StashActive();
            UpdateTitle();
            UpdateStatus();
            return true;
        }
        catch (Exception ex)
        {
            MsgDialog.Show(this, L.T("msg.error"), L.T("msg.saveFailed", ex.Message), MessageBoxIcon.Error, L.T("btn.ok"));
            return false;
        }
    }

    private bool SaveFileAs()
    {
        using var dlg = new SaveFileDialog
        {
            Title = L.T("dialog.save"),
            Filter = L.T("filter.markdown") + "|" + L.T("filter.all"),
            FileName = _filePath == null ? "" : Path.GetFileName(_filePath),
            DefaultExt = "md",
            AddExtension = true,
            OverwritePrompt = true,
        };
        if (!string.IsNullOrEmpty(_settings.LastDirectory) && Directory.Exists(_settings.LastDirectory))
        {
            dlg.InitialDirectory = _settings.LastDirectory;
        }

        if (dlg.ShowDialog(this) != DialogResult.OK) return false;

        _filePath = Path.GetFullPath(dlg.FileName);
        _settings.LastDirectory = Path.GetDirectoryName(_filePath) ?? "";
        _settings.Save();
        return SaveFile();
    }

    /// <summary>Asks to save pending changes. Returns false when the action must be aborted.</summary>
    private bool ConfirmDiscard()
    {
        if (!_dirty) return true;

        var choice = MsgDialog.Show(
            this,
            "SlimMD",
            L.T("msg.unsaved", DisplayName),
            MessageBoxIcon.Question,
            L.T("btn.yes"),
            L.T("btn.no"),
            L.T("btn.cancel"));

        return choice switch
        {
            0 => SaveFile(),
            1 => true,
            _ => false,
        };
    }

    // ---------------------------------------------------------------- export

    private async Task ExportAsync(bool pdf)
    {
        var baseName = _filePath == null ? "document" : Path.GetFileNameWithoutExtension(_filePath);
        using var dlg = new SaveFileDialog
        {
            Title = L.T(pdf ? "dialog.exportPdf" : "dialog.exportHtml"),
            Filter = L.T(pdf ? "filter.pdf" : "filter.html"),
            FileName = baseName,
            DefaultExt = pdf ? "pdf" : "html",
            AddExtension = true,
            OverwritePrompt = true,
        };
        var dir = !string.IsNullOrEmpty(_settings.LastDirectory) && Directory.Exists(_settings.LastDirectory)
            ? _settings.LastDirectory
            : _docRoot;
        if (Directory.Exists(dir)) dlg.InitialDirectory = dir;

        if (dlg.ShowDialog(this) != DialogResult.OK) return;

        var path = Path.GetFullPath(dlg.FileName);
        try
        {
            Cursor = Cursors.WaitCursor;
            if (pdf) await ExportPdfAsync(path);
            else await ExportHtmlAsync(path);
            _statusLeft.Text = L.T("status.exported", path);
        }
        catch (Exception ex)
        {
            MsgDialog.Show(this, L.T("msg.error"), L.T("msg.exportFailed", ex.Message), MessageBoxIcon.Error, L.T("btn.ok"));
        }
        finally
        {
            Cursor = Cursors.Default;
        }
    }

    private async Task ExportPdfAsync(string path)
    {
        var core = _preview.CoreWebView2 ?? throw new InvalidOperationException(L.T("msg.webviewMissing"));
        await RenderNowAsync();

        // Make sure embedded/local images are decoded before printing.
        try
        {
            await core.ExecuteScriptAsync(
                "Promise.all(Array.prototype.map.call(document.images, function (img) { " +
                "return img.complete ? 0 : new Promise(function (r) { img.onload = img.onerror = r; }); })" +
                ").then(function () { return 'ok'; })");
        }
        catch
        {
            // Best effort - printing still works without this.
        }

        var settings = core.Environment.CreatePrintSettings();
        settings.Orientation = CoreWebView2PrintOrientation.Portrait;
        settings.PageWidth = 8.27;    // A4 portrait, inches
        settings.PageHeight = 11.69;
        settings.MarginTop = 0.6;
        settings.MarginBottom = 0.6;
        settings.MarginLeft = 0.7;
        settings.MarginRight = 0.7;
        settings.ShouldPrintBackgrounds = true;
        settings.ShouldPrintHeaderAndFooter = false;
        settings.ScaleFactor = 1.0;

        var ok = await core.PrintToPdfAsync(path, settings);
        if (!ok) throw new IOException("PrintToPdfAsync failed");
    }

    private async Task ExportHtmlAsync(string path)
    {
        var core = _preview.CoreWebView2 ?? throw new InvalidOperationException(L.T("msg.webviewMissing"));
        await RenderNowAsync();

        var json = await core.ExecuteScriptAsync(
            "(function(){var el=document.getElementById('content');return el?el.outerHTML:'';})()");
        var content = JsonSerializer.Deserialize<string>(json) ?? "";

        var exportDir = Path.GetDirectoryName(path)!;
        content = RewriteDocUrls(content, exportDir);

        var cssPath = Path.Combine(AssetsDirectory, "preview.css");
        var css = File.Exists(cssPath) ? await File.ReadAllTextAsync(cssPath) : "";

        var title = _filePath == null ? "document" : Path.GetFileNameWithoutExtension(_filePath);
        var lang = L.Current == Lang.Zh ? "zh-Hant" : "en";
        var html = new StringBuilder();
        html.Append("<!doctype html>\n");
        html.Append("<html lang=\"").Append(lang).Append("\">\n");
        html.Append("<head>\n");
        html.Append("<meta charset=\"utf-8\">\n");
        html.Append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n");
        html.Append("<title>").Append(System.Net.WebUtility.HtmlEncode(title)).Append("</title>\n");
        html.Append("<style>\n").Append(css).Append("\n</style>\n");
        html.Append("</head>\n<body>\n");
        html.Append(content).Append('\n');
        html.Append("</body>\n</html>\n");

        await File.WriteAllTextAsync(path, html.ToString(), new UTF8Encoding(false));
    }

    /// <summary>Renders the current editor content and awaits completion.</summary>
    private Task RenderNowAsync()
    {
        var core = _preview.CoreWebView2 ?? throw new InvalidOperationException(L.T("msg.webviewMissing"));
        var markdown = JsonSerializer.Serialize(_editor.Text);
        var reset = _renderReset ? "true" : "false";
        _renderReset = false;
        return core.ExecuteScriptAsync($"SLIMMD.apply({markdown},{reset});");
    }

    /// <summary>Rewrites https://doc/ preview URLs in exported HTML to paths relative to the export folder.</summary>
    private string RewriteDocUrls(string html, string exportDir)
    {
        string prefix;
        try
        {
            var fullExport = Path.GetFullPath(exportDir).TrimEnd(Path.DirectorySeparatorChar);
            var fullDoc = Path.GetFullPath(_docRoot).TrimEnd(Path.DirectorySeparatorChar);
            if (string.Equals(fullExport, fullDoc, StringComparison.OrdinalIgnoreCase))
            {
                prefix = "";
            }
            else
            {
                var rel = Path.GetRelativePath(fullExport, fullDoc);
                // Different drive: fall back to an absolute file URI.
                prefix = Path.IsPathRooted(rel)
                    ? new Uri(fullDoc + Path.DirectorySeparatorChar).AbsoluteUri
                    : rel.Replace('\\', '/') + "/";
            }
        }
        catch
        {
            return html;
        }

        return Regex.Replace(html, "((?:href|src)=\")https://doc/", m => m.Groups[1].Value + prefix);
    }

    private static (string Text, Encoding Encoding) ReadAllTextAuto(string path)
    {
        var bytes = File.ReadAllBytes(path);

        if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF)
        {
            return (new UTF8Encoding(true).GetString(bytes, 3, bytes.Length - 3), new UTF8Encoding(true));
        }

        if (bytes.Length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
        {
            return (Encoding.Unicode.GetString(bytes, 2, bytes.Length - 2), Encoding.Unicode);
        }

        if (bytes.Length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF)
        {
            return (Encoding.BigEndianUnicode.GetString(bytes, 2, bytes.Length - 2), Encoding.BigEndianUnicode);
        }

        try
        {
            var utf8 = new UTF8Encoding(false, throwOnInvalidBytes: true);
            return (utf8.GetString(bytes), utf8);
        }
        catch (DecoderFallbackException)
        {
            // Not valid UTF-8 -> fall back to the system ANSI code page (Big5/GBK/1252...).
        }

        var ansi = Encoding.GetEncoding(System.Globalization.CultureInfo.CurrentCulture.TextInfo.ANSICodePage);
        return (ansi.GetString(bytes), ansi);
    }

    // ---------------------------------------------------------------- scroll sync

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    private const int EmGetFirstVisibleLine = 0x00CE;
    private const int EmGetLineCount = 0x00BA;
    private const int EmLineScroll = 0x00B6;

    /// <summary>Multiline TextBox that reports WM_VSCROLL / WM_MOUSEWHEEL / WM_HSCROLL.</summary>
    private sealed class EditorBox : TextBox
    {
        public event Action? Scrolled;

        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            if (m.Msg is 0x0115 or 0x0114 or 0x020A)
            {
                Scrolled?.Invoke();
            }
        }
    }

    /// <summary>Editor scroll position as a 0..1 fraction of the scrollable range.</summary>
    private double EditorScrollRatio()
    {
        if (!_editor.IsHandleCreated) return 0;
        var first = SendMessage(_editor.Handle, EmGetFirstVisibleLine, IntPtr.Zero, IntPtr.Zero).ToInt32();
        var count = SendMessage(_editor.Handle, EmGetLineCount, IntPtr.Zero, IntPtr.Zero).ToInt32();
        var lineHeight = Math.Max(1, _editor.Font.Height);
        var visible = Math.Max(1, _editor.ClientSize.Height / lineHeight);
        var maxFirst = count - visible;
        if (maxFirst <= 0) return 0;
        var ratio = (double)first / maxFirst;
        return ratio < 0 ? 0 : ratio > 1 ? 1 : ratio;
    }

    /// <summary>Moves the editor's viewport to a 0..1 fraction (used to follow the preview).</summary>
    private void ScrollEditorToRatio(double ratio)
    {
        if (!_showEditor || !_editor.IsHandleCreated) return;
        var first = SendMessage(_editor.Handle, EmGetFirstVisibleLine, IntPtr.Zero, IntPtr.Zero).ToInt32();
        var count = SendMessage(_editor.Handle, EmGetLineCount, IntPtr.Zero, IntPtr.Zero).ToInt32();
        var lineHeight = Math.Max(1, _editor.Font.Height);
        var visible = Math.Max(1, _editor.ClientSize.Height / lineHeight);
        var maxFirst = count - visible;
        if (maxFirst <= 0) return;
        var r = ratio < 0 ? 0 : ratio > 1 ? 1 : ratio;
        var delta = (int)Math.Round(r * maxFirst) - first;
        if (delta == 0) return;
        _syncingScroll = true;
        try
        {
            SendMessage(_editor.Handle, EmLineScroll, IntPtr.Zero, (IntPtr)delta);
        }
        finally
        {
            _syncingScroll = false;
        }
    }

    /// <summary>Editor viewport -> preview (the "see my edit immediately" direction).</summary>
    private void SyncScrollToPreview()
    {
        if (_syncingScroll || !_showEditor || _loading || _normalizing) return;
        var core = _preview.CoreWebView2;
        if (core == null || !_previewReady) return;

        var ratio = EditorScrollRatio();
        if (Math.Abs(ratio - _lastPushedRatio) < 0.002) return;
        _lastPushedRatio = ratio;
        _scrollSyncUntil = DateTime.UtcNow.AddMilliseconds(350);
        _ = core.ExecuteScriptAsync(
            $"SLIMMD.scrollToRatio({ratio.ToString("0.####", CultureInfo.InvariantCulture)});");
    }

    private double _lastPushedRatio = -1;

    // ---------------------------------------------------------------- tabs

    private void OnTabSelected(object? sender, EventArgs e)
    {
        if (_switchingTabs) return;
        if (_tabs.SelectedIndex >= 0 && _tabs.SelectedIndex != _active)
        {
            ActivateTab(_tabs.SelectedIndex);
        }
    }

    private void OnTabsMouseUp(object? sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Right) return;
        var idx = -1;
        for (var i = 0; i < _tabs.TabPages.Count; i++)
        {
            if (_tabs.GetTabRect(i).Contains(e.Location)) { idx = i; break; }
        }
        if (idx < 0 || idx >= _docs.Count) return;
        _tabContextIndex = idx;
        _tabMenu.Show(_tabs, e.Location);
    }

    /// <summary>Copies the live editor state into the active DocTab.</summary>
    private void StashActive()
    {
        if (_active < 0 || _active >= _docs.Count) return;
        var d = _docs[_active];
        d.FilePath = _filePath;
        d.Encoding = _encoding;
        d.Eol = _eol;
        d.Dirty = _dirty;
        d.Text = _editor.Text;
        d.Caret = _editor.SelectionStart;
    }

    /// <summary>Restores a DocTab into the live editor state.</summary>
    private void LoadTab(int index)
    {
        var d = _docs[index];
        _filePath = d.FilePath;
        _encoding = d.Encoding;
        _eol = d.Eol;
        _dirty = d.Dirty;
        _loading = true;
        _editor.Text = d.Text;
        _loading = false;
        var caret = Math.Min(Math.Max(0, d.Caret), _editor.TextLength);
        _editor.SelectionStart = caret;
        _editor.SelectionLength = 0;
        _renderReset = false;
        _lastPushedRatio = -1;
        _scrollSyncUntil = DateTime.MinValue;
        UpdateDocRoot();
        UpdateTitle();
        UpdateStatus();
        UpdateTabHeaders();
        try { _editor.ScrollToCaret(); }
        catch (InvalidOperationException) { /* no handle yet */ }
        ScheduleRender();
    }

    private void ActivateTab(int index)
    {
        if (index < 0 || index >= _docs.Count || index == _active) return;
        StashActive();
        _active = index;
        _switchingTabs = true;
        _tabs.SelectedIndex = index;
        _switchingTabs = false;
        LoadTab(index);
        if (_showEditor) _editor.Focus();
    }

    /// <summary>Adds a document tab and makes it active. Pass text/path for a file.</summary>
    private int AddTab(string? path, string text, Encoding encoding, string eol, bool dirty)
    {
        StashActive();
        var doc = new DocTab
        {
            FilePath = path,
            Encoding = encoding,
            Eol = eol,
            Dirty = dirty,
            Text = text,
        };
        _docs.Add(doc);
        doc.Page = new TabPage(TabLabel(doc));
        _tabs.TabPages.Add(doc.Page);
        _active = _docs.Count - 1;
        _switchingTabs = true;
        _tabs.SelectedIndex = _active;
        _switchingTabs = false;
        LoadTab(_active);
        UpdateTabHeaders();
        return _active;
    }

    /// <summary>Reuses the single blank untitled tab instead of stacking empty ones.</summary>
    private bool IsBlankUntitled() =>
        _docs.Count == 1 && _filePath == null && !_dirty && _editor.TextLength == 0;

    private static string TabLabel(DocTab d)
    {
        var name = d.FilePath == null ? L.T("file.untitled") : Path.GetFileName(d.FilePath);
        return d.Dirty ? name + "*" : name;
    }

    private void UpdateTabHeaders()
    {
        _tabs.Visible = _docs.Count > 1;
        for (var i = 0; i < _docs.Count && i < _tabs.TabPages.Count; i++)
        {
            // The active doc lives in the editor fields, not yet in _docs[i].
            var probe = i == _active
                ? new DocTab { FilePath = _filePath, Dirty = _dirty }
                : _docs[i];
            var label = TabLabel(probe);
            if (_tabs.TabPages[i].Text != label) _tabs.TabPages[i].Text = label;
        }
    }

    private void CloseTab(int index)
    {
        if (index < 0 || index >= _docs.Count) return;
        ActivateTab(index);

        if (_docs.Count == 1)
        {
            // Last tab: clear it (New behaviour) instead of leaving no document.
            if (!ConfirmDiscard()) return;
            _filePath = null;
            _encoding = new UTF8Encoding(false);
            _eol = "\r\n";
            _dirty = false;
            _loading = true;
            _editor.Clear();
            _loading = false;
            _editor.SelectionStart = 0;
            _renderReset = true;
            _lastPushedRatio = -1;
            StashActive();
            UpdateDocRoot();
            UpdateTitle();
            UpdateStatus();
            ScheduleRender();
            return;
        }

        if (!ConfirmDiscard()) return;

        _tabs.TabPages.RemoveAt(index);
        _docs.RemoveAt(index);
        if (_active >= _docs.Count) _active = _docs.Count - 1;
        _switchingTabs = true;
        _tabs.SelectedIndex = _active;
        _switchingTabs = false;
        LoadTab(_active);
        UpdateTabHeaders();
    }

    /// <summary>Prompts for every unsaved tab. False => abort the action.</summary>
    private bool ConfirmAllDiscarded()
    {
        var restore = _active;
        for (var i = 0; i < _docs.Count; i++)
        {
            if (i != _active) ActivateTab(i);
            if (!ConfirmDiscard())
            {
                // Aborted: put the user back where they were.
                if (restore != _active) ActivateTab(restore);
                return false;
            }
        }

        return true;
    }

    // ---------------------------------------------------------------- editor / view

    private void OnEditorTextChanged(object? sender, EventArgs e)
    {
        if (_loading) return;

        // Win32 EDIT controls silently drop bare LF; normalize any LF-only paste to CRLF.
        if (!_normalizing)
        {
            var t = _editor.Text;
            if (t.IndexOf('\n') >= 0 && (t.IndexOf("\r\n") < 0 || t.Replace("\r\n", "").IndexOf('\n') >= 0))
            {
                var caret = _editor.SelectionStart;
                var before = t.Substring(0, Math.Min(caret, t.Length));
                // Each bare LF before the caret gains one '\r'.
                var shift = (before.Split('\n').Length - 1) - before.Split("\r\n").Length + 1;
                _normalizing = true;
                try
                {
                    _editor.Text = t.Replace("\r\n", "\n").Replace("\n", "\r\n");
                    _editor.SelectionStart = Math.Min(caret + Math.Max(0, shift), _editor.TextLength);
                }
                finally
                {
                    _normalizing = false;
                }
            }
        }

        _dirty = true;
        UpdateTitle();
        UpdateStatus();
        ScheduleRender();
    }

    // The editor always holds CRLF; this is a no-op for text that already does.
    private static string ToEditorEol(string t) => t.Replace("\r\n", "\n").Replace("\n", "\r\n");

    private void ScheduleRender()
    {
        _debounce.Stop();
        _debounce.Start();
    }

    private void ToggleEditor() => SetEditorVisible(!_showEditor);

    private bool _splitPlaced;

    /// <summary>Places the splitter at 45% once the layout pass has real dimensions.</summary>
    private void PlaceSplitter()
    {
        if (_splitPlaced) return;
        var width = _split.Width;
        if (width <= _split.Panel1MinSize + _split.Panel2MinSize) return;
        var distance = (int)(width * 0.45);
        distance = Math.Max(_split.Panel1MinSize, Math.Min(distance, width - _split.Panel2MinSize));
        _split.SplitterDistance = distance;
        _splitPlaced = true;
    }

    private void SetEditorVisible(bool visible)
    {
        if (_showEditor == visible) return;
        _showEditor = visible;
        if (visible) PlaceSplitter();
        UpdateEditorVisibility(animated: true);
        if (visible)
        {
            _editor.Focus();
            // The preview may have been scrolled while hidden behind browse mode:
            // pull its position into the editor instead of snapping it to the top.
            SyncEditorFromPreview();
        }
    }

    /// <summary>Preview viewport -> editor (used when the editor pane reappears).</summary>
    private async void SyncEditorFromPreview()
    {
        try
        {
            var core = _preview.CoreWebView2;
            if (core == null || !_previewReady || !_showEditor) return;
            var json = await core.ExecuteScriptAsync("SLIMMD.scrollRatio()");
            if (double.TryParse(json, NumberStyles.Float, CultureInfo.InvariantCulture, out var ratio))
            {
                _scrollSyncUntil = DateTime.UtcNow.AddMilliseconds(350);
                ScrollEditorToRatio(ratio);
            }
        }
        catch (Exception ex)
        {
            AppSettings.DebugLog("scroll sync failed: " + ex.Message);
        }
    }

    private void UpdateEditorVisibility(bool animated)
    {
        _ = animated;
        _split.Panel1Collapsed = !_showEditor;
        _btnEdit.Text = _showEditor ? L.T("act.hideEditor") : L.T("act.edit");
        UpdateStatus();
    }

    private void UpdateTitle()
    {
        var name = DisplayName + (_dirty ? "*" : "");
        Text = $"{name} - {L.T("app.name")}";
        UpdateTabHeaders();
    }

    private void UpdateStatus()
    {
        if (!_showEditor)
        {
            _statusLeft.Text = _filePath == null
                ? L.T("status.browse")
                : L.T("status.doc", _filePath, _encoding.WebName, _editor.TextLength);
        }
        else
        {
            _statusLeft.Text = _filePath == null
                ? L.T("status.edit") + " - " + L.T("file.untitled")
                : L.T("status.doc", _filePath, _encoding.WebName, _editor.TextLength);
        }

        UpdateCursorStatus();
    }

    private void UpdateCursorStatus()
    {
        if (_loading) return;
        var text = _editor.Text;
        var pos = Math.Min(_editor.SelectionStart, text.Length);
        var line = 1;
        var col = 1;
        for (var i = 0; i < pos; i++)
        {
            if (text[i] == '\n')
            {
                line++;
                col = 1;
            }
            else
            {
                col++;
            }
        }

        _statusRight.Text = L.T("status.cursor", line, col);
    }

    // ---------------------------------------------------------------- preview

    private string AssetsDirectory => Path.Combine(AppContext.BaseDirectory, "assets");
    private string _docRoot = AppContext.BaseDirectory;
    private static readonly bool DebugOn = Environment.GetEnvironmentVariable("SLIMMD_DEBUG") == "1";

    private void UpdateDocRoot()
    {
        var core = _preview.CoreWebView2;

        _docRoot = _filePath == null
            ? AppContext.BaseDirectory
            : Path.GetDirectoryName(_filePath) ?? AppContext.BaseDirectory;

        if (core == null) return;
        core.SetVirtualHostNameToFolderMapping(DocHost, _docRoot, CoreWebView2HostResourceAccessKind.Allow);
    }

    private async Task InitPreviewAsync()
    {
        try
        {
            var userData = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "SlimMD", "WebView2");
            var env = await CoreWebView2Environment.CreateAsync(null, userData);
            await _preview.EnsureCoreWebView2Async(env);
        }
        catch (Exception)
        {
            _preview.Visible = false;
            _previewFallback.Visible = true;
            _previewFallback.Text = L.T("msg.webviewMissing");
            return;
        }

        var w = _preview.CoreWebView2!;
        w.Settings.IsWebMessageEnabled = true;
        w.Settings.AreDefaultContextMenusEnabled = false;
        w.Settings.AreDevToolsEnabled = false;
        w.Settings.IsStatusBarEnabled = false;
        w.Settings.IsZoomControlEnabled = false;
        w.Settings.IsSwipeNavigationEnabled = false;
        w.Settings.AreBrowserAcceleratorKeysEnabled = false;

        // Keyboard shortcuts while the preview has focus (the default in browse view)
        // are forwarded by the page script: with AreBrowserAcceleratorKeysEnabled=false
        // Chromium passes the keys to the document, and preview.js re-posts them as
        // {type:"shortcut"} messages handled in WebMessageReceived below.
        // (CoreWebView2Controller.AcceleratorKeyPressed is not publicly reachable.)

        w.SetVirtualHostNameToFolderMapping(AppHost, AssetsDirectory, CoreWebView2HostResourceAccessKind.Allow);
        UpdateDocRoot();

        // Keep the preview page in place: links open in the system browser / associated app.
        w.NavigationStarting += (_, e) =>
        {
            if (e.Uri.StartsWith($"https://{AppHost}/", StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            e.Cancel = true;
            OpenExternal(e.Uri);
        };
        w.NewWindowRequested += (_, e) =>
        {
            e.Handled = true;
            OpenExternal(e.Uri);
        };

        w.NavigationCompleted += async (_, e) =>
        {
            _previewReady = true;
            AppSettings.DebugLog($"NavigationCompleted success={e.IsSuccess} status={e.WebErrorStatus}");
            if (DebugOn)
            {
                try
                {
                    await w.ExecuteScriptAsync(
                        "window.__msgs=[];window.addEventListener('message',function(e){window.__msgs.push(JSON.stringify(e.data).slice(0,120))});'ok'");
                }
                catch (Exception ex)
                {
                    AppSettings.DebugLog("recorder failed: " + ex.Message);
                }
            }

            RenderPreview();

            if (DebugOn)
            {
                try
                {
                    await Task.Delay(700);
                    var probe = await w.ExecuteScriptAsync(
                        "JSON.stringify({t: typeof window.SLIMMD, sheets: document.styleSheets.length, len: (document.getElementById('content')||{innerHTML:''}).innerHTML.length, msgs: window.__msgs})");
                    AppSettings.DebugLog("probe: " + probe);
                }
                catch (Exception ex)
                {
                    AppSettings.DebugLog("probe failed: " + ex.Message);
                }
            }
        };
        w.WebMessageReceived += (_, e) =>
        {
            AppSettings.DebugLog("page message: " + e.WebMessageAsJson);
            try
            {
                using var doc = JsonDocument.Parse(e.WebMessageAsJson);
                if (!doc.RootElement.TryGetProperty("type", out var type)) return;

                var typeName = type.GetString();
                if (typeName == "ready")
                {
                    RenderPreview();
                }
                else if (typeName == "scroll" && _showEditor && !_loading &&
                         doc.RootElement.TryGetProperty("ratio", out var ratioEl) &&
                         DateTime.UtcNow >= _scrollSyncUntil)
                {
                    // Preview viewport -> editor. Guarded by _scrollSyncUntil so the
                    // echo of our own scrollToRatio() does not fight the user.
                    if (double.TryParse(ratioEl.GetRawText(), NumberStyles.Float,
                            CultureInfo.InvariantCulture, out var ratio))
                    {
                        _scrollSyncUntil = DateTime.UtcNow.AddMilliseconds(350);
                        BeginInvoke(() => ScrollEditorToRatio(ratio));
                    }
                }
                else if (typeName == "shortcut" && !_editor.Focused && IsHandleCreated &&
                         doc.RootElement.TryGetProperty("action", out var actionEl))
                {
                    // Preview has focus: the WinForms OnKeyDown never sees these keys,
                    // so the page forwards them. Defer so file dialogs / renders are
                    // never shown from inside the synchronous message handler.
                    var action = actionEl.GetString();
                    BeginInvoke(() =>
                    {
                        switch (action)
                        {
                            case "new": NewFile(); break;
                            case "open": OpenFile(); break;
                            case "save": SaveFile(); break;
                            case "saveas": SaveFileAs(); break;
                            case "toggle": ToggleEditor(); break;
                        }
                    });
                }
            }
            catch
            {
                // Ignore malformed page messages.
            }
        };

        w.Navigate($"https://{AppHost}/preview.html");
    }

    private void RenderPreview()
    {
        var core = _preview.CoreWebView2;
        AppSettings.DebugLog($"RenderPreview ready={_previewReady} len={_editor.Text.Length}");
        if (core == null || !_previewReady) return;

        // The native host->page message channel is unreliable on some WebView2 runtimes,
        // so content is delivered through the script channel instead.
        var markdown = JsonSerializer.Serialize(_editor.Text);
        var reset = _renderReset ? "true" : "false";
        var wasReset = _renderReset;
        _renderReset = false;
        _ = core.ExecuteScriptAsync($"SLIMMD.apply({markdown},{reset});").ContinueWith(_ =>
        {
            // Content height may have changed: re-anchor the preview to the editor
            // viewport so the line being edited stays visible.
            if (!wasReset && IsHandleCreated)
            {
                _lastPushedRatio = -1;
                try { BeginInvoke((Action)SyncScrollToPreview); }
                catch (InvalidOperationException) { /* handle gone */ }
            }
        });
    }

    /// <summary>Opens http(s)/mailto links in the default browser and doc links in their app.</summary>
    private void OpenExternal(string uri)
    {
        try
        {
            if (uri.StartsWith($"https://{DocHost}/", StringComparison.OrdinalIgnoreCase))
            {
                var relative = Uri.UnescapeDataString(uri[($"https://{DocHost}/".Length)..]);
                var combined = Path.GetFullPath(Path.Combine(_docRoot, relative));
                if (File.Exists(combined) || Directory.Exists(combined))
                {
                    uri = combined;
                }
                else
                {
                    return;
                }
            }

            Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true });
        }
        catch
        {
            // Unknown scheme or missing target - ignore.
        }
    }

    // ---------------------------------------------------------------- shell events

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.Control && !e.Shift && e.KeyCode == Keys.N)
        {
            NewFile();
            e.Handled = true;
            return;
        }

        if (e.Control && !e.Shift && e.KeyCode == Keys.O)
        {
            OpenFile();
            e.Handled = true;
            return;
        }

        if (e.Control && e.KeyCode == Keys.S)
        {
            if (e.Shift) SaveFileAs();
            else SaveFile();
            e.Handled = true;
            return;
        }

        if (e.Control && e.KeyCode == Keys.E)
        {
            ToggleEditor();
            e.Handled = true;
            return;
        }

        if (e.KeyCode == Keys.F9)
        {
            ToggleEditor();
            e.Handled = true;
            return;
        }

        base.OnKeyDown(e);
    }

    protected override void OnDragEnter(DragEventArgs e)
    {
        e.Effect = e.Data != null && e.Data.GetDataPresent(DataFormats.FileDrop)
            ? DragDropEffects.Copy
            : DragDropEffects.None;
        base.OnDragEnter(e);
    }

    protected override void OnDragDrop(DragEventArgs e)
    {
        if (e.Data?.GetData(DataFormats.FileDrop) is string[] { Length: > 0 } files)
        {
            for (var i = 0; i < files.Length; i++)
            {
                OpenFile(files[i], newTab: i > 0 || !IsBlankUntitled());
            }
        }

        base.OnDragDrop(e);
    }

    private void ShowAbout()
    {
        using var dlg = new AboutDialog();
        dlg.ShowDialog(this);
    }

    private static Icon LoadAppIcon()
    {
        try
        {
            using var stream = typeof(MainForm).Assembly.GetManifestResourceStream("SlimMD.SlimMD.ico");
            if (stream != null)
            {
                return new Icon(stream);
            }
        }
        catch
        {
            // fall through
        }

        return SystemIcons.Application;
    }
}
