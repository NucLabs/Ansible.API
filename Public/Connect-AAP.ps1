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

    $certParam = @{}
    if ($SkipCertificateCheck) {
        $certParam['SkipCertificateCheck'] = $true
    }

    # Try Basic Auth first (works on most AWX instances)
    $authBytes = [System.Text.Encoding]::UTF8.GetBytes(
        "$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"
    )
    $authHeader = "Basic $([Convert]::ToBase64String($authBytes))"

    $response = $null
    try {
        $response = Invoke-RestMethod -Method POST -Uri $tokenUrl `
            -Headers @{ Authorization = $authHeader } `
            -ContentType 'application/json' @certParam
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -in 401, 403) {
            Write-Verbose 'Basic auth failed, falling back to session-based login via /api/login/'
        } else {
            throw
        }
    }

    # Fallback: session-based login (required by some AAP/Controller instances)
    if (-not $response) {
        $session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()

        # GET /api/login/ to obtain the CSRF cookie
        Invoke-WebRequest -Uri "$baseUrl/api/login/" -SessionVariable 'session' `
            -UseBasicParsing @certParam | Out-Null

        $csrfToken = $session.Cookies.GetCookies("$baseUrl")['csrftoken'].Value

        # POST /api/login/ with form data to establish an authenticated session
        $loginBody = @{
            username            = $Credential.UserName
            password            = $Credential.GetNetworkCredential().Password
            csrfmiddlewaretoken = $csrfToken
            next                = '/api/'
        }
        $loginHeaders = @{
            Referer = "$baseUrl/api/login/"
        }

        Invoke-WebRequest -Uri "$baseUrl/api/login/" -Method POST `
            -Body $loginBody -Headers $loginHeaders `
            -WebSession $session -UseBasicParsing `
            -ContentType 'application/x-www-form-urlencoded' @certParam | Out-Null

        # Now create the token using the authenticated session
        $csrfToken = $session.Cookies.GetCookies("$baseUrl")['csrftoken'].Value
        $tokenHeaders = @{
            Referer      = "$baseUrl/api/v2/tokens/"
            'X-CSRFToken' = $csrfToken
        }

        $response = Invoke-RestMethod -Method POST -Uri $tokenUrl `
            -Headers $tokenHeaders -WebSession $session `
            -ContentType 'application/json' @certParam
    }

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
