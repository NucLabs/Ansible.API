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
        if ($Script:AAPSurveyParamNames) {
            foreach ($paramName in $Script:AAPSurveyParamNames) {
                if ($PSBoundParameters.ContainsKey($paramName)) {
                    $value = $PSBoundParameters[$paramName]
                    if ($value -is [array]) {
                        $vars[$paramName] = $value -join "`n"
                    } else {
                        $vars[$paramName] = $value
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
