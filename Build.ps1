<#
.SYNOPSIS
    Builds the Ansible.API module into Output/Ansible.API.psm1 and .psd1.
.DESCRIPTION
    Reads all .ps1 files from Private/ and Public/ folders, concatenates them
    into a single .psm1 file, and generates a module manifest (.psd1) that
    exports only the public functions.
#>
[CmdletBinding()]
param()

$ModuleName = 'Ansible.API'
$OutputDir  = Join-Path $PSScriptRoot 'Output'

# Ensure output directory exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$psm1Path = Join-Path $OutputDir "$ModuleName.psm1"
$psd1Path = Join-Path $OutputDir "$ModuleName.psd1"

# Collect source files
$privateFiles = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue
$publicFiles  = Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue

# Build the .psm1 content
$psm1Content = @"
#
# Module: $ModuleName
# Built:  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
#

"@

# Add private functions
foreach ($file in $privateFiles) {
    $psm1Content += "`n#region $($file.Name)`n"
    $psm1Content += (Get-Content -Path $file.FullName -Raw)
    $psm1Content += "`n#endregion`n"
}

# Add public functions
foreach ($file in $publicFiles) {
    $psm1Content += "`n#region $($file.Name)`n"
    $psm1Content += (Get-Content -Path $file.FullName -Raw)
    $psm1Content += "`n#endregion`n"
}

# Write .psm1
Set-Content -Path $psm1Path -Value $psm1Content -Encoding UTF8
Write-Host "Created $psm1Path" -ForegroundColor Green

# Determine public function names to export
$functionsToExport = $publicFiles | ForEach-Object { $_.BaseName }

# Build .psd1 manifest
$manifestParams = @{
    Path               = $psd1Path
    RootModule         = "$ModuleName.psm1"
    ModuleVersion      = '0.1.0'
    Author             = 'Ansible.API Contributors'
    Description        = 'PowerShell module for the AWX/AAP REST API'
    PowerShellVersion  = '7.4'
    FunctionsToExport  = $functionsToExport
    CmdletsToExport    = @()
    VariablesToExport   = @()
    AliasesToExport    = @()
}

New-ModuleManifest @manifestParams
Write-Host "Created $psd1Path" -ForegroundColor Green

Write-Host "`nBuild complete. Exported functions:" -ForegroundColor Cyan
$functionsToExport | ForEach-Object { Write-Host "  - $_" }
