#Requires -Modules Pester

Describe 'Ansible.API Module' {

    BeforeAll {
        $buildScript = Join-Path $PSScriptRoot '..' 'Build.ps1'
        & $buildScript

        $manifestPath = Join-Path $PSScriptRoot '..' 'Output' 'Ansible.API.psd1'
        $modulePath   = Join-Path $PSScriptRoot '..' 'Output' 'Ansible.API.psm1'
    }

    Context 'Module manifest' {
        It 'Has a valid manifest' {
            Test-ModuleManifest -Path $manifestPath | Should -Not -BeNullOrEmpty
        }

        It 'Specifies PowerShell 7.4 as minimum version' {
            $manifest = Test-ModuleManifest -Path $manifestPath
            $manifest.PowerShellVersion | Should -Be '7.4'
        }
    }

    Context 'Exported functions' {
        BeforeAll {
            Import-Module $manifestPath -Force
        }

        AfterAll {
            Remove-Module 'Ansible.API' -ErrorAction SilentlyContinue
        }

        It 'Exports Connect-AAP' {
            Get-Command -Module 'Ansible.API' -Name 'Connect-AAP' | Should -Not -BeNullOrEmpty
        }

        It 'Exports Disconnect-AAP' {
            Get-Command -Module 'Ansible.API' -Name 'Disconnect-AAP' | Should -Not -BeNullOrEmpty
        }

        It 'Exports Get-AAPMe' {
            Get-Command -Module 'Ansible.API' -Name 'Get-AAPMe' | Should -Not -BeNullOrEmpty
        }

        It 'Exports Get-AAPJobTemplate' {
            Get-Command -Module 'Ansible.API' -Name 'Get-AAPJobTemplate' | Should -Not -BeNullOrEmpty
        }

        It 'Exports Start-AAPJobTemplate' {
            Get-Command -Module 'Ansible.API' -Name 'Start-AAPJobTemplate' | Should -Not -BeNullOrEmpty
        }

        It 'Exports Get-AAPJob' {
            Get-Command -Module 'Ansible.API' -Name 'Get-AAPJob' | Should -Not -BeNullOrEmpty
        }

        It 'Does not export private functions' {
            Get-Command -Module 'Ansible.API' -Name 'Get-AAPApiUrl' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command -Module 'Ansible.API' -Name 'Invoke-AAPRestMethod' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command -Module 'Ansible.API' -Name 'ConvertTo-AAPPascalCase' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command -Module 'Ansible.API' -Name 'ConvertTo-AAPDynamicParam' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            Get-Command -Module 'Ansible.API' -Name 'Get-AAPCachedJobTemplates' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }
    }

    Context 'Session guard' {
        BeforeAll {
            Import-Module $manifestPath -Force
        }

        AfterAll {
            Remove-Module 'Ansible.API' -ErrorAction SilentlyContinue
        }

        It 'Get-AAPMe throws when not connected' {
            { Get-AAPMe } | Should -Throw '*Not connected to AAP*'
        }

        It 'Get-AAPJobTemplate throws when not connected' {
            { Get-AAPJobTemplate } | Should -Throw '*Not connected to AAP*'
        }

        It 'Get-AAPJob throws when not connected' {
            { Get-AAPJob -Id 1 } | Should -Throw '*Not connected to AAP*'
        }

        It 'Disconnect-AAP warns when not connected' {
            Disconnect-AAP 3>&1 | Should -BeLike '*No active AAP session*'
        }
    }

    Context 'ConvertTo-AAPDynamicParam' {
        BeforeAll {
            . (Join-Path $PSScriptRoot '..' 'Private' 'ConvertTo-AAPDynamicParam.ps1')
        }

        It 'Uses original variable names as parameter names' {
            $spec = @(
                @{ variable = 'target_host'; type = 'text'; required = $true; question_name = 'Target Host'; default = ''; choices = '' }
                @{ variable = 'deploy_env'; type = 'multiplechoice'; required = $false; question_name = 'Environment'; default = 'dev'; choices = "dev`nstaging`nprod" }
            )
            $result = ConvertTo-AAPDynamicParam -SurveySpec $spec
            $result.Keys | Should -Contain 'target_host'
            $result.Keys | Should -Contain 'deploy_env'
        }
    }
}
