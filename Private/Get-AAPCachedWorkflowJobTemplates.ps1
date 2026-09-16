function Get-AAPCachedWorkflowJobTemplates {
    <#
    .SYNOPSIS
        Returns a cached list of all workflow job templates, refreshing if stale.
    .DESCRIPTION
        Fetches all workflow job templates from /api/controller/v2/workflow_job_templates/ with pagination.
        Caches the results in $Script:AAPSession.WorkflowJobTemplateCache for 60 seconds
        to avoid excessive API calls during tab completion.
    #>
    [CmdletBinding()]
    param()

    if (-not $Script:AAPSession) {
        return @()
    }

    $cache = $Script:AAPSession.WorkflowJobTemplateCache
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    if ($cache -and $cache.CachedAt -and ($now - $cache.CachedAt) -lt 60) {
        return $cache.Templates
    }

    # Fetch all templates with pagination
    $templates = [System.Collections.Generic.List[object]]::new()
    $path = '/api/controller/v2/workflow_job_templates/?page_size=200'

    while ($path) {
        $response = Invoke-AAPRestMethod -Method GET -Path $path
        if ($response.results) {
            $templates.AddRange($response.results)
        }
        if ($response.next) {
            # next is a full path like /api/controller/v2/workflow_job_templates/?page=2
            $path = $response.next
        } else {
            $path = $null
        }
    }

    $Script:AAPSession.WorkflowJobTemplateCache = @{
        Templates = $templates.ToArray()
        CachedAt  = $now
    }

    return $Script:AAPSession.WorkflowJobTemplateCache.Templates
}
