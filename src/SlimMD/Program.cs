using System.Text;
using SlimMD;

namespace SlimMD;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        // Allows decoding of legacy ANSI (e.g. Big5/GBK) Markdown files.
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);

        ApplicationConfiguration.Initialize();

        Application.ThreadException += (_, e) =>
        {
            MsgDialog.Show(null, L.T("msg.error"), e.Exception.Message, MessageBoxIcon.Error, L.T("btn.ok"));
        };

        Application.Run(new MainForm(args.FirstOrDefault()));
    }
}
