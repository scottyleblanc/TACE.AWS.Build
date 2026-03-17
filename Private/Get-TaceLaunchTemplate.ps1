#Requires -Version 7.0

function Get-TaceLaunchTemplate {
    <#
    .SYNOPSIS
        Resolves a launch template profile name to its AWS Launch Template ID.

    .DESCRIPTION
        Reads the module config to locate the Launch Template entry for the given
        profile name (e.g. 'tace-linux'). Validates that the TemplateId is not a
        placeholder value. Returns the template config object on success.

    .PARAMETER ProfileName
        The named launch template profile to resolve (e.g. 'tace-linux', 'tace-windows').
        Must match a key under LaunchTemplates in tace.aws.build.config.json.

    .OUTPUTS
        PSCustomObject with TemplateId, TemplateName, Description properties.

    .NOTES
        Private function — not exported from the module.
        [SEC] TemplateId values must not contain user-supplied data — read from config only.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProfileName
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $templates = $script:Config.LaunchTemplates
    if (-not $templates.PSObject.Properties[$ProfileName]) {
        throw "Launch template profile '$ProfileName' not found in config. Available profiles: $($templates.PSObject.Properties.Name -join ', ')"
    }

    $template = $templates.$ProfileName

    if ($template.TemplateId -eq 'lt-PLACEHOLDER' -or $template.TemplateId -notmatch '^lt-[0-9a-f]+$') {
        throw "Launch template '$ProfileName' has not been configured. Update 'TemplateId' in config/tace.aws.build.config.json with the AWS Launch Template ID (format: lt-xxxxxxxxxxxxxxxxx)."
    }

    [PSCustomObject]@{
        TemplateId   = $template.TemplateId
        TemplateName = $template.TemplateName
        Description  = $template.Description
    }
}
