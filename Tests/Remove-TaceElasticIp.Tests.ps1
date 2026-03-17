#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'TACE.AWS.Build.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module TACE.AWS.Build -ErrorAction SilentlyContinue
}

Describe 'Remove-TaceElasticIp' {

    Context 'Parameter Validation' {

        It 'AllocationId is mandatory' {
            $param = (Get-Command Remove-TaceElasticIp).Parameters['AllocationId']
            $mandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory
            $mandatory | Should -Be $true
        }

        It 'PublicIp is mandatory' {
            $param = (Get-Command Remove-TaceElasticIp).Parameters['PublicIp']
            $mandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory
            $mandatory | Should -Be $true
        }

        It 'AllocationId rejects invalid format' {
            { Remove-TaceElasticIp -AllocationId 'not-valid' -PublicIp '1.2.3.4' -WhatIf } |
                Should -Throw
        }

        It 'AllocationId accepts valid format' {
            { Remove-TaceElasticIp -AllocationId 'eipalloc-062c1df88318cb5dc' -PublicIp '1.2.3.4' -WhatIf } |
                Should -Not -Throw
        }

        It 'PublicIp rejects non-IP values' {
            { Remove-TaceElasticIp -AllocationId 'eipalloc-062c1df88318cb5dc' -PublicIp 'not-an-ip' -WhatIf } |
                Should -Throw
        }
    }

    Context 'Implementation' {

        BeforeEach {
            Mock Assert-AwsCliAvailable { } -ModuleName TACE.AWS.Build
            Mock aws {
                if ($args -contains 'describe-addresses') { return 'None' }
                if ($args -contains 'release-address') { return $null }
            } -ModuleName TACE.AWS.Build
            Mock Read-Host { return '1.2.3.4' } -ModuleName TACE.AWS.Build
        }

        It 'returns Success=$true when confirmation matches' {
            $result = Remove-TaceElasticIp -AllocationId 'eipalloc-0abc1234567890def' -PublicIp '1.2.3.4' -Confirm:$false
            $result.Success | Should -Be $true
        }

        It 'returns Success=$false when confirmation does not match' {
            Mock Read-Host { return '9.9.9.9' } -ModuleName TACE.AWS.Build
            $result = Remove-TaceElasticIp -AllocationId 'eipalloc-0abc1234567890def' -PublicIp '1.2.3.4' -Confirm:$false
            $result.Success | Should -Be $false
        }

        It 'returns PSCustomObject with Success, Data, Message' {
            $result = Remove-TaceElasticIp -AllocationId 'eipalloc-0abc1234567890def' -PublicIp '1.2.3.4' -Confirm:$false
            $result.PSObject.Properties.Name | Should -Contain 'Success'
            $result.PSObject.Properties.Name | Should -Contain 'Data'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
        }

        It 'Message does not contain credential fragments' {
            $result = Remove-TaceElasticIp -AllocationId 'eipalloc-0abc1234567890def' -PublicIp '1.2.3.4' -Confirm:$false
            $result.Message | Should -Not -Match 'password|secret|token|key'
        }

        It 'Data.WasAssociated is $false when EIP has no association' {
            $result = Remove-TaceElasticIp -AllocationId 'eipalloc-0abc1234567890def' -PublicIp '1.2.3.4' -Confirm:$false
            $result.Data.WasAssociated | Should -Be $false
        }
    }

    Context 'Security' {

        It 'does not call AWS CLI when -WhatIf is specified' {
            Mock Assert-AwsCliAvailable { } -ModuleName TACE.AWS.Build
            Mock aws { throw 'AWS CLI should not be called under -WhatIf' }
            { Remove-TaceElasticIp -AllocationId 'eipalloc-0abc1234567890def' -PublicIp '1.2.3.4' -WhatIf } |
                Should -Not -Throw
            Should -Not -Invoke aws
        }

        It 'does not call release-address when confirmation does not match' {
            Mock Assert-AwsCliAvailable { } -ModuleName TACE.AWS.Build
            Mock Read-Host { return '9.9.9.9' } -ModuleName TACE.AWS.Build
            Mock aws { throw 'AWS CLI should not be called after failed confirmation' }
            { Remove-TaceElasticIp -AllocationId 'eipalloc-0abc1234567890def' -PublicIp '1.2.3.4' -Confirm:$false } |
                Should -Not -Throw
            Should -Not -Invoke aws -ParameterFilter { $args -contains 'release-address' }
        }
    }
}
