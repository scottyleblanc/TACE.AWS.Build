#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'TACE.AWS.Build.psd1'
    Import-Module $modulePath -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module TACE.AWS.Build -ErrorAction SilentlyContinue
}

Describe 'New-TaceInstance' {

    Context 'Parameter Validation' {

        It 'ProfileName is mandatory' {
            $param = (Get-Command New-TaceInstance).Parameters['ProfileName']
            $mandatory = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -ExpandProperty Mandatory
            $mandatory | Should -Be $true
        }

        It 'InstanceNumber accepts values 1-99' {
            $param = (Get-Command New-TaceInstance).Parameters['InstanceNumber']
            $range = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $range.MinRange | Should -Be 1
            $range.MaxRange | Should -Be 99
        }

        It 'MaxWaitSeconds accepts values 30-600' {
            $param = (Get-Command New-TaceInstance).Parameters['MaxWaitSeconds']
            $range = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $range.MinRange | Should -Be 30
            $range.MaxRange | Should -Be 600
        }
    }

    Context 'Implementation' {

        BeforeEach {
            Mock Assert-AwsCliAvailable { } -ModuleName TACE.AWS.Build
            Mock Get-TaceLaunchTemplate {
                [PSCustomObject]@{ TemplateId = 'lt-0abc1234567890def'; TemplateName = 'tace-linux'; Description = 'Test template' }
            } -ModuleName TACE.AWS.Build
            Mock aws {
                # Stub: describe-instances (list existing names)
                if ($args -contains 'describe-instances') { return '[[]]' | ConvertFrom-Json | ConvertTo-Json }
                # Stub: run-instances
                if ($args -contains 'run-instances') { return '{"InstanceId":"i-0test1234567890a","State":"pending"}' }
                # Stub: describe-instances (state poll)
                if ($args -contains 'text' -and $args -contains 'describe-instances') { return 'running' }
                # Stub: describe-instance-information (SSM)
                if ($args -contains 'describe-instance-information') { return 'Online' }
                # Stub: allocate-address
                if ($args -contains 'allocate-address') { return '{"PublicIp":"1.2.3.4","AllocationId":"eipalloc-0test1234"}' }
                # Stub: associate-address
                if ($args -contains 'associate-address') { return '{}' }
            }
            Mock Read-Host { return 'N' } -ModuleName TACE.AWS.Build
        }

        It 'returns a PSCustomObject with Success, Data, and Message' {
            $result = New-TaceInstance -ProfileName 'tace-linux' -Confirm:$false
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain 'Success'
            $result.PSObject.Properties.Name | Should -Contain 'Data'
            $result.PSObject.Properties.Name | Should -Contain 'Message'
        }

        It 'Message does not contain credential fragments' {
            $result = New-TaceInstance -ProfileName 'tace-linux' -Confirm:$false
            $result.Message | Should -Not -Match 'password|secret|token|key'
        }
    }

    Context 'Security' {

        BeforeEach {
            Mock Assert-AwsCliAvailable { } -ModuleName TACE.AWS.Build
        }

        It 'does not call AWS CLI when -WhatIf is specified' {
            Mock aws { throw 'AWS CLI should not be called under -WhatIf' }
            Mock Get-TaceLaunchTemplate {
                [PSCustomObject]@{ TemplateId = 'lt-0abc1234567890def'; TemplateName = 'tace-linux'; Description = 'Test' }
            } -ModuleName TACE.AWS.Build
            { New-TaceInstance -ProfileName 'tace-linux' -WhatIf } | Should -Not -Throw
            Should -Not -Invoke aws
        }
    }
}
