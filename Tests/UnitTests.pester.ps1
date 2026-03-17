#Requires -Version 7.0
<#
.SYNOPSIS
    Pester configuration for TACE.AWS.Build unit tests.

.DESCRIPTION
    Runs only unit tests. Integration tests are explicitly excluded —
    they live in Tests\Integration\*.Integration.Tests.ps1 and require
    real AWS credentials and live infrastructure.

    Usage:
        Invoke-Pester -Configuration (& .\Tests\UnitTests.pester.ps1)

.NOTES
    Copyright © TACE Data Management Inc.
#>

$config = New-PesterConfiguration

$unitTestFiles = Get-ChildItem -Path $PSScriptRoot -Filter '*.Tests.ps1' -File |
    Where-Object { $_.Name -notlike '*.Integration.Tests.ps1' } |
    Select-Object -ExpandProperty FullName

$config.Run.Path                = $unitTestFiles

$config.Output.Verbosity        = 'Detailed'

$config.TestResult.Enabled      = $true
$config.TestResult.OutputPath   = "$PSScriptRoot\TestResults\UnitTests.xml"
$config.TestResult.OutputFormat = 'NUnitXml'

return $config
