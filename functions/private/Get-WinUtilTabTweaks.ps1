function Get-WinUtilTabTweaks {
    <#

    .SYNOPSIS
        Returns the tweaks.json entries shown on one page

    .DESCRIPTION
        Entries with "tab": "Advanced" belong to the Advanced page; every other entry belongs to
        the Tweaks page. Both pages share $sync.configs.tweaks, so applying, undoing and
        detecting a tweak works the same wherever it is shown.

    .PARAMETER Tab
        Tweaks or Advanced.

    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Tweaks", "Advanced")]
        [string]$Tab
    )

    $entries = [ordered]@{}
    foreach ($property in $sync.configs.tweaks.PSObject.Properties) {
        $entryTab = if ($property.Value.tab) { $property.Value.tab } else { "Tweaks" }
        if ($entryTab -eq $Tab) {
            $entries[$property.Name] = $property.Value
        }
    }

    [pscustomobject]$entries
}
