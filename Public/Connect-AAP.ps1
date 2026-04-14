function Connect-AAP {
    <#
    .SYNOPSIS
        Connects to an AAP/AWX instance.
    .DESCRIPTION
        Authenticates against the AAP/AWX API. Supports three authentication methods:
        1. Credential (default) — Creates an OAuth2 token via Basic Auth, falling back
           to session-based login for environments where Basic Auth or token creation
           is disabled (e.g. LDAP users).
        2. Token — Uses a pre-generated Personal Access Token (OAuth2 token).
    .PARAMETER Url
        The base URL of the AAP/AWX server (e.g. http://localhost:32000).
    .PARAMETER Credential
        A PSCredential object containing the username and password.
    .PARAMETER Token
        A pre-generated OAuth2 Personal Access Token string.
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation (useful for self-signed certs).
    .EXAMPLE
        Connect-AAP -Url http://localhost:32000 -Credential (Get-Credential)
    .EXAMPLE
        Connect-AAP -Url https://aap.example.com -Token 'my-personal-access-token'
    #>
    [CmdletBinding(DefaultParameterSetName = 'Credential')]
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory, ParameterSetName = 'Credential')]
        [PSCredential]$Credential,

        [Parameter(Mandatory, ParameterSetName = 'Token')]
        [string]$Token,

        [Parameter()]
        [switch]$SkipCertificateCheck
    )

    $baseUrl = $Url.TrimEnd('/')

    $certParam = @{}
    if ($SkipCertificateCheck) {
        $certParam['SkipCertificateCheck'] = $true
    }

    # --- Pre-generated token ---
    if ($PSCmdlet.ParameterSetName -eq 'Token') {
        $Script:AAPSession = @{
            BaseUrl              = $baseUrl
            Token                = $Token
            TokenId              = $null
            AuthMethod           = 'Token'
            SkipCertificateCheck = [bool]$SkipCertificateCheck
        }

        # Verify the token works
        try {
            $me = Invoke-AAPRestMethod -Method GET -Path '/api/v2/me/'
            $username = $me.results[0].username
        }
        catch {
            $Script:AAPSession = $null
            throw "Failed to verify token: $_"
        }

        return [PSCustomObject]@{
            PSTypeName = 'AAP.Connection'
            Server     = $baseUrl
            Username   = $username
            AuthMethod = 'Token'
        }
    }

    # --- Credential-based auth ---
    $tokenUrl = "$baseUrl/api/v2/tokens/"

    $authBytes = [System.Text.Encoding]::UTF8.GetBytes(
        "$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"
    )
    $authHeader = "Basic $([Convert]::ToBase64String($authBytes))"

    # Step 1: Try Basic Auth → OAuth2 token
    $response = $null
    try {
        $response = Invoke-RestMethod -Method POST -Uri $tokenUrl `
            -Headers @{ Authorization = $authHeader } `
            -ContentType 'application/json' @certParam
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $_.ErrorDetails.Message
        if ($statusCode -in 401, 403) {
            Write-Verbose 'Basic auth token creation failed, falling back to session-based login via /api/login/'
        } else {
            throw
        }
    }

    if ($response) {
        # Basic Auth → Token succeeded
        $Script:AAPSession = @{
            BaseUrl              = $baseUrl
            Token                = $response.token
            TokenId              = $response.id
            AuthMethod           = 'BearerToken'
            SkipCertificateCheck = [bool]$SkipCertificateCheck
        }

        return [PSCustomObject]@{
            PSTypeName = 'AAP.Connection'
            Server     = $baseUrl
            Username   = $Credential.UserName
            TokenId    = $response.id
            AuthMethod = 'BearerToken'
        }
    }

    # Step 2: Session-based login via /api/login/
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

    Invoke-WebRequest -Uri "$baseUrl/api/login/" -Method POST `
        -Body $loginBody `
        -Headers @{ Referer = "$baseUrl/api/login/" } `
        -WebSession $session -UseBasicParsing `
        -ContentType 'application/x-www-form-urlencoded' @certParam | Out-Null

    # Step 3: Try to create a token using the session
    $csrfToken = $session.Cookies.GetCookies("$baseUrl")['csrftoken'].Value
    $tokenCreated = $false
    try {
        $response = Invoke-RestMethod -Method POST -Uri $tokenUrl `
            -Headers @{ Referer = "$baseUrl/api/v2/tokens/"; 'X-CSRFToken' = $csrfToken } `
            -WebSession $session -ContentType 'application/json' @certParam
        $tokenCreated = $true
    }
    catch {
        # Token creation may fail for LDAP/external auth users — use session cookies instead
        Write-Verbose "Token creation failed, using session-based authentication: $_"
    }

    if ($tokenCreated) {
        $Script:AAPSession = @{
            BaseUrl              = $baseUrl
            Token                = $response.token
            TokenId              = $response.id
            AuthMethod           = 'BearerToken'
            SkipCertificateCheck = [bool]$SkipCertificateCheck
        }

        return [PSCustomObject]@{
            PSTypeName = 'AAP.Connection'
            Server     = $baseUrl
            Username   = $Credential.UserName
            TokenId    = $response.id
            AuthMethod = 'BearerToken'
        }
    }

    # Step 4: Fall back to session-cookie auth
    $Script:AAPSession = @{
        BaseUrl              = $baseUrl
        Token                = $null
        TokenId              = $null
        AuthMethod           = 'Session'
        WebSession           = $session
        SkipCertificateCheck = [bool]$SkipCertificateCheck
    }

    [PSCustomObject]@{
        PSTypeName = 'AAP.Connection'
        Server     = $baseUrl
        Username   = $Credential.UserName
        AuthMethod = 'Session'
    }
}
