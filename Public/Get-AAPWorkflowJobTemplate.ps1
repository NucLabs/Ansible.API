function Get-AAPWorkflowJobTemplate {
    <#
    .SYNOPSIS
        Lists or retrieves AAP/AWX workflow job templates.
    .DESCRIPTION
        Without parameters, lists all workflow job templates. Use -Name for wildcard
        filtering (server-side search) or -Id for a specific template.
    .PARAMETER Name
        Filter templates by name. Supports server-side search and tab-completion.
    .PARAMETER Id
        Retrieve a specific template by its ID.
    .EXAMPLE
        Get-AAPWorkflowJobTemplate
    .EXAMPLE
        Get-AAPWorkflowJobTemplate -Name 'Deploy*'
    .EXAMPLE
        Get-AAPWorkflowJobTemplate -Id 42
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
            Invoke-AAPRestMethod -Method GET -Path "/api/v2/workflow_job_templates/$Id/"
        }
        'ByName' {
            $path = '/api/v2/workflow_job_templates/?page_size=200'
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
            $path = '/api/v2/workflow_job_templates/?page_size=200'
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

Register-ArgumentCompleter -CommandName 'Get-AAPWorkflowJobTemplate' -ParameterName 'Name' -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $templates = Get-AAPCachedWorkflowJobTemplates
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
