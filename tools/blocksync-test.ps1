param([string]$Exe = "src\SlimMD\bin\Release\net9.0-windows\SlimMD.exe")

# Block-based scroll sync: the preview must show the block that corresponds to
# the editor's first visible line (not a proportional position).
# Reads the editor's first visible line and the preview's topmost visible
# element through UIA, so window occlusion cannot affect the result.

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
public class B1 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint data, int e);
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
function Raise {
    [B1]::ShowWindow($script:mainH, 9) | Out-Null
    [B1]::SetWindowPos($script:mainH, [B1]::TOPMOST, 0, 0, 0, 0, 0x1 -bor 0x40) | Out-Null
    [B1]::SetForegroundWindow($script:mainH) | Out-Null
    Start-Sleep -Milliseconds 400
}

function Get-Win {
    return [System.Windows.Automation.AutomationElement]::FromHandle($script:mainH)
}

function Get-Buttons {
    $win = Get-Win
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
    $win = Get-Win
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Edit)
    return $win.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $cond)
}

# Text at the top of the editor pane (first visible line, then a bit more).
function Get-EditorTopText {
    $ed = Get-Editor
    if (-not $ed) { return $null }
    $tp = $null
    if (-not $ed.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$tp)) { return $null }
    $vis = $tp.GetVisibleRanges()
    if ($vis.Length -eq 0) { return $null }
    return $vis[0].GetText(200)
}

# Section number of the editor's first visible content (0 = document title,
# 9999 = the end marker). Blank first line: use the next non-blank line.
function Get-EditorSection {
    $text = Get-EditorTopText
    if ($null -eq $text) { return $null }
    foreach ($line in ($text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -eq '') { continue }
        if ($t -like '*Scroll sync probe*') { return 0 }
        if ($t -like '*END-OF-DOCUMENT-MARKER*' -or $t -like '*The Very End*') { return 9999 }
        if ($t -match 'Section (\d+)') { return [int]$Matches[1] }
        if ($t -match 'Paragraph number (\d+)') { return [int]$Matches[1] }
        break
    }
    return -1
}

# Section number of the element sitting at the top of the preview pane.
function Get-PreviewSection {
    $win = Get-Win
    $r = New-Object B1+RECT
    [B1]::GetWindowRect($script:mainH, [ref]$r) | Out-Null
    $previewTop = $r.Top + 40     # below the toolbar

    $names = New-Object System.Collections.Generic.List[string]
    $tops = New-Object System.Collections.Generic.List[int]
    $cond = [System.Windows.Automation.Condition]::TrueCondition
    $all = $win.FindAll([System.Windows.Automation.TreeScope]::Subtree, $cond)
    foreach ($e in $all) {
        $n = $e.Current.Name
        if (-not $n) { continue }
        if ($n -notmatch 'Section \d+|Paragraph number \d+|Scroll sync probe|END-OF-DOCUMENT-MARKER|The Very End') { continue }
        $rect = $e.Current.BoundingRectangle
        if ($rect.Height -le 0) { continue }
        # Inside the preview (right of the editor) and near the top edge.
        if ($rect.X -lt $r.Left + [int](($r.Right - $r.Left) * 0.45)) { continue }
        if ($rect.Y -gt $previewTop + 140) { continue }
        if ($rect.Y -lt $previewTop - 60) { continue }
        $names.Add($n)
        $tops.Add([int]$rect.Y)
    }
    if ($names.Count -eq 0) { return $null }
    # The element at the top of the viewport: the last one starting at or above
    # the top edge (+ a small tolerance for the pane's own padding); otherwise
    # the first one starting below it.
    $best = -1
    $bestY = [int]::MinValue
    for ($i = 0; $i -lt $names.Count; $i++) {
        if ($tops[$i] -le $previewTop + 20 -and $tops[$i] -gt $bestY) { $bestY = $tops[$i]; $best = $i }
    }
    if ($best -lt 0) { $best = 0; for ($i = 1; $i -lt $names.Count; $i++) { if ($tops[$i] -lt $tops[$best]) { $best = $i } } }
    $n = $names[$best]
    if ($n -like '*Scroll sync probe*') { return 0 }
    if ($n -like '*END-OF-DOCUMENT-MARKER*' -or $n -like '*The Very End*') { return 9999 }
    if ($n -match 'Section (\d+)') { return [int]$Matches[1] }
    if ($n -match 'Paragraph number (\d+)') { return [int]$Matches[1] }
    return -1
}

function Assert-Alignment([string]$label) {
    $e = Get-EditorSection
    $p = Get-PreviewSection
    if ($null -eq $e -or $null -eq $p) {
        Report $label $false "editor=$e preview=$p"
        return
    }
    # Off-by-one can legitimately occur when the top line is a blank separator
    # between blocks; anything larger means the sync is not block-based.
    $ok = [Math]::Abs($e - $p) -le 1
    Report $label $ok "editor=$e preview=$p"
}

# True when the preview's last block (the end marker) is inside the viewport.
function Get-PreviewEndVisible {
    $win = Get-Win
    $r = New-Object B1+RECT
    [B1]::GetWindowRect($script:mainH, [ref]$r) | Out-Null
    $cond = [System.Windows.Automation.Condition]::TrueCondition
    $all = $win.FindAll([System.Windows.Automation.TreeScope]::Subtree, $cond)
    foreach ($e in $all) {
        $n = $e.Current.Name
        if (-not $n) { continue }
        if ($n -notmatch 'END-OF-DOCUMENT-MARKER') { continue }
        $rect = $e.Current.BoundingRectangle
        if ($rect.Height -le 0) { continue }
        if ($rect.X -lt $r.Left + [int](($r.Right - $r.Left) * 0.45)) { continue }
        # Inside the window (above the status bar) => it is on screen.
        if ($rect.Y -gt $r.Top + 40 -and $rect.Y -lt $r.Bottom - 40) { return $true }
    }
    return $false
}

# True when the editor's visible text contains the end marker.
function Get-EditorEndVisible {
    $text = Get-EditorTopText
    if ($null -eq $text) { return $false }
    $ed = Get-Editor
    $tp = $null
    if ($ed -and $ed.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$tp)) {
        $vis = $tp.GetVisibleRanges()
        if ($vis.Length -gt 0) { $text = $vis[0].GetText(8000) }
    }
    return ($text -like '*END-OF-DOCUMENT-MARKER*')
}

function Assert-AtEnd([string]$label) {
    $p = Get-PreviewEndVisible
    $e = Get-EditorEndVisible
    Report $label ($p -and $e) "previewEnd=$p editorEnd=$e"
}

# ---------------------------------------------------------------- scenario

$file = Join-Path $root "testdata\scroll_sync.md"
Remove-Item "$env:LOCALAPPDATA\SlimMD\settings.json" -ErrorAction SilentlyContinue

$p = Start-Process (Join-Path $root $Exe) -ArgumentList "`"$file`"" -PassThru
Start-Sleep -Seconds 6
if ($p.HasExited) { Report "app starts" $false "exited early"; exit 1 }
$script:mainH = $p.MainWindowHandle
Report "app starts" $true

# Show the split view.
$shown = $false
for ($try = 0; $try -lt 3 -and -not $shown; $try++) {
    $btns = Get-Buttons
    $pat = $null
    if ($btns.Count -ge 6 -and $btns[5].TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pat)) {
        $pat.Invoke()
    }
    Start-Sleep -Milliseconds 1500
    $ed = Get-Editor
    if ($ed) {
        $tp = $null
        if ($ed.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$tp)) {
            $shown = $tp.DocumentRange.GetText(65536).Contains('## Section')
        }
    }
}
Report "editor pane shown with document text" $shown
if (-not $shown) { Stop-Process -Id $p.Id -Force; exit 1 }

Start-Sleep -Milliseconds 800
Assert-Alignment "aligned at document top"

# --- preview drives the editor: wheel the preview down ---
Raise
$r = New-Object B1+RECT
[B1]::GetWindowRect($script:mainH, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
$x = $r.Left + [int]($w * 0.75); $y = $r.Top + [int]($ht * 0.5)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
Start-Sleep -Milliseconds 300
$wd = [uint32]4294967056
for ($i = 0; $i -lt 25; $i++) { [B1]::mouse_event(0x0800, 0, 0, $wd, 0); Start-Sleep -Milliseconds 40 }
Start-Sleep -Milliseconds 1500
Assert-Alignment "aligned after preview wheel"

# --- editor drives the preview: jump the caret to the end ---
Raise
$ed = Get-Editor
$tp = $null
if ($ed -and $ed.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$tp)) {
    $tp.DocumentRange.Select()
}
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait("^({END})")
Start-Sleep -Milliseconds 2000
Assert-AtEnd "both panes reach the end after editor Ctrl+End"

# --- back to the top ---
Raise
[System.Windows.Forms.SendKeys]::SendWait("^({HOME})")
Start-Sleep -Milliseconds 2000
Assert-Alignment "aligned after editor Ctrl+Home"

# --- preview driven to its end must drag the editor to its end ---
Raise
$r = New-Object B1+RECT
[B1]::GetWindowRect($script:mainH, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
$x = $r.Left + [int]($w * 0.75); $y = $r.Top + [int]($ht * 0.5)
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
Start-Sleep -Milliseconds 300
$wd = [uint32]4294967056
for ($i = 0; $i -lt 200; $i++) { [B1]::mouse_event(0x0800, 0, 0, $wd, 0); Start-Sleep -Milliseconds 15 }
Start-Sleep -Milliseconds 2000
Assert-AtEnd "both panes reach the end after preview wheel to bottom"

[B1]::SetWindowPos($script:mainH, [B1]::NOTOPMOST, 0, 0, 0, 0, 0x1 -bor 0x40) | Out-Null
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }

$failed = @($results | Where-Object { -not $_.OK })
Write-Output ""
Write-Output ("total={0} passed={1} failed={2}" -f $results.Count, ($results.Count - $failed.Count), $failed.Count)
if ($failed.Count) { exit 1 }
