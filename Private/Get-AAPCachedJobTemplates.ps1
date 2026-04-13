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
