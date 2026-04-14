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

    $authMethod = $Script:AAPSession.AuthMethod

    if ($authMethod -eq 'BearerToken' -and $Script:AAPSession.TokenId) {
        # Revoke the token we created
        try {
            Invoke-AAPRestMethod -Method DELETE -Path "/api/v2/tokens/$($Script:AAPSession.TokenId)/"
        }
        catch {
            Write-Warning "Failed to revoke token on server: $_"
        }
    } elseif ($authMethod -eq 'Token') {
        Write-Verbose 'Pre-generated token provided — not revoking (manage it externally).'
    } elseif ($authMethod -eq 'Session') {
        Write-Verbose 'Session-based auth — session cookies cleared.'
    }

    $Script:AAPSession = $null
    Write-Verbose 'Disconnected from AAP.'
}
