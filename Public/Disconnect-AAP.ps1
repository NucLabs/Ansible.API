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
