using System.Diagnostics;
using System.Text;
using SlimMD;

namespace SlimMD;

internal static class Program
{
    /// <summary>Time since process start, for SLIMMD_DEBUG diagnostics.</summary>
    internal static readonly Stopwatch Clock = Stopwatch.StartNew();

    [STAThread]
    private static void Main(string[] args)
    {
        // Allows decoding of legacy ANSI (e.g. Big5/GBK) Markdown files.
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);

        ApplicationConfiguration.Initialize();

        // Boot the WebView2 browser process while the window is being built.
        MainForm.PrewarmWebView();

        Application.ThreadException += (_, e) =>
        {
            MsgDialog.Show(null, L.T("msg.error"), e.Exception.Message, MessageBoxIcon.Error, L.T("btn.ok"));
        };

        Application.Run(new MainForm(args));
    }
}
