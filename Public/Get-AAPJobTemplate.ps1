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
