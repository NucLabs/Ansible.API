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
