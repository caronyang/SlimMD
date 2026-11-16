param([string]$Exe = "src\SlimMD\bin\Release\net9.0-windows\SlimMD.exe")

# Multi-tab + unsaved-close prompt checks.
#   1. two files on the command line -> tab strip with 2 tabs
#   2. clicking a tab switches the single editor to that document
#   3. closing a tab (context menu) removes it
#   4. closing the window while dirty prompts Yes/No and Cancel keeps it alive

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
public class T2 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint data, int extra);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int max);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    public static string WinText(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
    public static string WinClass(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
    public static readonly IntPtr TOPMOST = new IntPtr(-1);
    public static readonly IntPtr NOTOPMOST = new IntPtr(-2);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$results = @()
function Report([string]$name, [bool]$ok, [string]$detail = "") {
    $script:results += [pscustomobject]@{ Check = $name; OK = $ok; Detail = $detail }
    Write-Output ("[{0}] {1} {2}" -f ($(if ($ok) { "PASS" } else { "FAIL" })), $name, $detail)
}

$script:mainH = [IntPtr]::Zero
function Get-MainH {
    if ($script:mainH -ne [IntPtr]::Zero) { return $script:mainH }
    $p = Get-Process -Name SlimMD -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($p) { return $p.MainWindowHandle }
    return [IntPtr]::Zero
}

function Get-Win {
    $h = Get-MainH
    if (-not $h) { return $null }
    return [System.Windows.Automation.AutomationElement]::FromHandle($h)
}

function Get-ByName([string]$name) {
    $win = Get-Win
    if (-not $win) { return $null }
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    return $win.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $cond)
}

function Get-Tabs {
    $win = Get-Win
    if (-not $win) { return @() }
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::TabItem)
    $all = $win.FindAll([System.Windows.Automation.TreeScope]::Subtree, $cond)
    $out = @()
    foreach ($e in $all) { $out += $e }
    return $out
}

function Get-Editor {
    $win = Get-Win
    if (-not $win) { return $null }
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Edit)
    return $win.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $cond)
}

function Get-ToolbarButtons {
    $win = Get-Win
    if (-not $win) { return @() }
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

# The app starts in browse mode (editor pane collapsed): show the split view.
function Show-Editor {
    if (Get-Editor) { return $true }
    $btns = Get-ToolbarButtons
    if ($btns.Count -lt 6) { return $false }
    Click-Element $btns[5] | Out-Null
    Start-Sleep -Milliseconds 1500
    return [bool](Get-Editor)
}

function Get-EditorText {
    $ed = Get-Editor
    if (-not $ed) { return $null }
    $p = $null
    if (-not $ed.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$p)) { return $null }
    return $p.DocumentRange.GetText(65536)
}

function Move-Cursor([int]$x, [int]$y) {
    for ($i = 0; $i -lt 10; $i++) {
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
        Start-Sleep -Milliseconds 30
        $cp = [System.Windows.Forms.Cursor]::Position
        if ($cp.X -eq $x -and $cp.Y -eq $y) { return $true }
    }
    return $false
}

function Click-Point([int]$x, [int]$y) {
    Move-Cursor $x $y | Out-Null
    [T2]::mouse_event(2, 0, 0, 0, 0)
    $cp = [System.Windows.Forms.Cursor]::Position
    if ($cp.X -ne $x -or $cp.Y -ne $y) {
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
        Start-Sleep -Milliseconds 30
    }
    [T2]::mouse_event(4, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 500
}

function Click-Element($el) {
    if (-not $el) { return $false }
    # Prefer UIA Invoke (immune to the physical-mouse race); fall back to a click.
    $pat = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pat)) {
        $pat.Invoke()
        Start-Sleep -Milliseconds 600
        return $true
    }
    $r = $el.Current.BoundingRectangle
    if ($r.Width -le 0 -or $r.Height -le 0) { return $false }
    [T2]::SetWindowPos((Get-MainH), [T2]::TOPMOST, 0, 0, 0, 0, 0x1 -bor 0x40) | Out-Null
    Click-Point ([int]($r.X + $r.Width / 2)) ([int]($r.Y + $r.Height / 2))
    return $true
}

# Visible top-level window of our process matching a title (modal dialogs).
function Get-DlgHwnd([string]$title) {
    $found = [IntPtr]::Zero
    $main = Get-MainH
    $procId = [uint32]0
    [void][T2]::GetWindowThreadProcessId($main, [ref]$procId)
    $cb = [T2+EnumProc]{
        param($h, $l)
        $p2 = [uint32]0
        [void][T2]::GetWindowThreadProcessId($h, [ref]$p2)
        if ($p2 -eq $script:dlgProc -and $h -ne $script:dlgMain -and [T2]::IsWindowVisible($h)) {
            if ([T2]::WinClass($h) -like "WindowsForms10*" -and [T2]::WinText($h) -eq $script:dlgTitle) {
                $script:dlgFound = $h
            }
        }
        return $true
    }
    $script:dlgProc = $procId
    $script:dlgMain = $main
    $script:dlgTitle = $title
    $script:dlgFound = [IntPtr]::Zero
    [void][T2]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:dlgFound
}

# ---------------------------------------------------------------- scenario

$dir = Join-Path $root "testdata"
$f1 = Join-Path $dir "tabs_a.md"
$f2 = Join-Path $dir "tabs_b.md"
Set-Content -Path $f1 -Value "# Alpha`n`nfirst document body" -Encoding UTF8
Set-Content -Path $f2 -Value "# Beta`n`nsecond document body" -Encoding UTF8

Remove-Item "$env:LOCALAPPDATA\SlimMD\settings.json" -ErrorAction SilentlyContinue

$p = Start-Process (Join-Path $root $Exe) -ArgumentList "`"$f1`"", "`"$f2`"" -PassThru
Start-Sleep -Seconds 6
if ($p.HasExited) { Report "app starts with two files" $false "exited early"; exit 1 }
$script:mainH = $p.MainWindowHandle
Report "app starts with two files" $true

# --- 1. tab strip shows both documents ---
$tabs = Get-Tabs
Report "two tabs are shown" ($tabs.Count -eq 2) "count=$($tabs.Count)"
$names = @($tabs | ForEach-Object { $_.Current.Name })
Report "tab labels are the file names" `
    (($names -contains "tabs_a.md") -and ($names -contains "tabs_b.md")) ($names -join " | ")

# --- 2. show the split view and check the active tab's content ---
Report "editor pane can be shown" (Show-Editor)
$text = Get-EditorText
Report "editor shows the second document" ($text -and $text.Contains("second document body")) `
    "len=$(if ($null -eq $text) { -1 } else { $text.Length })"

# --- 3. selecting the first tab switches the editor ---
$tabA = $null
foreach ($t in $tabs) { if ($t.Current.Name -eq "tabs_a.md") { $tabA = $t } }
if ($tabA) {
    $sel = $null
    if ($tabA.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sel)) {
        $sel.Select()
    } else {
        Click-Element $tabA | Out-Null
    }
    Start-Sleep -Milliseconds 900
    $text2 = Get-EditorText
    Report "switching tab updates the editor" ($text2 -and $text2.Contains("first document body")) `
        "len=$(if ($null -eq $text2) { -1 } else { $text2.Length })"
} else {
    Report "switching tab updates the editor" $false "tab A not found"
}

# --- 4. editing marks the tab dirty ---
$ed = Get-Editor
if ($ed) {
    $sel = $null
    if ($ed.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$sel)) {
        $sel.DocumentRange.Select()
    }
    [T2]::SetForegroundWindow((Get-MainH)) | Out-Null
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait("^({END})")
    Start-Sleep -Milliseconds 200
    [System.Windows.Forms.SendKeys]::SendWait("X")
    Start-Sleep -Milliseconds 700
    $tabs2 = Get-Tabs
    $labels = @($tabs2 | ForEach-Object { $_.Current.Name })
    Report "dirty tab gets an asterisk" ($labels -contains "tabs_a.md*") ($labels -join " | ")
} else {
    Report "dirty tab gets an asterisk" $false "editor not found"
}

# --- 5. the ✕ glyph on a tab header ---
function Get-TabClosePoint($tab) {
    $r = $tab.Current.BoundingRectangle
    if ($r.Width -le 0) { return $null }
    # ClosableTabControl draws the glyph at tab.Right-19 .. tab.Right-5.
    return @([int]($r.X + $r.Width - 12), [int]($r.Y + $r.Height / 2))
}

function Click-TabClose($tab) {
    $pt = Get-TabClosePoint $tab
    if (-not $pt) { return $false }
    [T2]::SetWindowPos((Get-MainH), [T2]::TOPMOST, 0, 0, 0, 0, 0x1 -bor 0x40) | Out-Null
    Click-Point $pt[0] $pt[1]
    return $true
}

$tabs3 = Get-Tabs
$dirtyTab = $null; $cleanTab = $null
foreach ($t in $tabs3) {
    if ($t.Current.Name -like "tabs_a.md*") { $dirtyTab = $t }
    if ($t.Current.Name -eq "tabs_b.md") { $cleanTab = $t }
}

# 5a. clicking ✕ on the dirty tab must prompt (and Cancel keeps both tabs).
if ($dirtyTab -and (Click-TabClose $dirtyTab)) {
    Start-Sleep -Milliseconds 1500
    $dh = Get-DlgHwnd "SlimMD"
    Report "closing a dirty tab via ✕ prompts" ($dh -ne [IntPtr]::Zero)
    if ($dh -ne [IntPtr]::Zero) {
        [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
        Start-Sleep -Milliseconds 1200
        $tabs4 = Get-Tabs
        $vis4 = @($tabs4 | Where-Object { -not $_.Current.IsOffscreen })
        Report "cancel keeps the dirty tab" ($vis4.Count -eq 2) "count=$($vis4.Count)"
    } else {
        Report "cancel keeps the dirty tab" $false "no prompt"
    }
} else {
    Report "closing a dirty tab via ✕ prompts" $false "dirty tab not found"
    Report "cancel keeps the dirty tab" $false "dirty tab not found"
}

# 5b. clicking ✕ on a clean tab closes it without prompting; with one document
# left the tab strip hides itself.
if ($cleanTab -and (Click-TabClose $cleanTab)) {
    Start-Sleep -Milliseconds 1500
    $dh3 = Get-DlgHwnd "SlimMD"
    $tabs5 = Get-Tabs
    $vis5 = @($tabs5 | Where-Object { -not $_.Current.IsOffscreen })
    Report "closing a clean tab via ✕ needs no prompt" ($dh3 -eq [IntPtr]::Zero)
    # One document left => the whole strip is hidden, so UIA exposes no tab items.
    Report "tab strip hides with one document" ($tabs5.Count -eq 0) "total=$($tabs5.Count)"
} else {
    Report "closing a clean tab via ✕ needs no prompt" $false "clean tab not found"
    Report "tab strip hides with one document" $false "clean tab not found"
}

# --- 6. close the window while dirty -> prompt appears; Cancel keeps it alive ---
[T2]::SetWindowPos((Get-MainH), [T2]::NOTOPMOST, 0, 0, 0, 0, 0x1 -bor 0x40) | Out-Null
$p.CloseMainWindow() | Out-Null
Start-Sleep -Milliseconds 1500
$dh = Get-DlgHwnd "SlimMD"
Report "closing a dirty tab prompts" ($dh -ne [IntPtr]::Zero)
if ($dh -ne [IntPtr]::Zero) {
    $dlg = [System.Windows.Automation.AutomationElement]::FromHandle($dh)
    $no = $null
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, "No")
    $no = $dlg.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    Report "prompt has a No button" ($null -ne $no)
    if ($no) {
        # Cancel the close with "No" (discard) would exit; use Escape instead to
        # prove the window survives a cancelled close.
        [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
        Start-Sleep -Milliseconds 1200
        Report "cancelled close keeps the window open" (-not $p.HasExited)
    }
}

# --- 6. No -> discards and closes ---
$p.CloseMainWindow() | Out-Null
Start-Sleep -Milliseconds 1500
$dh2 = Get-DlgHwnd "SlimMD"
if ($dh2 -ne [IntPtr]::Zero) {
    $dlg2 = [System.Windows.Automation.AutomationElement]::FromHandle($dh2)
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, "No")
    $no2 = $dlg2.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($no2) {
        $pat = $null
        if ($no2.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pat)) {
            $pat.Invoke()
        } else {
            $r = $no2.Current.BoundingRectangle
            Click-Point ([int]($r.X + $r.Width / 2)) ([int]($r.Y + $r.Height / 2))
        }
        Start-Sleep -Seconds 3
    }
    Report "No closes the window" ($p.HasExited)
} else {
    Report "No closes the window" $false "second prompt missing"
}

if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }

$failed = @($results | Where-Object { -not $_.OK })
Write-Output ""
Write-Output ("total={0} passed={1} failed={2}" -f $results.Count, ($results.Count - $failed.Count), $failed.Count)
if ($failed.Count) { exit 1 }
