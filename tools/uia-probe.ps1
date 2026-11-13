Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$proc = Get-Process -Name SlimMD -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$win = [System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
Write-Output "window: '$($win.Current.Name)'"

$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$script:found = @()
function Walk($el, $depth) {
    if ($depth -gt 7) { return }
    $child = $walker.GetFirstChild($el)
    while ($child) {
        $ct = $child.Current.ControlType.ProgrammaticName -replace 'ControlType\.', ''
        $nm = $child.Current.Name
        $aid = $child.Current.AutomationId
        $pats = @()
        foreach ($p in @(
            [System.Windows.Automation.InvokePattern]::Pattern,
            [System.Windows.Automation.ExpandCollapsePattern]::Pattern,
            [System.Windows.Automation.LegacyIAccessiblePattern]::Pattern,
            [System.Windows.Automation.ValuePattern]::Pattern,
            [System.Windows.Automation.TogglePattern]::Pattern)) {
            $tmp = $null
            if ($child.TryGetCurrentPattern($p, [ref]$tmp)) { $pats += ($p.ProgrammaticName -replace 'Pattern\.', '') }
        }
        Write-Output ('  ' * $depth + "$ct name='$nm' id='$aid' patterns=[$($pats -join ',')]")
        Walk $child ($depth + 1)
        $child = $walker.GetNextSibling($child)
    }
}
Walk $win 1
