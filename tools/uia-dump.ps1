param([int]$Depth = 6, [int]$Max = 120)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$proc = Get-Process -Name SlimMD -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
$root = [System.Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
Write-Output "root: $($root.Current.ControlType.ProgrammaticName) '$($root.Current.Name)'"

$count = 0
function Walk($el, $depth) {
    if ($depth -gt $Depth -or $script:count -ge $Max) { return }
    $cond = [System.Windows.Automation.Condition]::TrueCondition
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $child = $walker.GetFirstChild($el)
    while ($child -and $script:count -lt $Max) {
        $ct = $child.Current.ControlType.ProgrammaticName -replace 'ControlType\.', ''
        $nm = $child.Current.Name
        $aid = $child.Current.AutomationId
        Write-Output ('  ' * $depth + "$ct name='$nm' id='$aid'")
        $script:count++
        Walk $child ($depth + 1)
        $child = $walker.GetNextSibling($child)
    }
}
Walk $root 1
