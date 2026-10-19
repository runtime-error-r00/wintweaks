function Get-WinUtilDisplayAdapterKey {
    <#

    .SYNOPSIS
        Returns the driver registry keys of the display adapters from one vendor

    .DESCRIPTION
        Each display adapter has a numbered key (0000, 0001...) under the display device class.
        The number depends on install order, so the vendor is read from MatchingDeviceId instead
        of assuming the graphics card is 0000.

    .PARAMETER Vendor
        NVIDIA, AMD or Intel.

    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet("NVIDIA", "AMD", "Intel")]
        [string]$Vendor
    )

    $vendorId = @{ NVIDIA = "ven_10de"; AMD = "ven_1002"; Intel = "ven_8086" }[$Vendor]
    $classPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"

    Get-ChildItem -Path $classPath -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^\d{4}$' } |
        Where-Object { [string]$_.GetValue("MatchingDeviceId") -match $vendorId } |
        ForEach-Object { "$classPath\$($_.PSChildName)" }
}
