param([string]$Exe = "src\SlimMD\bin\Release\net9.0-windows\SlimMD.exe")

# Verifies the Open dialog actually shows Markdown files (filter strings valid).
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W2 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);
    public static readonly IntPtr TOPMOST = new IntPtr(-1);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = "") {
    if (-not $ok) { $script:fail++ }
    Write-Output ("[{0}] {1} {2}" -f ($(if ($ok) { "PASS" } else { "FAIL" })), $name, $detail)
}

# fresh settings -> English UI
Remove-Item "$env:LOCALAPPDATA\SlimMD\settings.json" -ErrorAction SilentlyContinue
$testFile = Join-Path $root "testdata\e2e_test.md"
Copy-Item (Join-Path $root "testdata\demo.md") $testFile -Force

$p = Start-Process (Join-Path $root $Exe) -ArgumentList "`"$testFile`"" -PassThru
Start-Sleep -Seconds 6
if ($p.HasExited) { Check "app starts" $false "exited early"; exit 1 }
Check "app starts" $true

# toolbar: [New, Open, Save, Save As..., Edit, Language, About] -> Open = index 1
$win = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$btns = @()
$child = $walker.GetFirstChild($win)
while ($child) {
    if ($child.Current.ControlType -eq [System.Windows.Automation.ControlType]::ToolBar) {
        $b = $walker.GetFirstChild($child)
        while ($b) {
            if ($b.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) { $btns += $b }
            $b = $walker.GetNextSibling($b)
        }
    }
    $child = $walker.GetNextSibling($child)
}
Check "toolbar buttons found" ($btns.Count -ge 2) "count=$($btns.Count)"
if ($btns.Count -lt 2) { Stop-Process -Id $p.Id -Force; exit 1 }

# click Open (real mouse click: UIA Invoke blocks on the modal dialog)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class M { [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, int e);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }
"@
[void][M]::SetForegroundWindow($p.MainWindowHandle)
Start-Sleep -Milliseconds 500
$r = $btns[1].Current.BoundingRectangle
$cx = [int]($r.X + $r.Width / 2); $cy = [int]($r.Y + $r.Height / 2)
Write-Output "click at $cx,$cy (btn rect: $r)"
[System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($cx, $cy)
Start-Sleep -Milliseconds 400
[M]::mouse_event(2, 0, 0, 0, 0); Start-Sleep -Milliseconds 60; [M]::mouse_event(4, 0, 0, 0, 0)
Start-Sleep -Seconds 2

# find the dialog window (class #32770)
$dlgHwnd = [IntPtr]::Zero
$enum = {
    param($h, $l)
    $cls = New-Object System.Text.StringBuilder 256
    [void][Win32]::GetClassName($h, $cls, 256)
    if ($cls.ToString() -eq "#32770") { $script:dlgHwnd = $h; return $false }
    return $true
}
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
}
"@
$myPid = [uint32]$p.Id
$found = [IntPtr]::Zero
$cb = [Win32+EnumProc]{
    param($h, $l)
    $pid2 = 0
    [void][Win32]::GetWindowThreadProcessId($h, [ref]$pid2)
    if ($pid2 -eq $script:myPid) {
        $cls = New-Object System.Text.StringBuilder 256
        [void][Win32]::GetClassName($h, $cls, 256)
        if ($cls.ToString() -eq "#32770") { $script:found = $h; return $false }
    }
    return $true
}
[void][Win32]::EnumWindows($cb, [IntPtr]::Zero)
Check "Open dialog appeared" ($found -ne [IntPtr]::Zero)
if ($found -eq [IntPtr]::Zero) {
    # full-screen snapshot to see what actually happened
    $bs = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($bs.Width, $bs.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $root "art\open_dialog_fail.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

if ($found -ne [IntPtr]::Zero) {
    [void][W2]::ShowWindow($found, 9)
    [void][W2]::SetForegroundWindow($found)
    Start-Sleep -Milliseconds 700

    # screenshot the dialog
    $r2 = New-Object W2+RECT
    [void][W2]::GetWindowRect($found, [ref]$r2)
    $w = $r2.Right - $r2.Left; $h2 = $r2.Bottom - $r2.Top
    $bmp = New-Object System.Drawing.Bitmap($w, $h2)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r2.Left, $r2.Top, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $root "art\open_dialog.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()

    # inspect file list items in the dialog
    $dlg = [System.Windows.Automation.AutomationElement]::FromHandle($found)
    $listCond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::List)
    $list = $dlg.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $listCond)
    $items = @()
    if ($list) {
        $w2 = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        $it = $w2.GetFirstChild($list)
        while ($it) { $items += $it.Current.Name; $it = $w2.GetNextSibling($it) }
    }
    $mdItems = @($items | Where-Object { $_ -match '\.md$' })
    Check "dialog lists .md files" ($mdItems.Count -gt 0) ("md={0} total={1}" -f $mdItems.Count, $items.Count)
    Write-Output ("items: " + (($items | Select-Object -First 8) -join " | "))

    # close dialog with Escape
    [W2]::keybd_event(0x1B, 0, 0, 0); Start-Sleep -Milliseconds 80; [W2]::keybd_event(0x1B, 0, 2, 0)
    Start-Sleep -Milliseconds 800
}

Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
Write-Output $(if ($fail -eq 0) { "ALL PASS" } else { "FAILED=$fail" })
exit $fail
