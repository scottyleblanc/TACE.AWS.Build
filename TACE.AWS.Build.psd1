#Requires -Version 7.0
@{
    # Module identity
    RootModule        = 'TACE.AWS.Build.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b2c3d4e5-f6a7-8901-bcde-f23456789012'
    Author            = 'Scott LeBlanc'
    CompanyName       = 'TACE Data Management Inc.'
    Copyright         = 'Copyright © TACE Data Management Inc.'
    Description       = 'TACE.AWS.Build — EC2 instance and Elastic IP lifecycle management via AWS Launch Templates. Build new instances from named profiles and safely tear them down.'

    # Requirements
    PowerShellVersion = '7.0'

    # Exported functions — update this list as new public functions are added
    FunctionsToExport = @(
        'New-TaceInstance'
        'Remove-TaceInstance'
        'Remove-TaceElasticIp'
        'Get-TaceOrphanedElasticIps'
    )

    AliasesToExport   = @()
    CmdletsToExport   = @()
    VariablesToExport = @()

    PrivateData       = @{
        PSData = @{
            Tags         = @('AWS', 'EC2', 'ElasticIP', 'LaunchTemplate', 'TACE')
            ProjectUri   = ''
            LicenseUri   = ''
            ReleaseNotes = 'v0.1.0 — Initial release. New-TaceInstance, Remove-TaceInstance, Remove-TaceElasticIp.'
        }
    }
}
