using System.Diagnostics;

namespace SlimMD;

/// <summary>
/// The About dialog: logo, version, feature list, project links and copyright.
/// Localised through <see cref="L"/> when it is created (it is shown modally, so the
/// interface language cannot change while it is open).
/// </summary>
internal sealed class AboutDialog : Form
{
    private const int TextWidth = 400;

    public AboutDialog()
    {
        Text = L.T("about.title");
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.CenterParent;
        Font = new Font("Segoe UI", 9.5f);
        AutoScaleMode = AutoScaleMode.Dpi;
        Padding = new Padding(20, 16, 20, 14);
        KeyPreview = true;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;

        var layout = new TableLayoutPanel
        {
            ColumnCount = 2,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Margin = new Padding(0),
            // Deliberately NOT docked: a Dock=Top child only contributes its height to the
            // form's AutoSize, so the dialog collapsed to a few dozen pixels wide and the
            // text wrapped character by character. Location is pinned to Padding instead.
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));           // logo
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, TextWidth)); // text
        for (var i = 0; i < 9; i++)
        {
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        }

        // --- header: logo + product name + version -------------------------
        var logoBox = new PictureBox
        {
            Size = new Size(64, 64),
            SizeMode = PictureBoxSizeMode.StretchImage,
            Margin = new Padding(0, 0, 14, 0),
        };
        var logo = LoadLogo();
        if (logo != null) logoBox.Image = logo;
        else logoBox.Visible = false;

        var title = new Label
        {
            Text = "SlimMD",
            Font = new Font(Font.FontFamily, 16f, FontStyle.Bold),
            AutoSize = true,
            Margin = new Padding(0, 0, 0, 1),
        };
        var version = new Label
        {
            Text = L.T("about.version", AppVersion()),
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
            Margin = new Padding(0, 0, 0, 0),
        };

        layout.Controls.Add(logoBox, 0, 0);
        layout.SetRowSpan(logoBox, 2);
        layout.Controls.Add(title, 1, 0);
        layout.Controls.Add(version, 1, 1);

        // --- body ----------------------------------------------------------
        AddBody(layout, 2, L.T("about.tagline"));
        AddBody(layout, 3, L.T("about.featuresHeader"), bold: true);
        AddBody(layout, 4, Bullets(
            L.T("about.feature.open"),
            L.T("about.feature.browse"),
            L.T("about.feature.export"),
            L.T("about.feature.lang"),
            L.T("about.feature.theme")));
        AddBody(layout, 5, L.T("about.builtWith"));

        // --- links ---------------------------------------------------------
        var links = new FlowLayoutPanel
        {
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            Margin = new Padding(0, 8, 0, 0),
        };
        links.Controls.Add(MakeLink(L.T("about.repo"), AppInfo.RepoUrl));
        links.Controls.Add(new Label
        {
            Text = "·",
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
            Margin = new Padding(8, 3, 8, 0),
        });
        links.Controls.Add(MakeLink(L.T("about.license", AppInfo.LicenseName), AppInfo.LicenseUrl));
        layout.Controls.Add(links, 0, 6);
        layout.SetColumnSpan(links, 2);

        // --- copyright -----------------------------------------------------
        var copyright = new Label
        {
            Text = AppInfo.Copyright,
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
            Margin = new Padding(0, 10, 0, 0),
        };
        layout.Controls.Add(copyright, 0, 7);
        layout.SetColumnSpan(copyright, 2);

        // --- OK ------------------------------------------------------------
        var buttonPanel = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
            Dock = DockStyle.Fill,
            Margin = new Padding(0, 14, 0, 0),
        };
        var ok = new Button
        {
            Text = L.T("btn.ok"),
            AutoSize = true,
            MinimumSize = new Size(88, 26),
            Margin = new Padding(0),
        };
        ok.Click += (_, _) => Close();
        buttonPanel.Controls.Add(ok);
        layout.Controls.Add(buttonPanel, 0, 8);
        layout.SetColumnSpan(buttonPanel, 2);

        Controls.Add(layout);
        layout.Location = new Point(Padding.Left, Padding.Top);

        AcceptButton = ok;
        CancelButton = ok;   // Esc closes as well
        ActiveControl = ok;  // Enter closes immediately (not the first focusable link)
    }

    /// <summary>Version from the assembly (csproj &lt;Version&gt;), without any build metadata.</summary>
    public static string AppVersion()
    {
        var raw = (Application.ProductVersion ?? "").Split('+')[0].Trim();
        var parts = raw.Split('.');
        if (parts.Length >= 3) return $"{parts[0]}.{parts[1]}.{parts[2]}";
        return string.IsNullOrEmpty(raw) ? "1.0.1" : raw;
    }

    private static void AddBody(TableLayoutPanel layout, int row, string text, bool bold = false)
    {
        var label = new Label
        {
            Text = text,
            AutoSize = true,
            MaximumSize = new Size(TextWidth, 0),
            Margin = new Padding(0, row == 2 ? 12 : 8, 0, 0),
        };
        if (bold) label.Font = new Font(label.Font, FontStyle.Bold);
        layout.Controls.Add(label, 0, row);
        layout.SetColumnSpan(label, 2);
    }

    private static string Bullets(params string[] items) =>
        string.Join("\n", items.Select(i => "• " + i));

    private static LinkLabel MakeLink(string text, string url)
    {
        var link = new LinkLabel
        {
            Text = text,
            AutoSize = true,
            Margin = new Padding(0, 3, 0, 0),
        };
        link.Links.Add(0, text.Length, url);
        link.LinkClicked += (_, e) => OpenUrl(e.Link?.LinkData as string);
        return link;
    }

    private static void OpenUrl(string? url)
    {
        if (string.IsNullOrEmpty(url)) return;
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch
        {
            // No browser available - nothing sensible to do.
        }
    }

    private static Image? LoadLogo()
    {
        try
        {
            using var stream = typeof(MainForm).Assembly.GetManifestResourceStream("SlimMD.SlimMD.ico");
            if (stream == null) return null;
            using var icon = new Icon(stream, 64, 64);
            return icon.ToBitmap();
        }
        catch
        {
            return null;
        }
    }
}
