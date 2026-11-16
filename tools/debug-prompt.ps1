# Debug: reproduce the unsaved prompt and dump its UIA tree + screenshot.
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
public class D2 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int max);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    public static string Txt(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
    public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$testFile = Join-Path $root "testdata\demo.md"
$p = Start-Process (Join-Path $root "src\SlimMD\bin\Release\net9.0-windows\SlimMD.exe") -ArgumentList "`"$testFile`"" -PassThru
Start-Sleep -Seconds 6
$script:mainH = $p.MainWindowHandle
$script:procId = [uint32]$p.Id
Write-Output "main=$($script:mainH) alive=$(-not $p.HasExited)"

$win = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)

# Show the split view (editor pane) via Invoke on the toolbar's Edit button.
function Get-ToolbarButtons {
    $w = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $child = $walker.GetFirstChild($w)
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
$btns = Get-ToolbarButtons
Write-Output "toolbar buttons: $($btns.Count) [$(($btns | ForEach-Object { $_.Current.Name }) -join ', ')]"
$pat = $null
if ($btns.Count -ge 6 -and $btns[5].TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pat)) {
    $pat.Invoke()
}
Start-Sleep -Milliseconds 1500

# Focus the editor and type one character so the document becomes dirty.
$edCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Edit)
$ed = $win.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $edCond)
if (-not $ed) { Write-Output "editor not found"; exit 1 }
[D2]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 400
$tp = $null
if ($ed.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$tp)) {
    $tp.DocumentRange.Select()
}
[System.Windows.Forms.SendKeys]::SendWait("Z")
Start-Sleep -Milliseconds 700
Write-Output "title after typing: $([D2]::Txt($p.MainWindowHandle))"

# Close the main window -> the prompt must appear.
$p.CloseMainWindow() | Out-Null
Start-Sleep -Milliseconds 1500
Write-Output "alive after close request: $(-not $p.HasExited)"

$found = [IntPtr]::Zero
$cb = [D2+EnumProc]{
    param($h, $l)
    $p2 = [uint32]0
    [void][D2]::GetWindowThreadProcessId($h, [ref]$p2)
    if ($p2 -eq $script:procId -and $h -ne $script:mainH -and [D2]::IsWindowVisible($h) -and [D2]::Txt($h) -eq "SlimMD") {
        $script:found = $h
    }
    return $true
}
[void][D2]::EnumWindows($cb, [IntPtr]::Zero)
$found = $script:found
Write-Output "dialog hwnd: $found"

if ($found -ne [IntPtr]::Zero) {
    $r = New-Object D2+RECT
    [D2]::GetWindowRect($found, [ref]$r) | Out-Null
    Write-Output "rect: $($r.Left),$($r.Top) size=$($r.Right - $r.Left)x$($r.Bottom - $r.Top)"
    $bmp = New-Object System.Drawing.Bitmap(($r.Right - $r.Left), ($r.Bottom - $r.Top))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $root "art\debug_prompt.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()

    $dlg = [System.Windows.Automation.AutomationElement]::FromHandle($found)
    $all = $dlg.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($e in $all) {
        $r2 = $e.Current.BoundingRectangle
        Write-Output ("UIA: {0} name='{1}' rect=({2},{3},{4}x{5})" -f
            $e.Current.ControlType.ProgrammaticName, $e.Current.Name,
            [int]$r2.X, [int]$r2.Y, [int]$r2.Width, [int]$r2.Height)
    }
    $dRect = $dlg.Current.BoundingRectangle
    Write-Output ("dialog rect: ({0},{1},{2}x{3})" -f [int]$dRect.X, [int]$dRect.Y, [int]$dRect.Width, [int]$dRect.Height)
} else {
    Write-Output "NO DIALOG FOUND"
}

if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
