function ConvertTo-AAPPascalCase {
    <#
    .SYNOPSIS
        Converts a snake_case string to PascalCase.
    .EXAMPLE
        ConvertTo-AAPPascalCase -Value 'target_host'
        # Returns: TargetHost
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    ($Value -split '_' | ForEach-Object {
        if ($_.Length -gt 0) {
            $_.Substring(0, 1).ToUpper() + $_.Substring(1).ToLower()
        }
    }) -join ''
}
