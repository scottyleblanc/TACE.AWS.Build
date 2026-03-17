#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

<#
.SECURITY
    Tests in this file do NOT:
      - Make real AWS API calls
      - Query real EC2 endpoints
    All AWS CLI calls and private helpers are mocked.
#>

BeforeAll {
    $modulePath = Resolve-Path "$PSScriptRoot\..\TACE.AWS.Build.psd1"
    Import-Module $modulePath -Force
}

Describe 'Get-TaceOrphanedElasticIps' {

    Context 'Parameter validation' {
        It 'Accepts call with no parameters' {
            Mock -CommandName 'Assert-AwsCliAvailable' -ModuleName 'TACE.AWS.Build' -MockWith { }
            Mock -CommandName 'aws' -ModuleName 'TACE.AWS.Build' -MockWith { '[]' }
            { Get-TaceOrphanedElasticIps } | Should -Not -Throw
        }
    }

    Context 'Implementation' {
        BeforeEach {
            Mock -CommandName 'Assert-AwsCliAvailable' -ModuleName 'TACE.AWS.Build' -MockWith { }
        }

        It 'Returns standard output contract object' {
            Mock -CommandName 'aws' -ModuleName 'TACE.AWS.Build' -MockWith { '[]' }
            $result = Get-TaceOrphanedElasticIps
            $result.PSObject.Properties.Name | Should -Contain 'Success'
            $result.PSObject.Properties.Name | Should -Contain 'Data'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
        }

        It 'Returns Success=$true when query succeeds' {
            Mock -CommandName 'aws' -ModuleName 'TACE.AWS.Build' -MockWith { '[]' }
            $result = Get-TaceOrphanedElasticIps
            $result.Success | Should -Be $true
        }

        It 'Returns empty Data array when no orphaned EIPs exist' {
            Mock -CommandName 'aws' -ModuleName 'TACE.AWS.Build' -MockWith {
                '[{"AllocationId":"eipalloc-aaa","PublicIp":"1.2.3.4","AssociationId":"eipassoc-111","Domain":"vpc"}]'
            }
            $result = Get-TaceOrphanedElasticIps
            $result.Success    | Should -Be $true
            $result.Data.Count | Should -Be 0
        }

        It 'Returns orphaned EIPs that have no AssociationId' {
            Mock -CommandName 'aws' -ModuleName 'TACE.AWS.Build' -MockWith {
                '[
                    {"AllocationId":"eipalloc-aaa","PublicIp":"1.2.3.4","AssociationId":"eipassoc-111","Domain":"vpc"},
                    {"AllocationId":"eipalloc-bbb","PublicIp":"5.6.7.8","AssociationId":null,"Domain":"vpc"},
                    {"AllocationId":"eipalloc-ccc","PublicIp":"9.10.11.12","AssociationId":null,"Domain":"vpc"}
                ]'
            }
            $result = Get-TaceOrphanedElasticIps
            $result.Success    | Should -Be $true
            $result.Data.Count | Should -Be 2
            $result.Data[0].AllocationId | Should -Be 'eipalloc-bbb'
            $result.Data[0].PublicIp     | Should -Be '5.6.7.8'
            $result.Data[1].AllocationId | Should -Be 'eipalloc-ccc'
        }

        It 'Each Data item has AllocationId, PublicIp, and Domain properties' {
            Mock -CommandName 'aws' -ModuleName 'TACE.AWS.Build' -MockWith {
                '[{"AllocationId":"eipalloc-bbb","PublicIp":"5.6.7.8","AssociationId":null,"Domain":"vpc"}]'
            }
            $result = Get-TaceOrphanedElasticIps
            $item = $result.Data[0]
            $item.PSObject.Properties.Name | Should -Contain 'AllocationId'
            $item.PSObject.Properties.Name | Should -Contain 'PublicIp'
            $item.PSObject.Properties.Name | Should -Contain 'Domain'
        }

        It 'Message includes the orphaned EIP count' {
            Mock -CommandName 'aws' -ModuleName 'TACE.AWS.Build' -MockWith {
                '[
                    {"AllocationId":"eipalloc-bbb","PublicIp":"5.6.7.8","AssociationId":null,"Domain":"vpc"},
                    {"AllocationId":"eipalloc-ccc","PublicIp":"9.10.11.12","AssociationId":null,"Domain":"vpc"}
                ]'
            }
            $result = Get-TaceOrphanedElasticIps
            $result.Message | Should -Match '2'
        }

        It 'Calls describe-addresses once' {
            Mock -CommandName 'aws' -ModuleName 'TACE.AWS.Build' -MockWith { '[]' }
            Get-TaceOrphanedElasticIps
            Should -Invoke 'aws' -ModuleName 'TACE.AWS.Build' -Times 1 -ParameterFilter {
                $args -contains 'describe-addresses'
            }
        }
    }

    Context 'Security' {
        It 'Error message contains no credential fragments' {
            Mock -CommandName 'Assert-AwsCliAvailable' -ModuleName 'TACE.AWS.Build' -MockWith {
                throw 'simulated failure'
            }
            $err = $null
            try { Get-TaceOrphanedElasticIps } catch { $err = $_ }
            $err.Exception.Message | Should -Not -Match 'password|secret|key|token|credential'
        }

        It 'Data items do not expose AssociationId in output' {
            Mock -CommandName 'Assert-AwsCliAvailable' -ModuleName 'TACE.AWS.Build' -MockWith { }
            Mock -CommandName 'aws' -ModuleName 'TACE.AWS.Build' -MockWith {
                '[{"AllocationId":"eipalloc-bbb","PublicIp":"5.6.7.8","AssociationId":null,"Domain":"vpc"}]'
            }
            $result = Get-TaceOrphanedElasticIps
            $result.Data[0].PSObject.Properties.Name | Should -Not -Contain 'AssociationId'
        }
    }
}
