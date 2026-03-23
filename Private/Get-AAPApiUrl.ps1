function Get-AAPApiUrl {
    <#
    .SYNOPSIS
        Builds a full API URL from the stored session base URL and a relative path.
    .PARAMETER Path
        The relative API path, e.g. '/api/v2/me/'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not $Script:AAPSession) {
        throw 'Not connected to AAP. Run Connect-AAP first.'
    }

    $baseUrl = $Script:AAPSession.BaseUrl.TrimEnd('/')
    $Path = $Path.TrimStart('/')

    return "$baseUrl/$Path"
}
