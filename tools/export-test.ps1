param([string]$Exe = "src\SlimMD\bin\Release\net9.0-windows\SlimMD.exe")

# Drives the real Export flow: toolbar -> menu item -> SaveFileDialog -> file on disk.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class EW {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, int e);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
}
"@

$script:results = @()
function Report([string]$name, [bool]$ok, [string]$detail = "") {
    $script:results += [pscustomobject]@{ Check = $name; OK = $ok }
    Write-Output ("[{0}] {1} {2}" -f ($(if ($ok) { "PASS" } else { "FAIL" })), $name, $detail)
}

function Get-Target { Get-Process -Name SlimMD -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1 }

# Process.MainWindowHandle starts returning the menu's SysShadow window once a
# dropdown has been opened - cache the real main-form handle instead.
$script:mainH = [IntPtr]::Zero
function Get-MainH {
    if ($script:mainH -ne [IntPtr]::Zero) { return $script:mainH }
    $p = Get-Target
    if ($p) { return $p.MainWindowHandle }
    return [IntPtr]::Zero
}

function Get-ToolbarButtons {
    $h = Get-MainH
    if (-not $h) { return @() }
    $win = [System.Windows.Automation.AutomationElement]::FromHandle($h)
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $child = $walker.GetFirstChild($win)
    while ($child) {
        if ($child.Current.ControlType -eq [System.Windows.Automation.ControlType]::ToolBar) {
            $btns = @()
            $b = $walker.GetFirstChild($child)
            while ($b) {
                if ($b.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) { $btns += $b }
                $b = $walker.GetNextSibling($b)
            }
            return $btns
        }
        $child = $walker.GetNextSibling($child)
    }
    return @()
}

function Find-Anywhere([string]$name) {
    $win = [System.Windows.Automation.AutomationElement]::FromHandle((Get-MainH))
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    $el = $win.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $cond)
    if ($el) { return $el }
    $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
    $el = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    if (-not $el) { $el = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond) }
    return $el
}

function Get-DialogHwnd([uint32]$procId) {
    $script:found = [IntPtr]::Zero
    $cb = [EW+EnumProc]{
        param($h, $l)
        $pid2 = 0
        [void][EW]::GetWindowThreadProcessId($h, [ref]$pid2)
        if ($pid2 -eq $script:procId -and [EW]::Cls($h) -eq "#32770") { $script:found = $h; return $false }
        return $true
    }
    [void][EW]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:found
}

# Click at an element's centre. Do NOT steal foreground first when the target is
# inside a popup - activating another window closes the popup before we click.
function Click-Element($el, [bool]$setForeground = $false) {
    $r = $el.Current.BoundingRectangle
    if ($r.Width -le 0 -or $r.Height -le 0) { return $false }
    $x = [int]($r.X + $r.Width / 2)
    $y = [int]($r.Y + $r.Height / 2)
    if ($setForeground) { [void][EW]::SetForegroundWindow((Get-MainH)); Start-Sleep -Milliseconds 300 }
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 250
    [EW]::mouse_event(2, 0, 0, 0, 0); Start-Sleep -Milliseconds 60; [EW]::mouse_event(4, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 500
    return $true
}

function Get-StatusText {
    $win = [System.Windows.Automation.AutomationElement]::FromHandle((Get-MainH))
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::StatusBar)
    $s = $win.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if (-not $s) { return "" }
    # StatusStrip exposes the text on its child labels, not on the bar itself
    $w = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $names = @()
    $c = $w.GetFirstChild($s)
    while ($c) { if ($c.Current.Name) { $names += $c.Current.Name }; $c = $w.GetNextSibling($c) }
    return ($names -join " ")
}

# --- setup ---
Remove-Item "$env:LOCALAPPDATA\SlimMD\settings.json" -ErrorAction SilentlyContinue
$testFile = Join-Path $root "testdata\e2e_test.md"
Copy-Item (Join-Path $root "testdata\demo.md") $testFile -Force
# The Save dialog defaults to "<basename><ext>" in the document folder, so the
# exports land next to the opened file.
$pdfOut = Join-Path $root "testdata\e2e_test.pdf"
$htmlOut = Join-Path $root "testdata\e2e_test.html"
Remove-Item $pdfOut, $htmlOut -ErrorAction SilentlyContinue

$p = Start-Process (Join-Path $root $Exe) -ArgumentList "`"$testFile`"" -PassThru
Start-Sleep -Seconds 6
if ($p.HasExited) { Report "app starts" $false "exited early"; exit 1 }
$script:mainH = $p.MainWindowHandle
$script:procId = [uint32]$p.Id
Report "app starts" $true

function Export-File([string]$menuItem, [string]$targetPath) {
    $script:exportOk = $false
    $btns = Get-ToolbarButtons
    if ($btns.Count -lt 8) { Report "toolbar ready" $false "count=$($btns.Count)"; return }

    # open the Export dropdown (ExpandCollapse - no foreground stealing)
    $pat = $null
    if ($btns[4].TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$pat)) {
        [void]$pat.Expand()
    } else {
        Click-Element $btns[4] $true | Out-Null
    }
    Start-Sleep -Milliseconds 900

    $item = Find-Anywhere $menuItem
    if (-not $item) { Report "menu item '$menuItem'" $false "not found"; return }
    Click-Element $item $false | Out-Null   # never activate a window here - it closes the menu

    # wait for the SaveFileDialog
    $dlg = [IntPtr]::Zero
    foreach ($t in 1..20) {
        Start-Sleep -Milliseconds 500
        $dlg = Get-DialogHwnd $script:procId
        if ($dlg -ne [IntPtr]::Zero) { break }
    }
    Report "Save dialog opens ($([System.IO.Path]::GetFileName($targetPath)))" ($dlg -ne [IntPtr]::Zero)
    if ($dlg -eq [IntPtr]::Zero) { return }

    [void][EW]::ShowWindow($dlg, 9)
    [void][EW]::SetForegroundWindow($dlg)
    Start-Sleep -Milliseconds 700

    # The dialog opens with the file-name box focused and pre-filled with
    # "<basename><ext>" in LastDirectory - exactly where we expect the output.
    # (Typing a path is deliberately avoided: the first Edit in the dialog is
    # the search box, which silently swallows input.)
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

    # wait for the dialog to close and the file to appear
    $closed = $false
    foreach ($t in 1..20) {
        Start-Sleep -Milliseconds 500
        if ((Get-DialogHwnd $script:procId) -eq [IntPtr]::Zero) { $closed = $true; break }
    }
    Report "Save dialog accepted" $closed

    $ok = $false
    foreach ($t in 1..30) {
        Start-Sleep -Milliseconds 500
        if ((Test-Path $targetPath) -and ((Get-Item $targetPath).Length -gt 0)) { $ok = $true; break }
    }
    $size = 0
    if (Test-Path $targetPath) { $size = (Get-Item $targetPath).Length }
    Report "export wrote file ($([System.IO.Path]::GetFileName($targetPath)))" $ok "size=$size"
    $script:exportOk = $ok
}

# --- export PDF ---
Export-File "Export as PDF..." $pdfOut
$didPdf = $script:exportOk
if ($didPdf) {
    $st = Get-StatusText
    Report "status bar reports export" ($st -match "Exported") "status='$st'"
}

# --- export HTML ---
Export-File "Export as HTML..." $htmlOut

# --- verify contents ---
if (Test-Path $pdfOut) {
    $bytes = [System.IO.File]::ReadAllBytes($pdfOut)
    $head = [System.Text.Encoding]::ASCII.GetString($bytes[0..([Math]::Min(7, $bytes.Length - 1))])
    Report "PDF has %PDF header" ($head.StartsWith("%PDF")) "head=$head"
    $tailLen = [Math]::Min(32, $bytes.Length)
    $tail = [System.Text.Encoding]::ASCII.GetString($bytes[($bytes.Length - $tailLen)..($bytes.Length - 1)])
    Report "PDF has %%EOF trailer" ($tail -match "%%EOF")
}

if (Test-Path $htmlOut) {
    $html = [System.IO.File]::ReadAllText($htmlOut)
    Report "HTML has article#content" ($html -match '<article id="content"')
    Report "HTML inlines preview.css" ($html -match '\.markdown-body\s*\{')
    Report "HTML has rendered heading" ($html -match '<h1')
    Report "HTML keeps external links" ($html -match 'https://openai\.com')
    Report "HTML rewrites doc:// urls" (-not ($html -match 'https://doc/'))
    Report "HTML references local image" ($html -match 'src="[^"]*logo\.png"')
    $b0 = [System.IO.File]::ReadAllBytes($htmlOut)
    $hasBom = ($b0.Length -ge 3 -and $b0[0] -eq 239 -and $b0[1] -eq 187 -and $b0[2] -eq 191)
    Report "HTML has no BOM" (-not $hasBom)
}

# --- close ---
$proc = Get-Target
if ($proc) { $proc.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 2; if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force } }

$failed = @($script:results | Where-Object { -not $_.OK })
Write-Output ""
Write-Output ("total={0} passed={1} failed={2}" -f $script:results.Count, ($script:results.Count - $failed.Count), $failed.Count)
if ($failed.Count) { exit 1 }
exit 0
