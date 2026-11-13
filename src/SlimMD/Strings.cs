namespace SlimMD;

internal enum Lang
{
    En,
    Zh,
}

/// <summary>UI strings. English is the default; Chinese (Traditional) is the alternate.</summary>
internal static class L
{
    public static Lang Current { get; set; } = Lang.En;

    private static readonly Dictionary<string, (string En, string Zh)> Map = new()
    {
        // Shell
        ["app.name"] = ("SlimMD", "SlimMD"),
        ["btn.ok"] = ("OK", "確定"),
        ["btn.yes"] = ("Yes", "是"),
        ["btn.no"] = ("No", "否"),
        ["btn.cancel"] = ("Cancel", "取消"),

        // Toolbar / menu
        ["act.new"] = ("New", "新增"),
        ["act.open"] = ("Open", "開啟"),
        ["act.save"] = ("Save", "儲存"),
        ["act.saveAs"] = ("Save As...", "另存新檔..."),
        ["act.edit"] = ("Edit", "編輯"),
        ["act.hideEditor"] = ("Hide Editor", "隱藏編輯區"),
        ["act.showEditor"] = ("Show Editor", "顯示編輯區"),
        ["act.export"] = ("Export", "匯出"),
        ["act.language"] = ("Language", "語言"),
        ["act.about"] = ("About", "關於"),

        // Export menu
        ["export.pdf"] = ("Export as PDF...", "匯出為 PDF..."),
        ["export.html"] = ("Export as HTML...", "匯出為 HTML..."),

        // Tooltips
        ["tip.new"] = ("New file (Ctrl+N)", "新增檔案 (Ctrl+N)"),
        ["tip.open"] = ("Open file (Ctrl+O)", "開啟檔案 (Ctrl+O)"),
        ["tip.save"] = ("Save (Ctrl+S)", "儲存 (Ctrl+S)"),
        ["tip.saveAs"] = ("Save As (Ctrl+Shift+S)", "另存新檔 (Ctrl+Shift+S)"),
        ["tip.edit"] = ("Show/hide the editor pane (Ctrl+E)", "顯示/隱藏編輯區 (Ctrl+E)"),
        ["tip.export"] = ("Export the document as PDF or HTML", "將文件匯出為 PDF 或 HTML"),
        ["tip.language"] = ("Change interface language", "切換介面語言"),
        ["tip.about"] = ("About SlimMD", "關於 SlimMD"),

        // Status bar
        ["status.browse"] = ("Browse mode - click Edit to split the view", "瀏覽模式 - 按一下「編輯」可分割畫面"),
        ["status.edit"] = ("Edit mode", "編輯模式"),
        ["status.cursor"] = ("Ln {0}, Col {1}", "第 {0} 行，第 {1} 列"),
        ["status.doc"] = ("{0}  |  {1}  |  {2} chars", "{0}  |  {1}  |  {2} 個字元"),
        ["status.exported"] = ("Exported: {0}", "已匯出：{0}"),

        // Files
        ["file.untitled"] = ("Untitled", "未命名"),
        ["filter.markdown"] = ("Markdown files (*.md;*.markdown;*.mdown;*.mkd;*.txt)|*.md;*.markdown;*.mdown;*.mkd;*.txt", "Markdown 檔案 (*.md;*.markdown;*.mdown;*.mkd;*.txt)|*.md;*.markdown;*.mdown;*.mkd;*.txt"),
        ["filter.all"] = ("All files (*.*)|*.*", "所有檔案 (*.*)|*.*"),
        ["dialog.open"] = ("Open Markdown file", "開啟 Markdown 檔案"),
        ["dialog.save"] = ("Save Markdown file", "儲存 Markdown 檔案"),
        ["dialog.exportPdf"] = ("Export PDF", "匯出 PDF"),
        ["dialog.exportHtml"] = ("Export HTML", "匯出 HTML"),
        ["filter.pdf"] = ("PDF file (*.pdf)|*.pdf", "PDF 檔案 (*.pdf)|*.pdf"),
        ["filter.html"] = ("HTML file (*.html;*.htm)|*.html;*.htm", "HTML 檔案 (*.html;*.htm)|*.html;*.htm"),

        // Messages
        ["msg.unsaved"] = ("Do you want to save the changes to {0}?", "是否要儲存 {0} 的變更？"),
        ["msg.openFailed"] = ("Could not open the file.\n\n{0}", "無法開啟檔案。\n\n{0}"),
        ["msg.saveFailed"] = ("Could not save the file.\n\n{0}", "無法儲存檔案。\n\n{0}"),
        ["msg.exportFailed"] = ("Could not export the file.\n\n{0}", "無法匯出檔案。\n\n{0}"),
        ["msg.error"] = ("Error", "錯誤"),
        ["msg.webviewMissing"] =
            ("Markdown preview needs the Microsoft Edge WebView2 Runtime.\n\nInstall it from:\nhttps://developer.microsoft.com/microsoft-edge/webview2/",
             "Markdown 預覽需要 Microsoft Edge WebView2 Runtime。\n\n請至下列網址安裝：\nhttps://developer.microsoft.com/microsoft-edge/webview2/"),

        // About dialog
        ["about.title"] = ("About SlimMD", "關於 SlimMD"),
        ["about.version"] = ("Version {0}", "版本 {0}"),
        ["about.tagline"] =
            ("Lightweight Markdown editor and viewer for Windows.",
             "適用於 Windows 的輕巧 Markdown 編輯與瀏覽工具。"),
        ["about.featuresHeader"] = ("Features", "功能"),
        ["about.feature.open"] =
            ("Open, create, edit and save Markdown files",
             "開啟、建立、編輯與儲存 Markdown 檔案"),
        ["about.feature.browse"] =
            ("Browse by default; Edit switches to a split view",
             "預設瀏覽模式，按「編輯」切換為分割畫面"),
        ["about.feature.export"] =
            ("Export to PDF and self-contained HTML",
             "匯出為 PDF 與獨立的 HTML 檔"),
        ["about.feature.lang"] =
            ("English / Traditional Chinese interface",
             "英文 / 繁體中文介面"),
        ["about.feature.theme"] = ("Light and dark themes", "亮色與暗色主題"),
        ["about.builtWith"] =
            ("Built with .NET 9 and WebView2 — low CPU and memory usage by design.",
             "採用 .NET 9 與 WebView2 打造 — 以低 CPU、低記憶體占用為設計目標。"),
        ["about.repo"] = ("GitHub Repository", "GitHub 儲存庫"),
        ["about.license"] = ("License: {0}", "授權：{0}"),
    };

    public static string T(string key) => T(key, Array.Empty<object>());

    public static string T(string key, params object[] args)
    {
        if (!Map.TryGetValue(key, out var pair))
        {
            return key;
        }

        var text = Current == Lang.Zh ? pair.Zh : pair.En;
        return args.Length == 0 ? text : string.Format(text, args);
    }
}
