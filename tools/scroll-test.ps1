param([string]$Exe = "src\SlimMD\bin\Release\net9.0-windows\SlimMD.exe")

# Editor <-> preview scroll synchronisation.
#   1. caret to end of a long document (editor scrolls) -> preview viewport moves
#   2. wheel-scroll the preview -> editor viewport moves
# Both are checked by comparing cropped screenshots of the preview/editor panes.

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
public class S1 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint data, int e);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
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
    $p = Get-Process -Name SlimMD -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
    if ($p) { return $p.MainWindowHandle }
    return [IntPtr]::Zero
}

function Grab([string]$file) {
    $h = Get-MainH
    if (-not $h) { return $false }
    [S1]::ShowWindow($h, 9) | Out-Null
    [S1]::SetWindowPos($h, [S1]::TOPMOST, 0, 0, 0, 0, 0x1 -bor 0x40) | Out-Null
    [S1]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 600
    $r = New-Object S1+RECT
    [S1]::GetWindowRect($h, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    return $true
}

# Difference ratio between two PNGs over a crop (0 = identical, 1 = totally different).
function Diff-Ratio([string]$a, [string]$b, [int]$x, [int]$y, [int]$w, [int]$h, [int]$step = 4) {
    $ba = [System.Drawing.Bitmap]::FromFile($a)
    $bb = [System.Drawing.Bitmap]::FromFile($b)
    try {
        $diff = 0; $total = 0
        for ($py = $y; $py -lt [Math]::Min($y + $h, $ba.Height); $py += $step) {
            for ($px = $x; $px -lt [Math]::Min($x + $w, $ba.Width); $px += $step) {
                $ca = $ba.GetPixel($px, $py); $cb = $bb.GetPixel($px, $py)
                $d = [Math]::Abs($ca.R - $cb.R) + [Math]::Abs($ca.G - $cb.G) + [Math]::Abs($ca.B - $cb.B)
                if ($d -gt 40) { $diff++ }
                $total++
            }
        }
        if ($total -eq 0) { return 1.0 }
        return [double]$diff / $total
    }
    finally { $ba.Dispose(); $bb.Dispose() }
}

function Get-ToolbarButtons {
    $win = [System.Windows.Automation.AutomationElement]::FromHandle((Get-MainH))
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $child = $walker.GetFirstChild($win)
    while ($child) {
        if ($child.Current.ControlType -eq [System.Windows.Automation.ControlType]::ToolBar) {
            $btns = @(); $b = $walker.GetFirstChild($child)
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

function Get-Editor {
    $win = [System.Windows.Automation.AutomationElement]::FromHandle((Get-MainH))
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Edit)
    return $win.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $cond)
}

# ---------------------------------------------------------------- scenario

# A document long enough that both panes have a real scroll range.
$md = @()
$md += "# Scroll sync probe"
$md += ""
for ($i = 1; $i -le 220; $i++) {
    $md += "## Section $i"
    $md += ""
    $md += "Paragraph number $i with some body text so the preview has real height."
    $md += ""
}
$md += "## The Very End"
$md += ""
$md += "END-OF-DOCUMENT-MARKER"
$md += ""
$file = Join-Path $root "testdata\scroll_sync.md"
Set-Content -Path $file -Value ($md -join "`r`n") -Encoding UTF8

Remove-Item "$env:LOCALAPPDATA\SlimMD\settings.json" -ErrorAction SilentlyContinue

$p = Start-Process (Join-Path $root $Exe) -ArgumentList "`"$file`"" -PassThru
Start-Sleep -Seconds 6
if ($p.HasExited) { Report "app starts" $false "exited early"; exit 1 }
$script:mainH = $p.MainWindowHandle
Report "app starts" $true

# Show the split view (Invoke, not a mouse click).
$btns = Get-ToolbarButtons
if ($btns.Count -ge 6) {
    $pat = $null
    if ($btns[5].TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pat)) {
        $pat.Invoke()
        Start-Sleep -Milliseconds 1500
    }
}
$ed = Get-Editor
Report "split view visible" ($null -ne $ed)

$shot1 = Join-Path $root "art\scroll_before.png"
$shot2 = Join-Path $root "art\scroll_after.png"
Grab $shot1 | Out-Null

# --- 1. editor -> preview: jump the caret to the end (the editor must scroll) ---
if ($ed) {
    $tp = $null
    if ($ed.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$tp)) {
        $tp.DocumentRange.Select()
    }
    [S1]::SetForegroundWindow((Get-MainH)) | Out-Null
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait("^({END})")
    Start-Sleep -Milliseconds 2000
}
Grab $shot2 | Out-Null

$w = 0; $h = 0
$r = New-Object S1+RECT
[S1]::GetWindowRect((Get-MainH), [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
# Preview pane is the right ~55% of the window, below the toolbar/status bar.
$px = [int]($w * 0.55); $py = [int]($h * 0.18)
$pw = [int]($w * 0.42); $ph = [int]($h * 0.65)
$d1 = Diff-Ratio $shot1 $shot2 $px $py $pw $ph
Report "editor scroll moves the preview" ($d1 -gt 0.02) ("diff=" + [Math]::Round($d1, 4))

# --- 2. preview -> editor: wheel-scroll the preview, the editor must follow ---
# Put the caret back at the top first so the editor has room to move.
if ($ed) {
    [S1]::SetForegroundWindow((Get-MainH)) | Out-Null
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait("^({HOME})")
    Start-Sleep -Milliseconds 1500
}
Grab $shot1 | Out-Null

# Wheel down over the preview area.
$x = [int]($r.Left + $w * 0.75)
$y = [int]($r.Top + $h * 0.55)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
Start-Sleep -Milliseconds 400
$wheelData = [uint32]4294967056   # -240 as a signed DWORD (wheel down)
for ($i = 0; $i -lt 8; $i++) { [S1]::mouse_event(0x0800, 0, 0, $wheelData, 0); Start-Sleep -Milliseconds 60 }
Start-Sleep -Milliseconds 2000
Grab $shot2 | Out-Null

# Editor pane is the left ~45%.
$ex = [int]($w * 0.04); $ey = [int]($h * 0.18)
$ew = [int]($w * 0.44); $eh = [int]($h * 0.65)
$d2 = Diff-Ratio $shot1 $shot2 $ex $ey $ew $eh
Report "preview scroll moves the editor" ($d2 -gt 0.02) ("diff=" + [Math]::Round($d2, 4))

if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }

$failed = @($results | Where-Object { -not $_.OK })
Write-Output ""
Write-Output ("total={0} passed={1} failed={2}" -f $results.Count, ($results.Count - $failed.Count), $failed.Count)
if ($failed.Count) { exit 1 }
