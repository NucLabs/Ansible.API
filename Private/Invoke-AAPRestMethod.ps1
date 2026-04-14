function Invoke-AAPRestMethod {
    <#
    .SYNOPSIS
        Authenticated REST call wrapper for AAP/AWX API.
    .DESCRIPTION
        Reads the OAuth2 token from the module session and calls Invoke-RestMethod
        with the appropriate Authorization header.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [string]$ContentType = 'application/json'
    )

    if (-not $Script:AAPSession) {
        throw 'Not connected to AAP. Run Connect-AAP first.'
    }

    $uri = Get-AAPApiUrl -Path $Path

    $params = @{
        Method      = $Method
        Uri         = $uri
        ContentType = $ContentType
    }

    if ($Script:AAPSession.AuthMethod -eq 'Session') {
        # Session-cookie auth: use the stored WebSession and include CSRF token for mutating requests
        $params['WebSession'] = $Script:AAPSession.WebSession
        if ($Method -ne 'GET') {
            $csrfToken = $Script:AAPSession.WebSession.Cookies.GetCookies($Script:AAPSession.BaseUrl)['csrftoken'].Value
            $params['Headers'] = @{
                'X-CSRFToken' = $csrfToken
                Referer       = $uri
            }
        }
    } else {
        # Bearer token auth (BearerToken or pre-generated Token)
        $params['Headers'] = @{ Authorization = "Bearer $($Script:AAPSession.Token)" }
    }

    if ($Script:AAPSession.SkipCertificateCheck) {
        $params['SkipCertificateCheck'] = $true
    }

    if ($Body) {
        if ($Body -is [string]) {
            $params['Body'] = $Body
        } else {
            $params['Body'] = $Body | ConvertTo-Json -Depth 10
        }
    }

    Invoke-RestMethod @params
}
