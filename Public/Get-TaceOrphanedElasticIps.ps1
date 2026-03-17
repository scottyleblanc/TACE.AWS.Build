#Requires -Version 7.0

function Get-TaceOrphanedElasticIps {
    <#
    .SYNOPSIS
        Returns all Elastic IPs in the account that are allocated but not associated
        with any EC2 instance.

    .DESCRIPTION
        Queries EC2 for all allocated Elastic IPs and returns those with no instance
        association. These are billable resources ($0.005/hr each) left behind when
        an instance is removed without releasing its EIP.

        Use Remove-TaceElasticIp to release each returned EIP after verifying it is
        no longer needed.

    .PARAMETER Region
        The AWS region to query. Defaults to config DefaultRegion.

    .PARAMETER Profile
        The AWS CLI profile to use. Defaults to config DefaultProfile.

    .EXAMPLE
        Get-TaceOrphanedElasticIps

        Returns all unassociated EIPs in the default region.

    .EXAMPLE
        (Get-TaceOrphanedElasticIps).Data | Select-Object PublicIp, AllocationId

        Lists orphaned EIPs in a compact format.

    .EXAMPLE
        $orphans = Get-TaceOrphanedElasticIps
        if ($orphans.Success -and $orphans.Data.Count -gt 0) {
            $orphans.Data | ForEach-Object {
                Remove-TaceElasticIp -AllocationId $_.AllocationId -PublicIp $_.PublicIp
            }
        }

        Finds all orphaned EIPs and releases each one interactively.

    .OUTPUTS
        PSCustomObject — Success, Data (array of AllocationId/PublicIp/Domain objects), Message.

    .NOTES
        [SEC] No credentials or sensitive values are included in any output path.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter()]
        [string] $Region = $script:DefaultRegion,

        [Parameter()]
        [string] $Profile = $script:DefaultProfile
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    try {
        Assert-AwsCliAvailable

        $eipParams = @(
            'ec2', 'describe-addresses',
            '--region', $Region,
            '--profile', $Profile,
            '--query', 'Addresses[].{AllocationId:AllocationId,PublicIp:PublicIp,AssociationId:AssociationId,Domain:Domain}',
            '--output', 'json'
        )
        $allEips = @(aws @eipParams | ConvertFrom-Json)

        $orphaned = @($allEips | Where-Object {
            -not $_.AssociationId
        } | ForEach-Object {
            [PSCustomObject]@{
                AllocationId = $_.AllocationId
                PublicIp     = $_.PublicIp
                Domain       = $_.Domain
            }
        })

        $msg = "Found $($orphaned.Count) orphaned Elastic IP(s) in $Region"
        Write-Verbose "[Get-TaceOrphanedElasticIps] $msg at $(Get-Date -Format 'u')"

        return [PSCustomObject]@{
            Success = $true
            Data    = $orphaned
            Message = $msg
        }
    }
    catch {
        $errorMessage = $($_.Exception.Message)
        throw "Get-TaceOrphanedElasticIps failed: $errorMessage"
    }
}
