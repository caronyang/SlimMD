param([string]$Exe = "src\SlimMD\bin\Release\net9.0-windows\SlimMD.exe")

# Captures the README screenshots (browse / split / About, EN + ZH) into art\.
# The window is raised TOPMOST before each capture so nothing overlaps it.
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
public class RW {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern void mouse_event(uint fl, uint dx, uint dy, uint d, int e);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int max);
    public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    public static readonly int GWL_EXSTYLE = -20;
    public static readonly int WS_EX_TOPMOST = 0x8;
    public static readonly int SW_MINIMIZE = 6;
    public static readonly int SW_RESTORE = 9;
    public static string Txt(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
    public static readonly IntPtr TOPMOST = new IntPtr(-1);
    public static readonly IntPtr NOTOPMOST = new IntPtr(-2);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$script:mainH = [IntPtr]::Zero
$script:procId = [uint32]0
function Get-MainH { $script:mainH }

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

# Move the cursor off the window: a hover state (tooltip / highlight) must not
# end up in the screenshot.
function Park-Cursor {
    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
    [System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new($vs.Right - 5, $vs.Bottom - 5)
    Start-Sleep -Milliseconds 700
}

# Foreign windows covering the capture area would leak into the screenshot -
# minimise them for the duration of the shot, then restore exactly the ones we
# touched (never touch our own process or the shell).
function Suppress-Overlap([int]$x, [int]$y, [int]$w, [int]$ht) {
    $script:suppressed = @()
    $script:suppressedInfo = @()
    $script:capX = $x; $script:capY = $y
    $script:capR = $x + $w; $script:capB = $y + $ht
    $cb = [RW+EnumProc]{
        param($h, $l)
        if ($h -eq $script:mainH -or -not [RW]::IsWindowVisible($h) -or [RW]::IsIconic($h)) { return $true }
        $p2 = [uint32]0
        [void][RW]::GetWindowThreadProcessId($h, [ref]$p2)
        if ($p2 -eq $script:ourPid) { return $true }
        $r = New-Object RW+RECT
        [void][RW]::GetWindowRect($h, [ref]$r)
        # only windows that actually intersect the capture rectangle
        if ($r.Left -lt $script:capR -and $r.Right -gt $script:capX -and
            $r.Top -lt $script:capB -and $r.Bottom -gt $script:capY) {
            [void][RW]::ShowWindow($h, [RW]::SW_MINIMIZE)
            $script:suppressed += $h
            # never Write-Output inside the callback - output here can corrupt the
            # bool return value and abort EnumWindows midway; collect instead.
            $script:suppressedInfo += ("h=$h txt='{0}' rect=({1},{2},{3},{4})" -f [RW]::Txt($h), $r.Left, $r.Top, $r.Right, $r.Bottom)
        }
        return $true
    }
    [void][RW]::EnumWindows($cb, [IntPtr]::Zero)
    foreach ($info in $script:suppressedInfo) { Write-Output "    suppressed: $info" }
    if ($script:suppressed.Count -gt 0) { Start-Sleep -Milliseconds 600 }
}

function Restore-Overlap {
    foreach ($h in $script:suppressed) {
        if ([RW]::IsWindow($h)) { [void][RW]::ShowWindow($h, [RW]::SW_RESTORE) }
    }
    $script:suppressed = @()
}

# Click empty whitespace in the preview so the toolbar loses its focus rectangle
# (xFrac: 0.5 in browse view, ~0.75 in split view where the preview is the right half).
function Click-Preview([double]$xFrac) {
    $r = New-Object RW+RECT
    [void][RW]::GetWindowRect((Get-MainH), [ref]$r)
    $cx = [int](($r.Left + $r.Right - $r.Left) * $xFrac); $cx = $r.Left + $cx
    $cy = $r.Bottom - 60
    for ($i = 0; $i -lt 8; $i++) {
        [System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new($cx, $cy)
        Start-Sleep -Milliseconds 30
        $cp = [System.Windows.Forms.Cursor]::Position
        if ($cp.X -eq $cx -and $cp.Y -eq $cy) { break }
    }
    [RW]::mouse_event(2,0,0,0,0); Start-Sleep -Milliseconds 60
    $cp = [System.Windows.Forms.Cursor]::Position
    if ($cp.X -ne $cx -or $cp.Y -ne $cy) { [System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new($cx, $cy); Start-Sleep -Milliseconds 30 }
    [RW]::mouse_event(4,0,0,0,0)
    Start-Sleep -Milliseconds 400
}

function Shot-Window([string]$file) {
    $h = Get-MainH
    [void][RW]::ShowWindow($h, 9)
    [void][RW]::SetWindowPos($h, [RW]::TOPMOST, 0, 0, 0, 0, 0x3 -bor 0x40)
    [void][RW]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 500
    Park-Cursor
    $r = New-Object RW+RECT
    [void][RW]::GetWindowRect($h, [ref]$r)
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    # PrintWindow requests the pixels from the window itself. CopyFromScreen
    # kept grabbing a stale/occluded frame (UIA said split view but the shot
    # showed browse mode), so use the window's own rendering instead.
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [void][RW]::PrintWindow($h, $hdc, 2)   # PW_RENDERFULLCONTENT
    $g.ReleaseHdc($hdc)
    $g.Dispose()
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Restore-Overlap
    Write-Output "-> $file ($w x $ht)"
}

function Invoke-Button([int]$index, [string]$expectAfter) {
    $btns = Get-ToolbarButtons
    if ($btns.Count -le $index) { throw "toolbar has only $($btns.Count) buttons" }
    $ip = $null
    if ($btns[$index].TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$ip)) {
        [void]$ip.Invoke()
    } else {
        # no InvokePattern - fall back to a real mouse click
        $r = $btns[$index].Current.BoundingRectangle
        $x = [int]($r.X + $r.Width / 2); $y = [int]($r.Y + $r.Height / 2)
        [void][RW]::SetWindowPos((Get-MainH), [RW]::TOPMOST, 0, 0, 0, 0, 0x3 -bor 0x40)
        [void][RW]::SetForegroundWindow((Get-MainH))
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
        Start-Sleep -Milliseconds 30
        $cp = [System.Windows.Forms.Cursor]::Position
        if ($cp.X -ne $x -or $cp.Y -ne $y) { [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y); Start-Sleep -Milliseconds 30 }
        [RW]::mouse_event(2,0,0,0,0); Start-Sleep -Milliseconds 60; [RW]::mouse_event(4,0,0,0,0)
    }
    Start-Sleep -Milliseconds 900
    $now = (Get-ToolbarButtons)[$index].Current.Name
    if ($expectAfter -and $now -ne $expectAfter) { throw "button $index is '$now', expected '$expectAfter'" }
}

# Real mouse click for the About button (UIA Invoke would block on the modal dialog).
function Click-About {
    $script:aboutTitle = "About SlimMD"
    $btns = Get-ToolbarButtons
    $r = $btns[7].Current.BoundingRectangle
    $x = [int]($r.X + $r.Width / 2); $y = [int]($r.Y + $r.Height / 2)
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        [void][RW]::SetWindowPos((Get-MainH), [RW]::TOPMOST, 0, 0, 0, 0, 0x3 -bor 0x40)
        [void][RW]::BringWindowToTop((Get-MainH))
        [void][RW]::SetForegroundWindow((Get-MainH))
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
        Start-Sleep -Milliseconds 30
        $cp = [System.Windows.Forms.Cursor]::Position
        if ($cp.X -ne $x -or $cp.Y -ne $y) { [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y); Start-Sleep -Milliseconds 30 }
        [RW]::mouse_event(2,0,0,0,0); Start-Sleep -Milliseconds 60
        # re-assert between down and up: the physical mouse may have dragged us off
        $cp = [System.Windows.Forms.Cursor]::Position
        if ($cp.X -ne $x -or $cp.Y -ne $y) { [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y); Start-Sleep -Milliseconds 30 }
        [RW]::mouse_event(4,0,0,0,0)
        Start-Sleep -Milliseconds 1300
        $script:dlgH = [IntPtr]::Zero
        $script:dlgMain = Get-MainH
        # Only accept a real WinForms dialog of ours: filter by class + title,
        # otherwise a tooltip / dropdown of the same process can be mistaken for it.
        $cb = [RW+EnumProc]{
            param($h, $l)
            $p2 = [uint32]0
            [void][RW]::GetWindowThreadProcessId($h, [ref]$p2)
            if ($p2 -eq $script:procId -and $h -ne $script:dlgMain -and [RW]::IsWindowVisible($h)) {
                if ([RW]::Txt($h) -eq $script:aboutTitle -and [RW]::Cls($h) -like "WindowsForms10*") { $script:dlgH = $h }
            }
            return $true
        }
        [void][RW]::EnumWindows($cb, [IntPtr]::Zero)
        if ($script:dlgH -ne [IntPtr]::Zero) { return $script:dlgH }
    }
    throw "About dialog did not open"
}

function Shot-Dialog([IntPtr]$dh, [string]$file) {
    Park-Cursor
    # demote the owner, raise the dialog - otherwise the TOPMOST owner covers it
    [void][RW]::SetWindowPos((Get-MainH), [RW]::NOTOPMOST, 0, 0, 0, 0, 0x3 -bor 0x40)
    [void][RW]::SetForegroundWindow($dh)
    Start-Sleep -Milliseconds 500
    $r = New-Object RW+RECT
    [void][RW]::GetWindowRect($dh, [ref]$r)
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    Suppress-Overlap $r.Left $r.Top $w $ht
    # The dialog has rounded corners and an invisible resize border, so the
    # capture includes a margin that shows whatever is behind the dialog.
    # Put a plain white borderless window directly behind it (below the dialog
    # in z-order, above everything else) so that margin is clean white.
    $filler = New-Object System.Windows.Forms.Form
    $filler.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $filler.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
    $filler.BackColor = [System.Drawing.Color]::White
    $filler.ShowInTaskbar = $false
    $filler.Bounds = [System.Drawing.Rectangle]::new($r.Left - 80, $r.Top - 80, $w + 160, $ht + 160)
    [void]$filler.Show()
    # place the filler right below the dialog in the Z order, but above all
    # other windows (HWND_TOP = 0 puts it at top; then re-raise the dialog)
    [void][RW]::SetWindowPos($filler.Handle, [IntPtr]::Zero, 0, 0, 0, 0, 0x3 -bor 0x40)
    [void][RW]::SetWindowPos($dh, [IntPtr]::Zero, 0, 0, 0, 0, 0x3 -bor 0x40)
    Start-Sleep -Milliseconds 300
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    $filler.Close(); $filler.Dispose()
    Restore-Overlap
    Write-Output "-> $file ($w x $ht)"
    # Close the modal dialog with WM_CLOSE - SendKeys depends on which window
    # owns the foreground, which Restore-Overlap may have just stolen.
    [void][RW]::PostMessage($dh, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)  # WM_CLOSE
    for ($i = 0; $i -lt 20 -and [RW]::IsWindow($dh); $i++) { Start-Sleep -Milliseconds 250 }
    if ([RW]::IsWindow($dh)) { throw "About dialog did not close after WM_CLOSE" }
    [void][RW]::SetWindowPos((Get-MainH), [RW]::TOPMOST, 0, 0, 0, 0, 0x3 -bor 0x40)
}

# ------------------------------------------------------------------ capture
Remove-Item "$env:LOCALAPPDATA\SlimMD\settings.json" -ErrorAction SilentlyContinue
$testFile = Join-Path $root "testdata\readme_demo.md"
Copy-Item (Join-Path $root "testdata\demo.md") $testFile -Force
$p = Start-Process (Join-Path $root $Exe) -ArgumentList "`"$testFile`"" -PassThru
Start-Sleep -Seconds 6
$script:mainH = $p.MainWindowHandle
$script:procId = [uint32]$p.Id
$script:ourPid = $script:procId
$script:suppressed = @()

# 1) EN browse
Shot-Window (Join-Path $root "art\readme_browse_en.png")

# 2) EN split view (Edit -> Hide Editor)
# The UIA element can go stale after the previous shot's window suppression /
# restore, which makes Invoke fail silently - verify the label and retry.
$splitLabel = "Hide Editor"
for ($try = 0; $try -lt 3; $try++) {
    try { Invoke-Button 5 $splitLabel; break }
    catch {
        if ($try -eq 2) { throw }
        Write-Output "Edit toggle failed (attempt $($try + 1)), retrying..."
        Start-Sleep -Milliseconds 800
    }
}
Shot-Window (Join-Path $root "art\readme_split_en.png")

# 3) EN About
$dlg = Click-About
Shot-Dialog $dlg (Join-Path $root "art\readme_about_en.png")

# 4) switch to Chinese, back to browse view
$btns = Get-ToolbarButtons
$pat = $null
if ($btns[6].TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$pat)) { [void]$pat.Expand() }
Start-Sleep -Milliseconds 800
$zhItem = Find-Anywhere "$([char]0x4E2D)$([char]0x6587)"
if (-not $zhItem) { throw "Chinese menu item not found" }
$ip = $null
if ($zhItem.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$ip)) { [void]$ip.Invoke() }
else { throw "no InvokePattern on Chinese item" }
Start-Sleep -Milliseconds 1300

# Edit button (index 5) now reads 隱藏編輯區 - click it to return to browse view,
# after which the label is back to 編輯.
$browseLabel = "$([char]0x7DE8)$([char]0x8F2F)"
for ($try = 0; $try -lt 3; $try++) {
    try { Invoke-Button 5 $browseLabel; break }
    catch {
        if ($try -eq 2) { throw }
        Write-Output "Hide Editor toggle failed (attempt $($try + 1)), retrying..."
        Start-Sleep -Milliseconds 800
    }
}
# The toolbar button keeps the focus rectangle - click preview whitespace so the
# screenshot shows a clean toolbar.
$r = New-Object RW+RECT
[void][RW]::GetWindowRect((Get-MainH), [ref]$r)
$cx = [int](($r.Left + $r.Right) / 2); $cy = [int]($r.Bottom - 60)
[System.Windows.Forms.Cursor]::Position = [System.Drawing.Point]::new($cx, $cy)
Start-Sleep -Milliseconds 30
[RW]::mouse_event(2,0,0,0,0); Start-Sleep -Milliseconds 60; [RW]::mouse_event(4,0,0,0,0)
Start-Sleep -Milliseconds 500
Shot-Window (Join-Path $root "art\readme_browse_zh.png")

if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
Write-Output "done"
