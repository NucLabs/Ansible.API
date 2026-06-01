function Get-AAPJobEvents {
    <#
    .SYNOPSIS
        Retrieves the job events for a given AAP/AWX job.
    .DESCRIPTION
        Fetches events from GET /api/v2/jobs/{id}/job_events/ and returns them
        as individual objects. Handles API pagination automatically.
        Use -Task to filter to a specific task name (server-side) and -EventType
        to filter by event kind (default: all events). Combine them to get only
        the result object of a named task with no surrounding noise.
        Accepts a job ID directly or a job object piped from Get-AAPJob.
    .PARAMETER Id
        The job ID whose events should be retrieved.
    .PARAMETER InputObject
        A job object piped from Get-AAPJob. The Id property is used.
    .PARAMETER Task
        Filter events to those produced by a specific task name (server-side filter).
    .PARAMETER EventType
        Filter events by event type. Common values: runner_on_ok, runner_on_failed,
        runner_on_skipped, runner_on_unreachable. Defaults to all event types.
    .EXAMPLE
        Get-AAPJobEvents -Id 123
    .EXAMPLE
        Get-AAPJob -Id 123 | Get-AAPJobEvents
    .EXAMPLE
        # Get only the result of a specific task
        Get-AAPJobEvents -Id 123 -Task 'Get Ad User' -EventType runner_on_ok
    .EXAMPLE
        # Extract the module result object directly
        (Get-AAPJobEvents -Id 123 -Task 'Get Ad User' -EventType runner_on_ok).event_data.res
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ById')]
        [int]$Id,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'FromJob')]
        [object]$InputObject,

        [Parameter()]
        [string]$Task,

        [Parameter()]
        [string]$EventType
    )

    process {
        $jobId = if ($PSCmdlet.ParameterSetName -eq 'FromJob') {
            $InputObject.id
        } else {
            $Id
        }

        $query = 'page_size=200'
        if ($Task) {
            $query += "&task=$([uri]::EscapeDataString($Task))"
        }
        if ($EventType) {
            $query += "&event=$([uri]::EscapeDataString($EventType))"
        }

        $path = "/api/v2/jobs/$jobId/job_events/?$query"
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
