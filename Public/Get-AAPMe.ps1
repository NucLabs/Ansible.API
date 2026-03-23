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
