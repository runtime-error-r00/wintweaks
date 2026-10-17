function Save-WinUtilCustomAppList {
    <#
    .SYNOPSIS
        Writes the current custom winget apps to custom-apps.json so the next session has them
    #>

    $wingetIds = @(
        $sync.configs.applicationsHashtable.Values |
            Where-Object { $_.custom -eq $true } |
            ForEach-Object { [string]$_.winget } |
            Sort-Object -Unique
    )

    $path = Join-Path $sync.winutildir "custom-apps.json"
    ConvertTo-Json -InputObject $wingetIds | Set-Content -LiteralPath $path -Encoding UTF8
}
