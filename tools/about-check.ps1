param([string]$Exe = "src\SlimMD\bin\Release\net9.0-windows\SlimMD.exe")
# Opens the About dialog (EN and ZH), reports its geometry and screenshots it.
$ErrorActionPreference = "Continue"
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
public class AW {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, int e);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    public static string Txt(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
    public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
    public static readonly IntPtr TOPMOST = new IntPtr(-1);
    public static readonly IntPtr NOTOPMOST = new IntPtr(-2);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$script:mainH = [IntPtr]::Zero
function Get-Target { Get-Process -Name SlimMD -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1 }
function Get-MainH { if ($script:mainH -ne [IntPtr]::Zero) { return $script:mainH }; $p = Get-Target; if ($p) { return $p.MainWindowHandle }; return [IntPtr]::Zero }

function Get-ToolbarButtons {
    $win = [System.Windows.Automation.AutomationElement]::FromHandle((Get-MainH))
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $child = $walker.GetFirstChild($win)
    while ($child) {
        if ($child.Current.ControlType -eq [System.Windows.Automation.ControlType]::ToolBar) {
            $btns = @()
            $b = $walker.GetFirstChild($child)
            while ($b) { if ($b.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) { $btns += $b }; $b = $walker.GetNextSibling($b) }
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

function Get-ProcWindows([uint32]$procId) {
    $script:wins = @()
    $cb = [AW+EnumProc]{ param($h,$l)
        $p2 = 0; [void][AW]::GetWindowThreadProcessId($h, [ref]$p2)
        if ($p2 -eq $script:procId -and [AW]::IsWindowVisible($h)) { $script:wins += $h }
        return $true }
    [void][AW]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:wins
}

function Codepoints([string]$s) { (($s.ToCharArray() | ForEach-Object { "{0:X4}" -f [int]$_ }) -join " ") }

function Open-About([string]$expectedTitle, [string]$shotFile) {
    $main = Get-MainH
    [void][AW]::ShowWindow($main, 9)
    [void][AW]::BringWindowToTop($main)
    # TOPMOST first: other always-on-top windows (editor, browser) otherwise swallow the
    # synthetic click even when the app is the foreground window. Same as e2e's Click-Element.
    [void][AW]::SetWindowPos($main, [AW]::TOPMOST, 0, 0, 0, 0, 0x1 -bor 0x40)
    [void][AW]::SetForegroundWindow($main)
    Start-Sleep -Milliseconds 600
    Write-Output ("  foreground is main: {0} (actual: '{1}')" -f ([AW]::GetForegroundWindow() -eq $main), [AW]::Txt([AW]::GetForegroundWindow()))

    $btns = Get-ToolbarButtons
    $about = $btns[7]
    Write-Output ("  about button '{0}'" -f $about.Current.Name)

    # Synthetic clicks are flaky when another window races for focus - retry up to 3x.
    $found = $null
    for ($attempt = 1; $attempt -le 3 -and -not $found; $attempt++) {
        [void][AW]::BringWindowToTop($main)
        [void][AW]::SetForegroundWindow($main)
        Start-Sleep -Milliseconds 300
        $r = $about.Current.BoundingRectangle
        $x = [int]($r.X + $r.Width / 2); $y = [int]($r.Y + $r.Height / 2)
        Write-Output ("  attempt {0}: click at {1},{2}" -f $attempt, $x, $y)
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
        Start-Sleep -Milliseconds 250
        # The physical mouse can race the synthetic click - re-assert right before pressing.
        $cp = [System.Windows.Forms.Cursor]::Position
        if ($cp.X -ne $x -or $cp.Y -ne $y) {
            [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
            Start-Sleep -Milliseconds 120
        }
        [AW]::mouse_event(2,0,0,0,0); Start-Sleep -Milliseconds 60; [AW]::mouse_event(4,0,0,0,0)
        Start-Sleep -Milliseconds 1500

        $others = @(Get-ProcWindows $script:procId) | Where-Object { $_ -ne $main }
        if ($others.Count -gt 0) {
            $found = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$others[0])
            break
        }
        $fh = [AW]::GetForegroundWindow()
        Write-Output ("    no dialog; foreground h={0} title='{1}'" -f $fh, [AW]::Txt($fh))
    }

    if (-not $found) {
        Write-Output "  all visible process windows:"
        foreach ($h in (Get-ProcWindows $script:procId)) {
            Write-Output ("    h={0} cls='{1}' title='{2}'" -f $h, [AW]::Cls($h), [AW]::Txt($h))
        }
        Write-Output "  !! dialog did not open"; return
    }

    # Verify we really grabbed the dialog: its window text must match the expected title.
    # (A blind name search can hit the About button's tooltip, whose EN text is identical.)
    $fhwnd = [IntPtr]$found.Current.NativeWindowHandle
    $txt = [AW]::Txt($fhwnd)
    if ($txt -cne $expectedTitle) {
        Write-Output ("  !! enumerated window title '{0}' != expected '{1}'" -f $txt, $expectedTitle)
        $byName = Find-Anywhere $expectedTitle
        if ($byName) { $found = $byName }
    }

    $ui = $found.Current.BoundingRectangle
    $hh = [IntPtr]$found.Current.NativeWindowHandle
    $wr = New-Object AW+RECT
    [void][AW]::GetWindowRect($hh, [ref]$wr)
    Write-Output ("  uiaRect=({0},{1}) {2}x{3}" -f $ui.X, $ui.Y, $ui.Width, $ui.Height)
    Write-Output ("  winRect=({0},{1}) {2}x{3}  hwnd={4}" -f $wr.Left, $wr.Top, ($wr.Right-$wr.Left), ($wr.Bottom-$wr.Top), $hh)
    Write-Output ("  uiaTitle='{0}' codepoints={1}" -f $found.Current.Name, (Codepoints $found.Current.Name))

    # A TOPMOST owner would cover its own (non-topmost) modal dialog in the capture:
    # demote the owner first, then bring the dialog forward.
    [void][AW]::SetWindowPos($main, [AW]::NOTOPMOST, 0, 0, 0, 0, 0x1 -bor 0x40)
    [void][AW]::SetForegroundWindow($hh)
    Start-Sleep -Milliseconds 500
    $w = [int]$ui.Width; $hgt = [int]$ui.Height
    if ($w -gt 0 -and $hgt -gt 0) {
        $bmp = New-Object System.Drawing.Bitmap($w, $hgt)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen([int]$ui.X, [int]$ui.Y, 0, 0, $bmp.Size)
        $bmp.Save($shotFile, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        Write-Output ("  -> {0} ({1}x{2})" -f $shotFile, $w, $hgt)
    }

    # close it with Enter (OK has focus)
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Milliseconds 1000
    # Window-based: a name search here would also match the About button's tooltip
    # (same text as the dialog title) while the cursor still hovers the button.
    $still = @(Get-ProcWindows $script:procId) | Where-Object { $_ -ne $main }
    Write-Output ("  closed: {0}" -f ($null -eq $still -or @($still).Count -eq 0))
}

# --- setup: fresh settings (English) ---
Remove-Item "$env:LOCALAPPDATA\SlimMD\settings.json" -ErrorAction SilentlyContinue
$testFile = Join-Path $root "testdata\e2e_test.md"
Copy-Item (Join-Path $root "testdata\demo.md") $testFile -Force
$p = Start-Process (Join-Path $root $Exe) -ArgumentList "`"$testFile`"" -PassThru
Start-Sleep -Seconds 6
$script:mainH = $p.MainWindowHandle
$script:procId = [uint32]$p.Id
Write-Output "=== EN ==="
Open-About "About SlimMD" (Join-Path $root "art\about_en.png")

# --- switch to Chinese ---
$btns = Get-ToolbarButtons
$pat = $null
if ($btns[6].TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$pat)) { [void]$pat.Expand() }
Start-Sleep -Milliseconds 800
$zhItem = "$([char]0x4E2D)$([char]0x6587)"
$item = Find-Anywhere $zhItem
if ($item) {
    $ip = $null
    if ($item.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$ip)) { [void]$ip.Invoke() }
    Start-Sleep -Milliseconds 1300
    Write-Output "switched to Chinese"
}

Write-Output "=== ZH ==="
$zhAbout = "$([char]0x95DC)$([char]0x65BC) SlimMD"
Write-Output ("  expected title codepoints={0}" -f (Codepoints $zhAbout))
Open-About $zhAbout (Join-Path $root "art\about_zh.png")

if ($p) { if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force } }
Write-Output "done"
