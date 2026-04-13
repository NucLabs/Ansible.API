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
