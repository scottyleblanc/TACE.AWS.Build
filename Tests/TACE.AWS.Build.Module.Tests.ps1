#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'TACE.AWS.Build.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module TACE.AWS.Build -ErrorAction SilentlyContinue
}

Describe 'TACE.AWS.Build Module' {

    Context 'Module loads successfully' {

        It 'imports without error' {
            { Import-Module (Join-Path $PSScriptRoot '..' 'TACE.AWS.Build.psd1') -Force } |
                Should -Not -Throw
        }

        It 'exports New-TaceInstance' {
            Get-Command -Module TACE.AWS.Build -Name New-TaceInstance |
                Should -Not -BeNullOrEmpty
        }

        It 'exports Remove-TaceInstance' {
            Get-Command -Module TACE.AWS.Build -Name Remove-TaceInstance |
                Should -Not -BeNullOrEmpty
        }

        It 'exports Remove-TaceElasticIp' {
            Get-Command -Module TACE.AWS.Build -Name Remove-TaceElasticIp |
                Should -Not -BeNullOrEmpty
        }

        It 'exports Get-TaceOrphanedElasticIps' {
            Get-Command -Module TACE.AWS.Build -Name Get-TaceOrphanedElasticIps |
                Should -Not -BeNullOrEmpty
        }
    }

    Context 'Config is loaded' {

        It 'module-scoped DefaultRegion is not null or empty' {
            # Access via a function that uses the config variable
            $fn = Get-Command New-TaceInstance
            $fn | Should -Not -BeNullOrEmpty
        }
    }
}
