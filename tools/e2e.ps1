param([string]$Exe = "src\SlimMD\bin\Release\net9.0-windows\SlimMD.exe")

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
public class W {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
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

function Get-Target {
    Get-Process -Name SlimMD -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
}

# Once a dropdown menu has been opened, Process.MainWindowHandle starts returning
# the menu's SysShadow window instead of the main form - cache the real handle.
$script:mainH = [IntPtr]::Zero
function Get-MainH {
    if ($script:mainH -ne [IntPtr]::Zero) { return $script:mainH }
    $proc = Get-Target
    if ($proc) { return $proc.MainWindowHandle }
    return [IntPtr]::Zero
}

function Set-Topmost([bool]$on) {
    $h = Get-MainH
    if (-not $h) { return }
    $flag = if ($on) { [W]::TOPMOST } else { [W]::NOTOPMOST }
    [W]::SetWindowPos($h, $flag, 0, 0, 0, 0, 0x1 -bor 0x40) | Out-Null
}

function Shot([string]$file) {
    $proc = Get-Target
    $h = Get-MainH
    if (-not $proc -or -not $h) { Write-Output "!! window missing for $file"; return $false }
    [W]::ShowWindow($h, 9) | Out-Null
    [W]::SetWindowPos($h, [W]::TOPMOST, 0, 0, 0, 0, 0x1 -bor 0x40) | Out-Null
    [W]::SetForegroundWindow($h) | Out-Null
    Start-Sleep -Milliseconds 700
    $r = New-Object W+RECT
    [W]::GetWindowRect($h, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output "-> $file ($w x $ht)"
    return $true
}

# Capture an arbitrary window (e.g. a modal dialog) without touching focus.
function Shot-Hwnd([IntPtr]$h, [string]$file) {
    if ($h -eq [IntPtr]::Zero) { return $false }
    $r = New-Object W+RECT
    [W]::GetWindowRect($h, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    if ($w -le 0 -or $ht -le 0) { return $false }
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output "-> $file ($w x $ht)"
    return $true
}

# Capture an element's screen rectangle (dialogs are easier to grab this way than
# through their HWND, and it doubles as a visibility proof).
function Shot-Element($el, [string]$file) {
    if (-not $el) { return $false }
    $r = $el.Current.BoundingRectangle
    if ($r.Width -le 0 -or $r.Height -le 0) { return $false }
    $w = [int]$r.Width; $ht = [int]$r.Height
    $bmp = New-Object System.Drawing.Bitmap($w, $ht)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen([int]$r.X, [int]$r.Y, 0, 0, $bmp.Size)
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Output "-> $file ($w x $ht)"
    return $true
}

# Text of every element under a window (used to assert dialog content).
function Get-ElementText($el) {
    if (-not $el) { return "" }
    $names = @()
    $all = $el.FindAll([System.Windows.Automation.TreeScope]::Descendants,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($e in $all) { if ($e.Current.Name) { $names += $e.Current.Name } }
    if ($el.Current.Name) { $names += $el.Current.Name }
    return ($names -join " ")
}

function Get-Win {
    $h = Get-MainH
    if (-not $h) { return $null }
    return [System.Windows.Automation.AutomationElement]::FromHandle($h)
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

function Get-Editor {
    $win = Get-Win
    if (-not $win) { return $null }
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Edit)
    return $win.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $cond)
}

# Selection length of the editor via UIA TextPattern (guards the select-all-on-
# first-focus bug: showing the editor must leave the caret at position 0).
function Get-SelectionLength {
    $ed = Get-Editor
    if (-not $ed) { return -1 }
    $p = $null
    if (-not $ed.TryGetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern, [ref]$p)) { return -2 }
    $sel = $p.GetSelection()
    if (-not $sel -or $sel.Count -eq 0) { return 0 }
    return $sel[0].GetText(4096).Length
}

# Click empty whitespace in the preview (bottom-right) so the WebView document
# owns keyboard focus - this is the state where shortcuts used to be dead.
function Focus-Preview {
    $h = Get-MainH
    if (-not $h) { return $false }
    $r = New-Object W+RECT
    [W]::GetWindowRect($h, [ref]$r) | Out-Null
    $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
    Set-Topmost $true
    $x = [int]($r.Left + $w * 0.75)
    $y = [int]($r.Top + $ht * 0.92)
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 300
    $cp = [System.Windows.Forms.Cursor]::Position
    if ($cp.X -ne $x -or $cp.Y -ne $y) {
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
        Start-Sleep -Milliseconds 150
    }
    [W]::mouse_event(2, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 60
    [W]::mouse_event(4, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 500
    # SendKeys targets the foreground window - retry until the app owns it.
    for ($i = 0; $i -lt 5; $i++) {
        [W]::SetForegroundWindow($h) | Out-Null
        Start-Sleep -Milliseconds 350
        if ([W]::GetForegroundWindow() -eq $h) { return $true }
    }
    return $false
}

# Visible top-level window of our process with the Win32 common-dialog class
# (#32770) - used to detect the Open/Save file dialogs.
function Get-FileDlgHwnd {
    $script:fileDlg = [IntPtr]::Zero
    $script:fileDlgMain = Get-MainH
    $procId = [uint32]0
    [void][W]::GetWindowThreadProcessId($script:fileDlgMain, [ref]$procId)
    $script:fileDlgPid = $procId
    $cb = [W+EnumProc]{
        param($h, $l)
        $p2 = [uint32]0
        [void][W]::GetWindowThreadProcessId($h, [ref]$p2)
        if ($p2 -eq $script:fileDlgPid -and $h -ne $script:fileDlgMain -and [W]::IsWindowVisible($h)) {
            if ([W]::WinClass($h) -eq "#32770") { $script:fileDlg = $h }
        }
        return $true
    }
    [void][W]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:fileDlg
}

# UIA Invoke if available, otherwise a real mouse click at the element centre.
function Activate-Element($el) {
    if (-not $el) { return $false }
    $pattern = $null
    if ($el.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        $pattern.Invoke(); return $true
    }
    if ($el.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$pattern)) {
        $pattern.Expand(); return $true
    }
    $r = $el.Current.BoundingRectangle
    if ($r.Width -le 0 -or $r.Height -le 0) { return $false }
    $x = [int]($r.X + $r.Width / 2)
    $y = [int]($r.Y + $r.Height / 2)
    Set-Topmost $true
    Move-Cursor $x $y
    [W]::mouse_event(2, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 60
    [W]::mouse_event(4, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 400
    return $true
}

# Position the cursor and verify in a tight loop - the physical mouse races
# synthetic moves, so never sleep long between asserting and clicking.
function Move-Cursor([int]$x, [int]$y) {
    for ($i = 0; $i -lt 10; $i++) {
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
        Start-Sleep -Milliseconds 30
        $cp = [System.Windows.Forms.Cursor]::Position
        if ($cp.X -eq $x -and $cp.Y -eq $y) { return $true }
    }
    # could not stabilise - click anyway at the last position
    return $false
}

# Always a real mouse click at the element centre. Needed for controls that open a
# modal dialog: UIA InvokePattern blocks until that dialog closes (and then times out).
function Click-Element($el) {
    if (-not $el) { return $false }
    $r = $el.Current.BoundingRectangle
    if ($r.Width -le 0 -or $r.Height -le 0) { return $false }
    $x = [int]($r.X + $r.Width / 2)
    $y = [int]($r.Y + $r.Height / 2)
    Set-Topmost $true
    Move-Cursor $x $y | Out-Null
    [W]::mouse_event(2, 0, 0, 0, 0)
    # re-assert between down and up: a drag from a racing mouse would miss anyway
    $cp = [System.Windows.Forms.Cursor]::Position
    if ($cp.X -ne $x -or $cp.Y -ne $y) {
        [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
        Start-Sleep -Milliseconds 30
    }
    [W]::mouse_event(4, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 500
    return $true
}

function Find-ByName([string]$name) {
    $win = Get-Win
    if (-not $win) { return $null }
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    return $win.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $cond)
}

# Menus pop up in a separate top-level window - search the desktop too.
function Find-Anywhere([string]$name) {
    $el = Find-ByName $name
    if ($el) { return $el }
    $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)
    $el = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    if (-not $el) { $el = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond) }
    return $el
}

# HWND of the app's modal dialog: a visible top-level window of the same process,
# WindowsForms class, matching the expected title. Window-based (not UIA name search)
# so the About button's tooltip - whose text is identical to the dialog title in both
# languages - cannot produce a false hit.
$script:dlgH = [IntPtr]::Zero
function Get-DialogHwnd([string]$title, [IntPtr]$main) {
    $script:dlgH = [IntPtr]::Zero
    $script:dlgTitle = $title
    $script:dlgMain = $main
    $procId = [uint32]0
    [void][W]::GetWindowThreadProcessId($main, [ref]$procId)
    $script:dlgProc = $procId
    $cb = [W+EnumProc]{
        param($h, $l)
        $p2 = [uint32]0
        [void][W]::GetWindowThreadProcessId($h, [ref]$p2)
        if ($p2 -eq $script:dlgProc -and $h -ne $script:dlgMain -and [W]::IsWindowVisible($h)) {
            if ([W]::WinClass($h) -like "WindowsForms10*" -and [W]::WinText($h) -eq $script:dlgTitle) {
                $script:dlgH = $h
            }
        }
        return $true
    }
    [void][W]::EnumWindows($cb, [IntPtr]::Zero)
    return $script:dlgH
}

# Open the About dialog (real mouse click - UIA Invoke would block until the modal
# dialog closes), assert its content, screenshot it, then close it again.
function Check-About([string]$title, [string]$shot, [string[]]$needles) {
    $btns = Get-ToolbarButtons
    if ($btns.Count -lt 8) { Report "about dialog opens ($title)" $false "buttons=$($btns.Count)"; return }

    # A TOPMOST owner hides its own (non-topmost) modal dialog - undo that first.
    Set-Topmost $false
    Start-Sleep -Milliseconds 300

    # Synthetic clicks race the physical mouse - retry up to 3x.
    $dh = [IntPtr]::Zero
    for ($attempt = 1; $attempt -le 3 -and $dh -eq [IntPtr]::Zero; $attempt++) {
        Click-Element $btns[7] | Out-Null
        Start-Sleep -Milliseconds 1300
        $dh = Get-DialogHwnd $title (Get-MainH)
    }
    Report "about dialog opens ($title)" ($dh -ne [IntPtr]::Zero)
    if ($dh -eq [IntPtr]::Zero) { return }

    $win = [System.Windows.Automation.AutomationElement]::FromHandle($dh)
    $text = Get-ElementText $win
    foreach ($n in $needles) {
        Report "about content has '$n'" ($text -like "*$n*")
    }

    # focus the dialog first: it must be the foreground window for SendKeys,
    # and it guarantees the capture shows the dialog rather than the owner behind it.
    # Demote the (still TOPMOST) owner first, otherwise it covers its own dialog.
    $mh = Get-MainH
    [W]::SetWindowPos($mh, [W]::NOTOPMOST, 0, 0, 0, 0, 0x1 -bor 0x40) | Out-Null
    [W]::SetForegroundWindow($dh) | Out-Null
    Start-Sleep -Milliseconds 500
    Shot-Element $win $shot | Out-Null

    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Milliseconds 1000
    $gone = -not [W]::IsWindow($dh)
    Report "about dialog closes ($title)" $gone
    if (-not $gone) {
        [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
        Start-Sleep -Milliseconds 800
        Report "about dialog closes on Escape" (-not [W]::IsWindow($dh))
    }
}

# ---------------------------------------------------------------- scenario

$zhEditHide = "$([char]0x96B1)$([char]0x85CF)$([char]0x7DE8)$([char]0x8F2F)$([char]0x5340)"   # 隱藏編輯區
$zhLang     = "$([char]0x8A9E)$([char]0x8A00)"                                                # 語言
$zhItem     = "$([char]0x4E2D)$([char]0x6587)"                                                # 中文
$zhEdit     = "$([char]0x7DE8)$([char]0x8F2F)"                                                # 編輯
$zhExport   = "$([char]0x532F)$([char]0x51FA)"                                                # 匯出
$zhAbout    = "$([char]0x95DC)$([char]0x65BC) SlimMD"                                        # 關於 SlimMD
$zhVersion  = "$([char]0x7248)$([char]0x672C)"                                               # 版本
$zhFeatures = "$([char]0x529F)$([char]0x80FD)"                                               # 功能
$zhPdf      = "$([char]0x532F)$([char]0x51FA)$([char]0x70BA) PDF..."                          # 匯出為 PDF...
$zhHtml     = "$([char]0x532F)$([char]0x51FA)$([char]0x70BA) HTML..."                         # 匯出為 HTML...

# fresh settings -> English default UI
Remove-Item "$env:LOCALAPPDATA\SlimMD\settings.json" -ErrorAction SilentlyContinue
$testFile = Join-Path $root "testdata\e2e_test.md"
Copy-Item (Join-Path $root "testdata\demo.md") $testFile -Force

$p = Start-Process (Join-Path $root $Exe) -ArgumentList "`"$testFile`"" -PassThru
Start-Sleep -Seconds 6
if ($p.HasExited) { Report "app starts" $false "process exited early"; exit 1 }
$script:mainH = $p.MainWindowHandle
Report "app starts" $true

Shot (Join-Path $root "art\e2e_1_browse_en.png") | Out-Null

# --- toggle editor (button index 5; Export occupies index 4) ---
$btns = Get-ToolbarButtons
Report "toolbar has 8 buttons" ($btns.Count -eq 8) "count=$($btns.Count)"
if ($btns.Count -ge 7) {
    Report "toggle before click shows Edit" ($btns[5].Current.Name -eq "Edit") "name='$($btns[5].Current.Name)'"
    Activate-Element $btns[5] | Out-Null
    Start-Sleep -Milliseconds 1600
    Shot (Join-Path $root "art\e2e_2_split_en.png") | Out-Null
    $btns2 = Get-ToolbarButtons
    Report "toggle shows Hide Editor after click" ($btns2[5].Current.Name -eq "Hide Editor") "name='$($btns2[5].Current.Name)'"

    # Regression: showing the editor used to select all of its text on first focus.
    $selLen = Get-SelectionLength
    Report "editor has no select-all after showing (sel=0)" ($selLen -eq 0) "selLen=$selLen"
}

# --- paste markdown into the editor and verify live rendering ---
$editor = Get-Editor
if ($editor) {
    Activate-Element $editor | Out-Null
    Start-Sleep -Milliseconds 500
    $fg = [W]::GetForegroundWindow()
    $isForeground = $fg -eq (Get-MainH)
    Report "editor has focus" $isForeground "fg=$fg"
    if ($isForeground) {
        $marker = @'

# Pasted Heading

Live **update** test with `code` and a table:

| a | b |
|---|---|
| 1 | 2 |

'@
        Set-Clipboard -Value $marker
        [System.Windows.Forms.SendKeys]::SendWait("^{END}")
        Start-Sleep -Milliseconds 200
        [System.Windows.Forms.SendKeys]::SendWait("^v")
        Start-Sleep -Milliseconds 1500
        Shot (Join-Path $root "art\e2e_3_pasted_en.png") | Out-Null

        [System.Windows.Forms.SendKeys]::SendWait("^s")
        Start-Sleep -Milliseconds 900
        $saved = Get-Content $testFile -Raw -ErrorAction SilentlyContinue
        Report "Ctrl+S writes file" ($saved -and $saved.Contains("Pasted Heading")) "len=$($saved.Length)"
    }
} else {
    Report "editor element exists" $false
}

# --- shortcuts while the preview (browse view) has focus: Chromium used to
# swallow them, now preview.js re-posts them as {type:"shortcut"} messages ---
# back to browse first
$btnsB = Get-ToolbarButtons
if ($btnsB.Count -ge 6 -and $btnsB[5].Current.Name -eq "Hide Editor") {
    Activate-Element $btnsB[5] | Out-Null
    Start-Sleep -Milliseconds 1400
}

if (Focus-Preview) {
    [System.Windows.Forms.SendKeys]::SendWait("{F9}")
    Start-Sleep -Milliseconds 1500
    $b = Get-ToolbarButtons
    Report "F9 from browse mode toggles editor" ($b.Count -ge 6 -and $b[5].Current.Name -eq "Hide Editor") "name='$($b[5].Current.Name)'"
} else {
    Report "F9 from browse mode toggles editor" $false "app not foreground"
}

if (Focus-Preview) {
    [System.Windows.Forms.SendKeys]::SendWait("^e")
    Start-Sleep -Milliseconds 1500
    $b = Get-ToolbarButtons
    Report "Ctrl+E from preview toggles editor back" ($b.Count -ge 6 -and $b[5].Current.Name -eq "Edit") "name='$($b[5].Current.Name)'"
} else {
    Report "Ctrl+E from preview toggles editor back" $false "app not foreground"
}

if (Focus-Preview) {
    [System.Windows.Forms.SendKeys]::SendWait("^o")
    Start-Sleep -Milliseconds 1800
    $dh = Get-FileDlgHwnd
    Report "Ctrl+O from browse mode opens file dialog" ($dh -ne [IntPtr]::Zero)
    if ($dh -ne [IntPtr]::Zero) {
        [W]::SetForegroundWindow($dh) | Out-Null
        Start-Sleep -Milliseconds 400
        [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
        Start-Sleep -Milliseconds 900
        Report "file dialog closed by Escape" (-not [W]::IsWindow($dh))
    }
} else {
    Report "Ctrl+O from browse mode opens file dialog" $false "app not foreground"
}

# restore split view: the checks below expect the editor to be visible again
$btnsR = Get-ToolbarButtons
if ($btnsR.Count -ge 6 -and $btnsR[5].Current.Name -eq "Edit") {
    Activate-Element $btnsR[5] | Out-Null
    Start-Sleep -Milliseconds 1400
    $btnsR2 = Get-ToolbarButtons
    Report "state restored to split view" ($btnsR2.Count -ge 6 -and $btnsR2[5].Current.Name -eq "Hide Editor") "name='$($btnsR2[5].Current.Name)'"
}

# --- export menu opens (button index 4) ---
$btnsX = Get-ToolbarButtons
if ($btnsX.Count -ge 7) {
    Report "export button label" ($btnsX[4].Current.Name -eq "Export") "name='$($btnsX[4].Current.Name)'"
    Activate-Element $btnsX[4] | Out-Null
    Start-Sleep -Milliseconds 900
    $pdfEn = Find-Anywhere "Export as PDF..."
    $htmlEn = Find-Anywhere "Export as HTML..."
    Report "export menu opens, PDF/HTML items found" ($null -ne $pdfEn -and $null -ne $htmlEn) "pdf=$($null -ne $pdfEn) html=$($null -ne $htmlEn)"
    # close the menu without invoking an item (that would open a modal dialog)
    [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
    Start-Sleep -Milliseconds 600
    $stillOpen = Find-Anywhere "Export as PDF..."
    Report "export menu closed by Escape" ($null -eq $stillOpen)
} else {
    Report "export menu opens, PDF/HTML items found" $false "buttons=$($btnsX.Count)"
}

# --- About dialog (button index 7) ---
Check-About "About SlimMD" (Join-Path $root "art\e2e_about_en.png") @("1.0.3", "Caron Yang", "Export to PDF", "GitHub Repository")

# --- switch language to Chinese (button index 6) ---
$btns3 = Get-ToolbarButtons
if ($btns3.Count -ge 7) {
    Activate-Element $btns3[6] | Out-Null
    Start-Sleep -Milliseconds 900
    $item = Find-ByName $zhItem
    if (-not $item) {
        # popup may be a separate top-level window
        $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, $zhItem)
        $item = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
        if (-not $item) { $item = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond) }
    }
    Report "language menu opens, 中文 item found" ($null -ne $item)
    if ($item) {
        Activate-Element $item | Out-Null
        Start-Sleep -Milliseconds 1300
        $btns4 = Get-ToolbarButtons
        Report "language switched to Chinese" ($btns4.Count -ge 7 -and $btns4[0].Current.Name -ne "New") "name='$($btns4[0].Current.Name)' lang='$($btns4[6].Current.Name)'"
        Shot (Join-Path $root "art\e2e_4_split_zh.png") | Out-Null
    }
}

# --- export menu localised (button index 4) ---
$btnsX2 = Get-ToolbarButtons
if ($btnsX2.Count -ge 7) {
    Report "export button label localised" ($btnsX2[4].Current.Name -eq $zhExport) "name='$($btnsX2[4].Current.Name)'"
    Activate-Element $btnsX2[4] | Out-Null
    Start-Sleep -Milliseconds 900
    $pdfZh = Find-Anywhere $zhPdf
    $htmlZh = Find-Anywhere $zhHtml
    Report "export menu localised (匯出為 PDF/HTML)" ($null -ne $pdfZh -and $null -ne $htmlZh) "pdf=$($null -ne $pdfZh) html=$($null -ne $htmlZh)"
    [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
    Start-Sleep -Milliseconds 600
}

# --- hide editor in Chinese UI ---
$btns5 = Get-ToolbarButtons
if ($btns5.Count -ge 7) {
    Report "toggle label localised" ($btns5[5].Current.Name -eq $zhEditHide) "name='$($btns5[5].Current.Name)'"
    Activate-Element $btns5[5] | Out-Null
    Start-Sleep -Milliseconds 1400
    Shot (Join-Path $root "art\e2e_5_browse_zh.png") | Out-Null
    $btns6 = Get-ToolbarButtons
    Report "editor hidden again (label back to 編輯)" ($btns6[5].Current.Name -eq $zhEdit) "name='$($btns6[5].Current.Name)'"
}

# --- About dialog localised ---
Check-About $zhAbout (Join-Path $root "art\e2e_about_zh.png") @("1.0.3", "Caron Yang", $zhVersion, $zhFeatures)

# --- settings persisted ---
$settingsPath = "$env:LOCALAPPDATA\SlimMD\settings.json"
$hasZh = (Test-Path $settingsPath) -and ((Get-Content $settingsPath -Raw) -match '"language"\s*:\s*"zh"')
Report "language preference persisted" $hasZh

# --- close ---
$proc = Get-Target
if ($proc) { $proc.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 2; if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force } }

$failed = @($results | Where-Object { -not $_.OK })
Write-Output ""
Write-Output ("total={0} passed={1} failed={2}" -f $results.Count, ($results.Count - $failed.Count), $failed.Count)
if ($failed.Count) { exit 1 }
