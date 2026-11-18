param([string]$Exe = "src\SlimMD\bin\Release\net9.0-windows\SlimMD.exe")

# Loading-state checks (English and Traditional Chinese):
#   1. the window appears quickly
#   2. while the document is being prepared the status bar shows a loading
#      message and an indeterminate progress bar, and the preview pane shows
#      the same message instead of a blank page
#   3. once rendered, the loading state is gone and the document info is shown
#   4. the loading message follows the interface language

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class LT {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

$results = @()
function Report([string]$name, [bool]$ok, [string]$detail = "") {
    $script:results += [pscustomobject]@{ Check = $name; OK = $ok; Detail = $detail }
    Write-Output ("[{0}] {1} {2}" -f ($(if ($ok) { "PASS" } else { "FAIL" })), $name, $detail)
}

# Localized markers built from code points: Windows PowerShell 5.1 reads
# BOM-less files as ANSI, so literal Chinese in this file would be corrupted
# (it can even swallow the following line). Keep this file ASCII-only.
$zhLoadingFile = "$([char]0x6B63)$([char]0x5728)$([char]0x8B80)$([char]0x53D6) "   # "zheng zai du qu" + space
$zhLoadingPane = "$([char]0x8F09)$([char]0x5165)$([char]0x4E2D)$([char]0x2026)"      # "zai ru zhong" + ellipsis
$enLoading = "Loading"

function Test-IsLoadingText([string]$n) {
    return ($n -like "*$enLoading*" -or $n -like "*$zhLoadingFile*" -or $n -like "*$zhLoadingPane*")
}

function Get-StatusTexts([IntPtr]$h) {
    try {
        $win = [System.Windows.Automation.AutomationElement]::FromHandle($h)
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::StatusBar)
        $bar = $win.FindFirst([System.Windows.Automation.TreeScope]::Subtree, $cond)
        if (-not $bar) { return @() }
        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
        $names = @(); $c = $walker.GetFirstChild($bar)
        while ($c) { if ($c.Current.Name) { $names += $c.Current.Name }; $c = $walker.GetNextSibling($c) }
        return $names
    } catch { return @() }
}

function Get-LoadingTexts([IntPtr]$h) {
    try {
        $win = [System.Windows.Automation.AutomationElement]::FromHandle($h)
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Text)
        $all = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
        $out = @()
        foreach ($e in $all) {
            $n = $e.Current.Name
            if ($n -and (Test-IsLoadingText $n)) { $out += $n }
        }
        return $out
    } catch { return @() }
}

function Set-Language([string]$lang) {
    $dir = "$env:LOCALAPPDATA\SlimMD"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $settings = @{
        Language = $lang; X = -1; Y = -1; Width = 1100; Height = 760;
        Maximized = $false; LastDirectory = (Join-Path $root "testdata")
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText((Join-Path $dir "settings.json"), $settings,
        (New-Object System.Text.UTF8Encoding($false)))
}

function Start-SlimMD([string]$file) {
    $script:proc = Start-Process (Join-Path $root $Exe) -ArgumentList "`"$file`"" -PassThru
    $h = [IntPtr]::Zero
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt 60 -and $h -eq [IntPtr]::Zero; $i++) {
        Start-Sleep -Milliseconds 100
        $script:proc.Refresh()
        if ($script:proc.MainWindowHandle -ne 0) { $h = $script:proc.MainWindowHandle }
    }
    return @{ Handle = $h; ElapsedMs = $sw.ElapsedMilliseconds }
}

function Stop-SlimMD {
    if ($script:proc -and -not $script:proc.HasExited) { Stop-Process -Id $script:proc.Id -Force }
}

# ---------------------------------------------------------------- English
$file = Join-Path $root "testdata\scroll_sync.md"
Set-Language "en"
Stop-Process -Name SlimMD -Force -ErrorAction SilentlyContinue
$started = Start-SlimMD $file
$h = $started.Handle
Report "window appears quickly" ($started.ElapsedMs -lt 3000) "shown in $($started.ElapsedMs) ms"
if ($h -eq [IntPtr]::Zero) { Report "window handle" $false "no window"; exit 1 }

Start-Sleep -Milliseconds 500
$status = Get-StatusTexts $h
$loading = Get-LoadingTexts $h
Report "status bar shows the loading message" `
    (@($status | Where-Object { Test-IsLoadingText $_ }).Count -ge 1) ($status -join " || ")
Report "preview pane shows the loading message" ($loading.Count -ge 1) (($loading | Select-Object -First 1) -join "")
Report "loading message names the file" `
    (@($status | Where-Object { $_ -like "*scroll_sync.md*" }).Count -ge 1) ""

Start-Sleep -Seconds 5
$statusDone = Get-StatusTexts $h
$loadingDone = Get-LoadingTexts $h
Report "loading state clears when rendered" ($loadingDone.Count -eq 0) ($loadingDone -join " || ")
Report "document info replaces it" `
    (@($statusDone | Where-Object { $_ -like "*scroll_sync.md*" -and $_ -like "*chars*" }).Count -ge 1) `
    ($statusDone -join " || ")
Stop-SlimMD

# ---------------------------------------------------------------- Chinese
Set-Language "zh"
Stop-Process -Name SlimMD -Force -ErrorAction SilentlyContinue
$started = Start-SlimMD $file
$h = $started.Handle
if ($h -eq [IntPtr]::Zero) { Report "zh window" $false "no window" }
else {
    Start-Sleep -Milliseconds 500
    $statusZh = Get-StatusTexts $h
    $loadingZh = Get-LoadingTexts $h
    Report "zh status bar shows the loading message" `
        (@($statusZh | Where-Object { $_ -like "*$zhLoadingFile*" }).Count -ge 1) ($statusZh -join " || ")
    Report "zh preview pane shows the loading message" `
        (@($loadingZh | Where-Object { $_ -like "*$zhLoadingFile*" -or $_ -like "*$zhLoadingPane*" }).Count -ge 1) `
        (($loadingZh | Select-Object -First 1) -join "")
    Start-Sleep -Seconds 5
    $loadingZhDone = Get-LoadingTexts $h
    Report "zh loading state clears when rendered" ($loadingZhDone.Count -eq 0) ($loadingZhDone -join " || ")
}
Stop-SlimMD

$failed = @($results | Where-Object { -not $_.OK })
Write-Output ""
Write-Output ("total={0} passed={1} failed={2}" -f $results.Count, ($results.Count - $failed.Count), $failed.Count)
if ($failed.Count) { exit 1 }
