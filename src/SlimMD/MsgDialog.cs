namespace SlimMD;

/// <summary>
/// Small fully localised message dialog (WinForms MessageBox button captions follow the
/// OS language, which would break the language switch of the application).
/// </summary>
internal sealed class MsgDialog : Form
{
    private MsgDialog(string title, string message, MessageBoxIcon icon, string[] buttons, int cancelIndex)
    {
        Text = title;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.CenterParent;
        Font = new Font("Segoe UI", 9.5f);
        AutoScaleMode = AutoScaleMode.Dpi;
        Padding = new Padding(16, 14, 16, 14);
        KeyPreview = true;

        var layout = new TableLayoutPanel
        {
            ColumnCount = 2,
            RowCount = 2,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
        };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 400));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var iconBox = new PictureBox
        {
            Size = new Size(32, 32),
            SizeMode = PictureBoxSizeMode.CenterImage,
            Margin = new Padding(0, 2, 12, 0),
        };
        iconBox.Image = (icon switch
        {
            MessageBoxIcon.Error => SystemIcons.Error,
            MessageBoxIcon.Warning => SystemIcons.Warning,
            MessageBoxIcon.Question => SystemIcons.Question,
            _ => SystemIcons.Information,
        }).ToBitmap();

        var label = new Label
        {
            Text = message,
            AutoSize = true,
            MaximumSize = new Size(400, 0),
            Margin = new Padding(0, 2, 0, 8),
        };

        layout.Controls.Add(iconBox, 0, 0);
        layout.Controls.Add(label, 1, 0);

        var buttonPanel = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
            Margin = new Padding(0, 12, 0, 0),
        };

        Button? accept = null;
        Button? cancel = null;
        for (var i = buttons.Length - 1; i >= 0; i--)
        {
            var index = i;
            var b = new Button
            {
                Text = buttons[i],
                AutoSize = true,
                MinimumSize = new Size(88, 26),
                Margin = new Padding(8, 0, 0, 0),
            };
            b.Click += (_, _) =>
            {
                Tag = index;
                Close();
            };
            buttonPanel.Controls.Add(b);
            if (i == 0) accept = b;
            if (i == cancelIndex) cancel = b;
        }

        layout.Controls.Add(buttonPanel, 0, 1);
        layout.SetColumnSpan(buttonPanel, 2);

        // No docking: docked children inside a non-autosizing form overflowed
        // and painted over each other. Size the form to the layout explicitly.
        Controls.Add(layout);
        layout.Location = new Point(Padding.Left, Padding.Top);
        layout.PerformLayout();
        ClientSize = new Size(
            layout.Width + Padding.Horizontal,
            layout.Height + Padding.Vertical);

        if (accept != null) AcceptButton = accept;
        if (cancel != null) CancelButton = cancel;

        CancelIndex = cancelIndex;

        // Close button (X) behaves like the cancel button.
        FormClosed += (_, _) =>
        {
            if (Tag == null) Tag = CancelIndex;
        };
    }

    private int CancelIndex { get; }

    /// <summary>Shows the dialog and returns the index of the pressed button.</summary>
    public static int Show(IWin32Window? owner, string title, string message, MessageBoxIcon icon, params string[] buttons)
    {
        if (buttons.Length == 0)
        {
            buttons = new[] { L.T("btn.ok") };
        }

        using var dlg = new MsgDialog(title, message, icon, buttons, buttons.Length - 1);
        dlg.ShowDialog(owner);
        return dlg.Tag is int i ? i : buttons.Length - 1;
    }
}
