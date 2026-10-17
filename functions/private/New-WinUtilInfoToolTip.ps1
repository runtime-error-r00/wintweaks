function New-WinUtilInfoToolTip {
    <#
    .SYNOPSIS
        Builds what the info icon next to a tweak or feature shows on hover

    .DESCRIPTION
        A title, the plain-language description from the config and, when the entry has one, its
        risk rating in the matching colour. Creates WPF elements, so it must run on the interface
        thread.

    .PARAMETER Title
        The entry's Content, as shown next to its checkbox.

    .PARAMETER Description
        The entry's description from the config JSON. May be empty.

    .PARAMETER Risk
        low, medium or high. Entries without a rating omit it.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [string]$Description,

        [string]$Risk
    )

    $panel = New-Object Windows.Controls.StackPanel
    $panel.Margin = "4"

    # The window's implicit TextBlock style paints a label colour and background, which would
    # show as dark boxes on the tooltip, so colour and background are set explicitly
    $titleBlock = New-Object Windows.Controls.TextBlock
    $titleBlock.Text = $Title
    $titleBlock.FontWeight = [Windows.FontWeights]::SemiBold
    $titleBlock.TextWrapping = "Wrap"
    $titleBlock.Background = [Windows.Media.Brushes]::Transparent
    $titleBlock.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, "LabelboxForegroundColor")
    $panel.Children.Add($titleBlock) | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($Description)) {
        $descriptionBlock = New-Object Windows.Controls.TextBlock
        $descriptionBlock.Text = $Description
        $descriptionBlock.TextWrapping = "Wrap"
        $descriptionBlock.Margin = "0,4,0,0"
        $descriptionBlock.Background = [Windows.Media.Brushes]::Transparent
        $descriptionBlock.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, "MainForegroundColor")
        $panel.Children.Add($descriptionBlock) | Out-Null
    }

    $riskLabels = @{
        low    = @{ Resource = "RiskLowColor"; Text = "Low risk: safe for most PCs." }
        medium = @{ Resource = "RiskMediumColor"; Text = "Medium risk: read the side effects above." }
        high   = @{ Resource = "RiskHighColor"; Text = "High risk: only if you know you need it." }
    }

    if (-not [string]::IsNullOrWhiteSpace($Risk) -and $riskLabels.ContainsKey($Risk.ToLowerInvariant())) {
        $riskLabel = $riskLabels[$Risk.ToLowerInvariant()]
        $riskBlock = New-Object Windows.Controls.TextBlock
        $riskBlock.Text = "$([char]0x25CF) $($riskLabel.Text)"
        $riskBlock.TextWrapping = "Wrap"
        $riskBlock.Margin = "0,6,0,0"
        $riskBlock.FontWeight = [Windows.FontWeights]::SemiBold
        $riskBlock.Background = [Windows.Media.Brushes]::Transparent
        $riskBlock.SetResourceReference([Windows.Controls.TextBlock]::ForegroundProperty, $riskLabel.Resource)
        $panel.Children.Add($riskBlock) | Out-Null
    }

    return $panel
}
