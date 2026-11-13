Add-Type -AssemblyName System.Windows.Forms

$path = Join-Path (Split-Path $PSScriptRoot -Parent) "testdata\e2e_test.md"
$bytes = [System.IO.File]::ReadAllBytes($path)
$crlf = 0; $lf = 0
for ($i = 0; $i -lt $bytes.Length; $i++) {
    if ($bytes[$i] -eq 10) { $lf++; if ($i -gt 0 -and $bytes[$i-1] -eq 13) { $crlf++ } }
}
Write-Output "file: len=$($bytes.Length) lf=$lf crlf=$crlf"

$text = [System.IO.File]::ReadAllText($path)
$t = New-Object System.Windows.Forms.TextBox
$t.Multiline = $true
$t.Text = $text
Write-Output "TextBox: Lines=$($t.Lines.Count) textLen=$($t.Text.Length)"
$last = $t.Lines.Count - 3
for ($i = [Math]::Max(0, $last); $i -lt $t.Lines.Count; $i++) {
    $l = $t.Lines[$i]
    if ($l.Length -gt 60) { $l = $l.Substring(0, 60) + "..." }
    Write-Output "  [$i] $l"
}
