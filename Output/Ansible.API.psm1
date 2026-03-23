#
# Module: Ansible.API
# Built:  2026-03-23 13:56:33
#

#region Get-AAPApiUrl.ps1
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

#endregion

#region Invoke-AAPRestMethod.ps1
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
        Headers     = @{ Authorization = "Bearer $($Script:AAPSession.Token)" }
        ContentType = $ContentType
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

#endregion

#region Connect-AAP.ps1
function Connect-AAP {
    <#
    .SYNOPSIS
        Connects to an AAP/AWX instance by obtaining an OAuth2 token.
    .DESCRIPTION
        Authenticates against the AAP/AWX API using basic auth credentials
        and stores the resulting OAuth2 token for subsequent API calls.
    .PARAMETER Url
        The base URL of the AAP/AWX server (e.g. http://localhost:32000).
    .PARAMETER Credential
        A PSCredential object containing the username and password.
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation (useful for self-signed certs).
    .EXAMPLE
        Connect-AAP -Url http://localhost:32000 -Credential (Get-Credential)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [PSCredential]$Credential,

        [Parameter()]
        [switch]$SkipCertificateCheck
    )

    $baseUrl = $Url.TrimEnd('/')
    $tokenUrl = "$baseUrl/api/v2/tokens/"

    $authBytes = [System.Text.Encoding]::UTF8.GetBytes(
        "$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"
    )
    $authHeader = "Basic $([Convert]::ToBase64String($authBytes))"

    $params = @{
        Method      = 'POST'
        Uri         = $tokenUrl
        Headers     = @{ Authorization = $authHeader }
        ContentType = 'application/json'
    }

    if ($SkipCertificateCheck) {
        $params['SkipCertificateCheck'] = $true
    }

    $response = Invoke-RestMethod @params

    $Script:AAPSession = @{
        BaseUrl              = $baseUrl
        Token                = $response.token
        TokenId              = $response.id
        SkipCertificateCheck = [bool]$SkipCertificateCheck
    }

    [PSCustomObject]@{
        PSTypeName = 'AAP.Connection'
        Server     = $baseUrl
        Username   = $Credential.UserName
        TokenId    = $response.id
    }
}

#endregion

#region Disconnect-AAP.ps1
function Disconnect-AAP {
    <#
    .SYNOPSIS
        Disconnects from AAP/AWX by revoking the current OAuth2 token.
    .DESCRIPTION
        Sends a DELETE request to revoke the token on the server, then clears
        the local session state.
    .EXAMPLE
        Disconnect-AAP
    #>
    [CmdletBinding()]
    param()

    if (-not $Script:AAPSession) {
        Write-Warning 'No active AAP session to disconnect.'
        return
    }

    $tokenId = $Script:AAPSession.TokenId
    try {
        Invoke-AAPRestMethod -Method DELETE -Path "/api/v2/tokens/$tokenId/"
    }
    catch {
        Write-Warning "Failed to revoke token on server: $_"
    }

    $Script:AAPSession = $null
    Write-Verbose 'Disconnected from AAP.'
}

#endregion

#region Get-AAPMe.ps1
function Get-AAPMe {
    <#
    .SYNOPSIS
        Returns the current authenticated user's information from AAP/AWX.
    .DESCRIPTION
        Calls GET /api/v2/me/ and returns the user object.
    .EXAMPLE
        Get-AAPMe
    #>
    [CmdletBinding()]
    param()

    $response = Invoke-AAPRestMethod -Method GET -Path '/api/v2/me/'

    if ($response.results) {
        $response.results
    } else {
        $response
    }
}

#endregion

