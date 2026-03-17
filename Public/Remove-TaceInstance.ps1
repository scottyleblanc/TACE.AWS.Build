#Requires -Version 7.0

function Remove-TaceInstance {
    <#
    .SYNOPSIS
        Terminates a TACE EC2 instance. This action is irreversible.

    .DESCRIPTION
        Terminates the specified EC2 instance after two confirmation gates:
          1. PowerShell SupportsShouldProcess (-WhatIf / -Confirm)
          2. Typed instance name confirmation — the caller must type the exact
             instance name to proceed.

        This function terminates the instance only. Elastic IPs associated with
        the instance are NOT released — use Remove-TaceElasticIp separately to
        avoid ongoing EIP charges.

    .PARAMETER InstanceId
        The EC2 instance ID to terminate (e.g. i-0e2007838d8464bff).

    .PARAMETER InstanceName
        The human-readable name of the instance (e.g. tace-linux-02). Used only
        for confirmation prompts and log messages — not passed to AWS directly.

    .PARAMETER Region
        AWS region the instance resides in. Defaults to config DefaultRegion.

    .PARAMETER Profile
        AWS CLI profile to use. Defaults to config DefaultProfile.

    .EXAMPLE
        Remove-TaceInstance -InstanceId i-0e2007838d8464bff -InstanceName tace-linux-02

        Prompts for typed confirmation, then terminates the instance.

    .EXAMPLE
        Remove-TaceInstance -InstanceId i-0e2007838d8464bff -InstanceName tace-linux-02 -WhatIf

        Shows what would be terminated without executing.

    .OUTPUTS
        PSCustomObject — Success, Data (InstanceId, PreviousState, CurrentState), Message.

    .NOTES
        [SEC] InstanceId is validated against AWS instance ID format before use.
        This function does NOT release Elastic IPs. Run Remove-TaceElasticIp after
        termination to avoid ongoing EIP charges ($0.005/hr per unassociated EIP).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [ValidatePattern('^i-[0-9a-f]{8,17}$')]
        [string] $InstanceId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $InstanceName,

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
        if (-not $PSCmdlet.ShouldProcess($InstanceId, "TERMINATE EC2 instance '$InstanceName' — this is irreversible")) {
            return [PSCustomObject]@{ Success = $false; Data = $null; Message = 'Operation cancelled.' }
        }

        # ── Gate 2: Typed name confirmation ──────────────────────────────────
        Write-Host ""
        Write-Host "[WARN] You are about to PERMANENTLY TERMINATE EC2 instance '$InstanceName' ($InstanceId)." -ForegroundColor Red
        Write-Host "[WARN] This cannot be undone. The instance and its local storage will be destroyed." -ForegroundColor Red
        Write-Host "[WARN] Elastic IPs are NOT released by this command — run Remove-TaceElasticIp separately." -ForegroundColor Yellow
        Write-Host ""
        $typed = Read-Host "Type the instance name '$InstanceName' to confirm termination"

        if ($typed -ne $InstanceName) {
            Write-Host "[New-TaceInstance] Confirmation name did not match. Operation cancelled." -ForegroundColor Yellow
            return [PSCustomObject]@{ Success = $false; Data = $null; Message = "Confirmation failed — typed '$typed', expected '$InstanceName'. Operation cancelled." }
        }

        # ── Terminate ─────────────────────────────────────────────────────────
        Write-Verbose "[Remove-TaceInstance] Terminating $InstanceName ($InstanceId) at $(Get-Date -Format 'u')"

        $terminateParams = @(
            'ec2', 'terminate-instances',
            '--instance-ids', $InstanceId,
            '--region', $Region,
            '--profile', $Profile,
            '--query', 'TerminatingInstances[0].{ID:InstanceId,Prev:PreviousState.Name,Curr:CurrentState.Name}',
            '--output', 'json'
        )
        $result = aws @terminateParams | ConvertFrom-Json

        Write-Host "[Remove-TaceInstance] $InstanceName ($InstanceId): $($result.Prev) -> $($result.Curr)" -ForegroundColor Green

        $msg = "Terminated $InstanceName ($InstanceId): $($result.Prev) -> $($result.Curr)"
        Write-Verbose "[Remove-TaceInstance] $msg"

        return [PSCustomObject]@{
            Success = $true
            Data    = [PSCustomObject]@{
                InstanceId    = $result.ID
                InstanceName  = $InstanceName
                PreviousState = $result.Prev
                CurrentState  = $result.Curr
            }
            Message = $msg
        }
    }
    catch {
        $errorMessage = $($_.Exception.Message)
        throw "Remove-TaceInstance failed: $errorMessage"
    }
}
