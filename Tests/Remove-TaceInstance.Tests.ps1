#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'TACE.AWS.Build.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module TACE.AWS.Build -ErrorAction SilentlyContinue
}

Describe 'Remove-TaceInstance' {

    Context 'Parameter Validation' {

        It 'InstanceId is mandatory' {
            $param = (Get-Command Remove-TaceInstance).Parameters['InstanceId']
            $mandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory
            $mandatory | Should -Be $true
        }

        It 'InstanceName is mandatory' {
            $param = (Get-Command Remove-TaceInstance).Parameters['InstanceName']
            $mandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory
            $mandatory | Should -Be $true
        }

        It 'InstanceId rejects invalid format' {
            { Remove-TaceInstance -InstanceId 'not-valid' -InstanceName 'tace-linux-02' -WhatIf } |
                Should -Throw
        }

        It 'InstanceId accepts valid format' {
            { Remove-TaceInstance -InstanceId 'i-0e2007838d8464bff' -InstanceName 'tace-linux-02' -WhatIf } |
                Should -Not -Throw
        }
    }

    Context 'Implementation' {

        BeforeEach {
            Mock Assert-AwsCliAvailable { } -ModuleName TACE.AWS.Build
            Mock aws { '{"ID":"i-0e2007838d8464bff","Prev":"running","Curr":"shutting-down"}' } -ModuleName TACE.AWS.Build
            Mock Read-Host { return 'tace-linux-02' } -ModuleName TACE.AWS.Build
        }

        It 'returns Success=$true when confirmation matches' {
            $result = Remove-TaceInstance -InstanceId 'i-0e2007838d8464bff' -InstanceName 'tace-linux-02' -Confirm:$false
            $result.Success | Should -Be $true
        }

        It 'returns Success=$false when confirmation does not match' {
            Mock Read-Host { return 'wrong-name' } -ModuleName TACE.AWS.Build
            $result = Remove-TaceInstance -InstanceId 'i-0e2007838d8464bff' -InstanceName 'tace-linux-02' -Confirm:$false
            $result.Success | Should -Be $false
        }

        It 'returns PSCustomObject with Success, Data, Message' {
            $result = Remove-TaceInstance -InstanceId 'i-0e2007838d8464bff' -InstanceName 'tace-linux-02' -Confirm:$false
            $result.PSObject.Properties.Name | Should -Contain 'Success'
            $result.PSObject.Properties.Name | Should -Contain 'Data'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
        }

        It 'Message does not contain credential fragments on success' {
            $result = Remove-TaceInstance -InstanceId 'i-0e2007838d8464bff' -InstanceName 'tace-linux-02' -Confirm:$false
            $result.Message | Should -Not -Match 'password|secret|token|key'
        }
    }

    Context 'Security' {

        It 'does not call AWS CLI when -WhatIf is specified' {
            Mock Assert-AwsCliAvailable { } -ModuleName TACE.AWS.Build
            Mock aws { throw 'AWS CLI should not be called under -WhatIf' }
            { Remove-TaceInstance -InstanceId 'i-0e2007838d8464bff' -InstanceName 'tace-linux-02' -WhatIf } |
                Should -Not -Throw
            Should -Not -Invoke aws
        }

        It 'does not call AWS CLI when confirmation does not match' {
            Mock Assert-AwsCliAvailable { } -ModuleName TACE.AWS.Build
            Mock Read-Host { return 'wrong-name' } -ModuleName TACE.AWS.Build
            Mock aws { throw 'AWS CLI should not be called after failed confirmation' }
            { Remove-TaceInstance -InstanceId 'i-0e2007838d8464bff' -InstanceName 'tace-linux-02' -Confirm:$false } |
                Should -Not -Throw
            Should -Not -Invoke aws -ParameterFilter { $args -contains 'terminate-instances' }
        }
    }
}
