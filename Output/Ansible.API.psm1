#
# Module: Ansible.API
# Built:  2026-04-14 08:39:58
#

#region ConvertTo-AAPDynamicParam.ps1
function ConvertTo-AAPDynamicParam {
    <#
    .SYNOPSIS
        Converts an AWX/AAP survey_spec into a RuntimeDefinedParameterDictionary.
    .DESCRIPTION
        Takes the spec array from GET /api/v2/job_templates/{id}/survey_spec/
        and generates typed PowerShell dynamic parameters. Also populates
        $Script:AAPSurveyParamMap with the PascalCase-to-original-variable mapping.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.RuntimeDefinedParameterDictionary])]
    param(
        [Parameter(Mandatory)]
        [object[]]$SurveySpec
    )

    $paramDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
    $Script:AAPSurveyParamMap = @{}

    foreach ($field in $SurveySpec) {
        $originalName = $field.variable
        $paramName = ConvertTo-AAPPascalCase -Value $originalName
        $Script:AAPSurveyParamMap[$paramName] = $originalName

        # Determine .NET type
        $paramType = switch ($field.type) {
            'integer'        { [int] }
            'float'          { [double] }
            'multiselect'    { [string[]] }
            default          { [string] }  # text, textarea, password, multiplechoice
        }

        # Build attributes
        $attributes = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()

        $paramAttribute = [System.Management.Automation.ParameterAttribute]::new()
        $paramAttribute.Mandatory = [bool]$field.required
        if ($field.question_name) {
            $paramAttribute.HelpMessage = $field.question_name
        }
        $attributes.Add($paramAttribute)

        # ValidateSet for choice fields
        if ($field.type -in 'multiplechoice', 'multiselect' -and $field.choices) {
            $choiceList = if ($field.choices -is [array]) {
                $field.choices
            } else {
                ($field.choices -split "`n") | Where-Object { $_.Trim() -ne '' }
            }
            if ($choiceList.Count -gt 0) {
                $validateSet = [System.Management.Automation.ValidateSetAttribute]::new([string[]]$choiceList)
                $attributes.Add($validateSet)
            }
        }

        $dynParam = [System.Management.Automation.RuntimeDefinedParameter]::new(
            $paramName,
            $paramType,
            $attributes
        )

        # Set default value if provided and not empty
        if ($null -ne $field.default -and "$($field.default)" -ne '') {
            $dynParam.Value = $field.default
        }

        $paramDictionary.Add($paramName, $dynParam)
    }

    return $paramDictionary
}

#endregion

#region ConvertTo-AAPPascalCase.ps1
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

#endregion

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

#region Get-AAPCachedJobTemplates.ps1
function Get-AAPCachedJobTemplates {
    <#
    .SYNOPSIS
        Returns a cached list of all job templates, refreshing if stale.
    .DESCRIPTION
        Fetches all job templates from /api/v2/job_templates/ with pagination.
        Caches the results in $Script:AAPSession.JobTemplateCache for 60 seconds
        to avoid excessive API calls during tab completion.
    #>
    [CmdletBinding()]
    param()

    if (-not $Script:AAPSession) {
        return @()
    }

    $cache = $Script:AAPSession.JobTemplateCache
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    if ($cache -and $cache.CachedAt -and ($now - $cache.CachedAt) -lt 60) {
        return $cache.Templates
    }

    # Fetch all templates with pagination
    $templates = [System.Collections.Generic.List[object]]::new()
    $path = '/api/v2/job_templates/?page_size=200'

    while ($path) {
        $response = Invoke-AAPRestMethod -Method GET -Path $path
        if ($response.results) {
            $templates.AddRange($response.results)
        }
        if ($response.next) {
            # next is a full path like /api/v2/job_templates/?page=2
            $path = $response.next
        } else {
            $path = $null
        }
    }

    $Script:AAPSession.JobTemplateCache = @{
        Templates = $templates.ToArray()
        CachedAt  = $now
    }

    return $Script:AAPSession.JobTemplateCache.Templates
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

#region Get-AAPJob.ps1
function Get-AAPJob {
    <#
    .SYNOPSIS
        Retrieves an AAP/AWX job by ID, optionally waiting for completion.
    .DESCRIPTION
        Fetches job status from GET /api/v2/jobs/{id}/. With -Wait, polls until
        the job reaches a terminal state (successful, failed, error, canceled).
    .PARAMETER Id
        The job ID to retrieve.
    .PARAMETER Wait
        Wait for the job to reach a terminal state before returning.
    .PARAMETER WaitTimeout
        Maximum seconds to wait (default: 600).
    .PARAMETER PollInterval
        Seconds between status checks (default: 5).
    .EXAMPLE
        Get-AAPJob -Id 123
    .EXAMPLE
        Get-AAPJob -Id 123 -Wait
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [int]$Id,

        [Parameter()]
        [switch]$Wait,

        [Parameter()]
        [int]$WaitTimeout = 600,

        [Parameter()]
        [int]$PollInterval = 5
    )

    $job = Invoke-AAPRestMethod -Method GET -Path "/api/v2/jobs/$Id/"

    if (-not $Wait) {
        return $job
    }

    $terminalStates = @('successful', 'failed', 'error', 'canceled')
    $elapsed = 0

    while ($job.status -notin $terminalStates -and $elapsed -lt $WaitTimeout) {
        Write-Verbose "Job $Id status: $($job.status) — waiting ($elapsed`s / $WaitTimeout`s)"
        Start-Sleep -Seconds $PollInterval
        $elapsed += $PollInterval
        $job = Invoke-AAPRestMethod -Method GET -Path "/api/v2/jobs/$Id/"
    }

    if ($job.status -notin $terminalStates) {
        Write-Warning "Job $Id did not complete within $WaitTimeout seconds. Last status: $($job.status)"
    }

    $job
}

#endregion

#region Get-AAPJobTemplate.ps1
function Get-AAPJobTemplate {
    <#
    .SYNOPSIS
        Lists or retrieves AAP/AWX job templates.
    .DESCRIPTION
        Without parameters, lists all job templates. Use -Name for wildcard
        filtering (server-side search) or -Id for a specific template.
    .PARAMETER Name
        Filter templates by name. Supports server-side search.
    .PARAMETER Id
        Retrieve a specific template by its ID.
    .EXAMPLE
        Get-AAPJobTemplate
    .EXAMPLE
        Get-AAPJobTemplate -Name 'Deploy*'
    .EXAMPLE
        Get-AAPJobTemplate -Id 42
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [int]$Id
    )

    switch ($PSCmdlet.ParameterSetName) {
        'ById' {
            Invoke-AAPRestMethod -Method GET -Path "/api/v2/job_templates/$Id/"
        }
        'ByName' {
            $path = '/api/v2/job_templates/?page_size=200'
            if ($Name) {
                $searchTerm = $Name -replace '[*?]', ''
                $path += "&search=$([uri]::EscapeDataString($searchTerm))"
            }

            $results = [System.Collections.Generic.List[object]]::new()
            while ($path) {
                $response = Invoke-AAPRestMethod -Method GET -Path $path
                if ($response.results) {
                    $results.AddRange($response.results)
                }
                $path = $response.next
            }

            # Client-side wildcard filtering if the Name had wildcards
            if ($Name -and ($Name -match '[*?]')) {
                $results | Where-Object { $_.name -like $Name }
            } else {
                $results
            }
        }
        default {
            # List all
            $path = '/api/v2/job_templates/?page_size=200'
            $results = [System.Collections.Generic.List[object]]::new()
            while ($path) {
                $response = Invoke-AAPRestMethod -Method GET -Path $path
                if ($response.results) {
                    $results.AddRange($response.results)
                }
                $path = $response.next
            }
            $results
        }
    }
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

#region Start-AAPJobTemplate.ps1
function Start-AAPJobTemplate {
    <#
    .SYNOPSIS
        Launches an AAP/AWX job template by name or ID.
    .DESCRIPTION
        Launches a job template. If the template has a survey, the survey fields
        are exposed as dynamic PowerShell parameters with proper types and validation.
        Use tab-completion on -Name to discover available templates.
    .PARAMETER Name
        The name of the job template to launch. Supports tab-completion.
    .PARAMETER Id
        The ID of the job template to launch (alternative to -Name).
    .PARAMETER ExtraVars
        A hashtable of extra variables to pass to the job. These are merged with
        any survey parameters provided via dynamic parameters.
    .PARAMETER Wait
        Wait for the job to complete before returning.
    .PARAMETER WaitTimeout
        Maximum seconds to wait for job completion (default: 600).
    .PARAMETER PollInterval
        Seconds between status checks when waiting (default: 5).
    .EXAMPLE
        Start-AAPJobTemplate -Name 'Deploy Web App' -Wait
    .EXAMPLE
        Start-AAPJobTemplate -Name 'Provision Server' -TargetHost 'web01' -DeployEnv 'production' -Wait
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(ParameterSetName = 'ByName', Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [int]$Id,

        [Parameter()]
        [hashtable]$ExtraVars,

        [Parameter()]
        [switch]$Wait,

        [Parameter()]
        [int]$WaitTimeout = 600,

        [Parameter()]
        [int]$PollInterval = 5
    )

    DynamicParam {
        if (-not $Script:AAPSession) { return }

        # Resolve the template to check for survey
        $templateId = $null
        if ($PSBoundParameters.ContainsKey('Id')) {
            $templateId = $PSBoundParameters['Id']
        } elseif ($PSBoundParameters.ContainsKey('Name')) {
            $templateName = $PSBoundParameters['Name']
            $templates = Get-AAPCachedJobTemplates
            $match = $templates | Where-Object { $_.name -eq $templateName } | Select-Object -First 1
            if ($match) {
                $templateId = $match.id
            }
        }

        if ($templateId) {
            try {
                $cached = $Script:AAPSession.SurveySpecCache
                if ($cached -and $cached.TemplateId -eq $templateId) {
                    $surveySpec = $cached.Spec
                } else {
                    $template = Invoke-AAPRestMethod -Method GET -Path "/api/v2/job_templates/$templateId/"
                    if ($template.survey_enabled) {
                        $survey = Invoke-AAPRestMethod -Method GET -Path "/api/v2/job_templates/$templateId/survey_spec/"
                        $surveySpec = $survey.spec
                        $Script:AAPSession.SurveySpecCache = @{
                            TemplateId = $templateId
                            Spec       = $surveySpec
                        }
                    }
                }
            } catch {
                # Fail silently during tab completion — don't break the prompt
                $surveySpec = $null
            }

            if ($surveySpec) {
                return (ConvertTo-AAPDynamicParam -SurveySpec $surveySpec)
            }
        }
    }

    Process {
        # Resolve template ID
        $templateId = if ($PSBoundParameters.ContainsKey('Id')) {
            $Id
        } else {
            $templates = Get-AAPCachedJobTemplates
            $match = $templates | Where-Object { $_.name -eq $Name } | Select-Object -First 1
            if (-not $match) {
                throw "Job template '$Name' not found."
            }
            $match.id
        }

        # Build extra_vars from dynamic params + ExtraVars
        $vars = @{}

        # Collect bound dynamic parameters (survey fields)
        if ($Script:AAPSurveyParamMap) {
            foreach ($paramName in $Script:AAPSurveyParamMap.Keys) {
                if ($PSBoundParameters.ContainsKey($paramName)) {
                    $originalName = $Script:AAPSurveyParamMap[$paramName]
                    $value = $PSBoundParameters[$paramName]
                    if ($value -is [array]) {
                        $vars[$originalName] = $value -join "`n"
                    } else {
                        $vars[$originalName] = $value
                    }
                }
            }
        }

        # Merge ExtraVars (explicit ExtraVars take precedence)
        if ($ExtraVars) {
            foreach ($key in $ExtraVars.Keys) {
                $vars[$key] = $ExtraVars[$key]
            }
        }

        # Build launch body
        $body = @{}
        if ($vars.Count -gt 0) {
            $body['extra_vars'] = $vars
        }

        # Launch
        $job = Invoke-AAPRestMethod -Method POST -Path "/api/v2/job_templates/$templateId/launch/" -Body $body

        if ($Wait) {
            $jobId = $job.id
            $elapsed = 0
            $terminalStates = @('successful', 'failed', 'error', 'canceled')

            while ($elapsed -lt $WaitTimeout) {
                $jobStatus = Invoke-AAPRestMethod -Method GET -Path "/api/v2/jobs/$jobId/"

                if ($jobStatus.status -in $terminalStates) {
                    return $jobStatus
                }

                Write-Verbose "Job $jobId status: $($jobStatus.status) — waiting ($elapsed`s / $WaitTimeout`s)"
                Start-Sleep -Seconds $PollInterval
                $elapsed += $PollInterval
            }

            Write-Warning "Job $jobId did not complete within $WaitTimeout seconds. Last status: $($jobStatus.status)"
            return $jobStatus
        }

        $job
    }
}

# Register argument completer for -Name parameter
Register-ArgumentCompleter -CommandName 'Start-AAPJobTemplate' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $templates = Get-AAPCachedJobTemplates
    $templates | Where-Object { $_.name -like "$wordToComplete*" } | ForEach-Object {
        $name = $_.name
        $desc = $_.description
        if ($name -match '\s') {
            $completionText = "'$name'"
        } else {
            $completionText = $name
        }
        [System.Management.Automation.CompletionResult]::new(
            $completionText,
            $name,
            'ParameterValue',
            ($desc ? $desc : $name)
        )
    }
}

#endregion

