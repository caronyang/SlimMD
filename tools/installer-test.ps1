# Smoke-tests the shipped installer: silent install -> launch -> verify Export
# menu exists in the installed app -> silent uninstall.
$ErrorActionPreference = "Continue"
$root = 'D:\caron\99_temp\opencode\SlimMD'
$setup = Join-Path $root 'dist\SlimMD-1.0.3-Setup.exe'
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\SlimMD'
$exe = Join-Path $installDir 'SlimMD.exe'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class IW {
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int max);
    public static string Txt(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
}
"@

$fail = 0
function Check([string]$name, [bool]$ok, [string]$detail = "") {
    if (-not $ok) { $script:fail++ }
    Write-Output ("[{0}] {1} {2}" -f ($(if ($ok) { "PASS" } else { "FAIL" })), $name, $detail)
}

# Start from default settings: another test may have left the UI in Chinese.
Remove-Item (Join-Path $env:LOCALAPPDATA 'SlimMD\settings.json') -ErrorAction SilentlyContinue

Check "setup exists" (Test-Path $setup) "$([math]::Round((Get-Item $setup).Length/1MB,1)) MB"

# --- install (silent) ---
Start-Process $setup -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART","/SP-" -Wait
Start-Sleep -Seconds 2
Check "installed SlimMD.exe" (Test-Path $exe)

# --- launch installed app with a test file ---
$md = Join-Path $root 'testdata\demo.md'
$p = Start-Process $exe -ArgumentList "`"$md`"" -PassThru
Start-Sleep -Seconds 7
Check "installed app runs" (-not $p.HasExited)

$mainH = $p.MainWindowHandle
$win = [System.Windows.Automation.AutomationElement]::FromHandle($mainH)
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$child = $walker.GetFirstChild($win)
$btnNames = @()
while ($child) {
    if ($child.Current.ControlType -eq [System.Windows.Automation.ControlType]::ToolBar) {
        $b = $walker.GetFirstChild($child)
        while ($b) {
            if ($b.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) { $btnNames += $b.Current.Name }
            $b = $walker.GetNextSibling($b)
        }
    }
    $child = $walker.GetNextSibling($child)
}
Check "installed toolbar has Export" ($btnNames -contains "Export") "count=$($btnNames.Count) [$($btnNames -join ', ')]"

# --- open the export menu in the installed build ---
$btns = @()
$child = $walker.GetFirstChild($win)
while ($child) {
    if ($child.Current.ControlType -eq [System.Windows.Automation.ControlType]::ToolBar) {
        $b = $walker.GetFirstChild($child)
        while ($b) { if ($b.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) { $btns += $b }; $b = $walker.GetNextSibling($b) }
    }
    $child = $walker.GetNextSibling($child)
}
if ($btns.Count -ge 5) {
    $pat = $null
    if ($btns[4].TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$pat)) {
        [void]$pat.Expand()
        Start-Sleep -Milliseconds 900
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty, "Export as PDF...")
        $rootEl = [System.Windows.Automation.AutomationElement]::RootElement
        $item = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
        if (-not $item) { $item = $rootEl.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond) }
        Check "installed export menu opens" ($null -ne $item)
        [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
        Start-Sleep -Milliseconds 500
    } else {
        Check "installed export menu opens" $false "no ExpandCollapse pattern"
    }
}

# --- close and uninstall ---
if (-not $p.HasExited) { $p.CloseMainWindow() | Out-Null; Start-Sleep -Seconds 2 }
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }

$unins = Join-Path $installDir 'unins000.exe'
if (Test-Path $unins) {
    Start-Process $unins -ArgumentList "/VERYSILENT","/SUPPRESSMSGBOXES","/NORESTART" -Wait
    Start-Sleep -Seconds 3
}
Check "uninstalled (exe gone)" (-not (Test-Path $exe))

Write-Output ""
if ($fail) { Write-Output "FAILED=$fail"; exit 1 }
Write-Output "installer smoke test: ALL PASS"
exit 0
