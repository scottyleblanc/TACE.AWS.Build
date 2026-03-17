#Requires -Version 7.0

function Remove-TaceElasticIp {
    <#
    .SYNOPSIS
        Disassociates and releases a TACE Elastic IP address. This action is irreversible.

    .DESCRIPTION
        Disassociates the Elastic IP from any instance it is associated with (if any),
        then releases the allocation back to AWS. Released EIPs are gone — the same
        public IP address is not guaranteed to be available again.

        Two confirmation gates are required:
          1. PowerShell SupportsShouldProcess (-WhatIf / -Confirm)
          2. Typed public IP address confirmation

        Run this after Remove-TaceInstance to stop ongoing EIP charges ($0.005/hr
        per unassociated EIP).

    .PARAMETER AllocationId
        The EIP allocation ID to release (e.g. eipalloc-062c1df88318cb5dc).

    .PARAMETER PublicIp
        The public IP address of the EIP. Used for confirmation prompts and log
        messages only — AllocationId is used for all AWS API calls.

    .PARAMETER Region
        AWS region the EIP resides in. Defaults to config DefaultRegion.

    .PARAMETER Profile
        AWS CLI profile to use. Defaults to config DefaultProfile.

    .EXAMPLE
        Remove-TaceElasticIp -AllocationId eipalloc-062c1df88318cb5dc -PublicIp 15.157.202.56

        Prompts for typed confirmation, disassociates if attached, then releases the EIP.

    .EXAMPLE
        Remove-TaceElasticIp -AllocationId eipalloc-062c1df88318cb5dc -PublicIp 15.157.202.56 -WhatIf

        Shows what would be released without executing.

    .OUTPUTS
        PSCustomObject — Success, Data (AllocationId, PublicIp, WasAssociated), Message.

    .NOTES
        [SEC] AllocationId is validated against AWS allocation ID format before use.
        Released EIPs cannot be recovered. Confirm the correct AllocationId before running.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^eipalloc-[0-9a-f]+$')]
        [string] $AllocationId,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')]
        [string] $PublicIp,

        [Parameter()]
        [string] $Region = $script:DefaultRegion,

        [Parameter()]
        [string] $Profile = $script:DefaultProfile
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    try {
        Assert-AwsCliAvailable

        # ── Gate 1: SupportsShouldProcess (-WhatIf / -Confirm) ───────────────
        if (-not $PSCmdlet.ShouldProcess($AllocationId, "RELEASE Elastic IP $PublicIp — this is irreversible")) {
            return [PSCustomObject]@{ Success = $false; Data = $null; Message = 'Operation cancelled.' }
        }

        # ── Gate 2: Typed IP confirmation ─────────────────────────────────────
        Write-Host ""
        Write-Host "[WARN] You are about to PERMANENTLY RELEASE Elastic IP $PublicIp ($AllocationId)." -ForegroundColor Red
        Write-Host "[WARN] This cannot be undone. The IP address will be returned to the AWS pool." -ForegroundColor Red
        Write-Host ""
        $typed = Read-Host "Type the public IP address '$PublicIp' to confirm release"

        if ($typed -ne $PublicIp) {
            Write-Host "[Remove-TaceElasticIp] Confirmation IP did not match. Operation cancelled." -ForegroundColor Yellow
            return [PSCustomObject]@{ Success = $false; Data = $null; Message = "Confirmation failed — typed '$typed', expected '$PublicIp'. Operation cancelled." }
        }

        # ── Check for existing association and disassociate ───────────────────
        Write-Verbose "[Remove-TaceElasticIp] Checking association state for $AllocationId"

        $descParams = @(
            'ec2', 'describe-addresses',
            '--allocation-ids', $AllocationId,
            '--region', $Region,
            '--profile', $Profile,
            '--query', 'Addresses[0].AssociationId',
            '--output', 'text'
        )
        $associationId = aws @descParams

        $wasAssociated = $false
        if ($associationId -and $associationId -ne 'None' -and $associationId -match '^eipassoc-') {
            Write-Verbose "[Remove-TaceElasticIp] Disassociating $AllocationId (AssociationId: $associationId)"
            $wasAssociated = $true

            $disassocParams = @(
                'ec2', 'disassociate-address',
                '--association-id', $associationId,
                '--region', $Region,
                '--profile', $Profile
            )
            $null = aws @disassocParams
            Write-Host "[Remove-TaceElasticIp] Disassociated EIP $PublicIp from instance." -ForegroundColor Cyan
        }

        # ── Release EIP ───────────────────────────────────────────────────────
        Write-Verbose "[Remove-TaceElasticIp] Releasing $AllocationId ($PublicIp) at $(Get-Date -Format 'u')"

        $releaseParams = @(
            'ec2', 'release-address',
            '--allocation-id', $AllocationId,
            '--region', $Region,
            '--profile', $Profile
        )
        $null = aws @releaseParams

        Write-Host "[Remove-TaceElasticIp] Released EIP $PublicIp ($AllocationId)." -ForegroundColor Green

        $msg = "Released Elastic IP $PublicIp ($AllocationId)"
        Write-Verbose "[Remove-TaceElasticIp] $msg"

        return [PSCustomObject]@{
            Success = $true
            Data    = [PSCustomObject]@{
                AllocationId  = $AllocationId
                PublicIp      = $PublicIp
                WasAssociated = $wasAssociated
            }
            Message = $msg
        }
    }
    catch {
        $errorMessage = $($_.Exception.Message)
        throw "Remove-TaceElasticIp failed: $errorMessage"
    }
}
