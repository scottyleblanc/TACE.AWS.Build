#Requires -Version 7.0

<#
.SYNOPSIS
    Post-build configuration steps for a TACE Linux EC2 instance.

.DESCRIPTION
    Runs post-build steps that should be executed once after a new Linux instance
    is provisioned via New-TaceInstance. Currently performs:

        1. Root volume resize — expands the EBS root volume to 30 GB and extends
           the XFS filesystem online (no reboot required).

    Additional post-build steps should be added here as new requirements emerge.

.PARAMETER InstanceName
    The logical instance name as defined in tace.aws.build.config.json (e.g. 'Linux').
    The instance ID is resolved from config automatically.

.PARAMETER VolumeSizeGB
    Target size in GB for the root EBS volume. Defaults to 30.

.PARAMETER Region
    AWS region of the target instance. Defaults to ca-central-1.

.PARAMETER AwsProfile
    AWS CLI named profile to use. Defaults to tace-aws-admin.

.PARAMETER CommandTimeoutSeconds
    Maximum seconds to wait per SSM step. Defaults to 120.

.EXAMPLE
    .\linux.post.build.ps1 -InstanceName Linux

.NOTES
    Requires: AWS CLI, SSM agent Online on the target instance.
    Instance name-to-ID mapping is maintained manually in config\tace.aws.build.config.json.
    Run this script once after New-TaceInstance completes.
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([PSCustomObject])]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $InstanceName,

    [Parameter()]
    [ValidateRange(10, 16384)]
    [int] $VolumeSizeGB = 30,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $Region = 'ca-central-1',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $AwsProfile = 'tace-aws-admin',

    [Parameter()]
    [ValidateRange(30, 600)]
    [int] $CommandTimeoutSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helper: assert AWS CLI is in PATH ─────────────────────────────────────────
function Assert-AwsCliAvailableLocal {
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        throw 'aws CLI not found in PATH. Install the AWS CLI v2 before running this script.'
    }
    Write-Verbose '[linux.post.build] aws CLI found.'
}

# ── Helper: send an SSM shell command and poll until complete ─────────────────
function Invoke-SsmShellCommand {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]   $StepName,
        [Parameter(Mandatory)] [string[]] $Commands,
        [Parameter(Mandatory)] [string]   $InstanceId,
        [Parameter(Mandatory)] [string]   $Region,
        [Parameter(Mandatory)] [string]   $AwsProfile,
        [Parameter()]          [int]      $TimeoutSeconds = 120,
        [Parameter()]          [int]      $PollIntervalSeconds = 5
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Host "[linux.post.build] [$StepName] Sending command to $InstanceId..." -ForegroundColor Cyan

    $tempFile  = Join-Path $env:TEMP "tace-ssm-$(New-Guid).json"
    $commandId = $null

    try {
        @{ commands = $Commands } | ConvertTo-Json -Depth 3 | Set-Content -Path $tempFile -Encoding UTF8

        $sendParams = @(
            'ssm', 'send-command',
            '--instance-ids', $InstanceId,
            '--document-name', 'AWS-RunShellScript',
            '--parameters', "file://$tempFile",
            '--timeout-seconds', $TimeoutSeconds.ToString(),
            '--region', $Region,
            '--profile', $AwsProfile,
            '--query', 'Command.CommandId',
            '--output', 'text'
        )
        $commandId = aws @sendParams
    }
    finally {
        if (Test-Path $tempFile) {
            Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Verbose "[linux.post.build] [$StepName] CommandId: $commandId"

    $elapsed = 0
    $status  = 'Pending'
    $result  = $null

    while ($status -in @('Pending', 'InProgress', 'Delayed')) {
        Start-Sleep -Seconds $PollIntervalSeconds
        $elapsed += $PollIntervalSeconds

        $pollParams = @(
            'ssm', 'get-command-invocation',
            '--command-id', $commandId,
            '--instance-id', $InstanceId,
            '--region', $Region,
            '--profile', $AwsProfile,
            '--query', '{Status:Status,StdOut:StandardOutputContent,StdErr:StandardErrorContent}',
            '--output', 'json'
        )

        try {
            $result = aws @pollParams | ConvertFrom-Json
            $status = $result.Status
            Write-Verbose "[linux.post.build] [$StepName] Status: $status (${elapsed}s elapsed)"
        }
        catch {
            Write-Verbose "[linux.post.build] [$StepName] Poll error (will retry): $($_.Exception.Message)"
        }

        if ($elapsed -ge $TimeoutSeconds) {
            throw "[$StepName] Timed out after $TimeoutSeconds seconds. Last status: $status"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($result.StdOut)) {
        Write-Host $result.StdOut -ForegroundColor DarkGray
    }
    if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) {
        Write-Host "[linux.post.build] [$StepName] stderr:" -ForegroundColor Yellow
        Write-Host $result.StdErr -ForegroundColor Yellow
    }

    if ($status -ne 'Success') {
        throw "[$StepName] SSM command completed with status '$status'. See output above."
    }

    Write-Host "[linux.post.build] [$StepName] Completed successfully." -ForegroundColor Green
    return $result
}

# ── Main ──────────────────────────────────────────────────────────────────────
try {
    Assert-AwsCliAvailableLocal

    # ── Resolve instance ID from Build config ──────────────────────────────────
    $buildConfigPath = Join-Path $PSScriptRoot '..' 'config' 'tace.aws.build.config.json'
    $buildConfig     = Get-Content -Path $buildConfigPath -Raw | ConvertFrom-Json
    $instanceId      = $buildConfig.Instances.$InstanceName

    if ([string]::IsNullOrWhiteSpace($instanceId)) {
        $available = ($buildConfig.Instances.PSObject.Properties.Name) -join ', '
        throw "Instance name '$InstanceName' not found in tace.aws.build.config.json. Available: $available"
    }

    Write-Verbose "[linux.post.build] Resolved '$InstanceName' to $instanceId"

    if (-not $PSCmdlet.ShouldProcess("$InstanceName ($instanceId)", 'Run Linux post-build steps')) {
        return [PSCustomObject]@{ Success = $false; Data = $null; Message = 'Operation cancelled by user.' }
    }

    # ── Confirm instance is SSM Online ─────────────────────────────────────────
    Write-Host "[linux.post.build] Checking SSM status for $InstanceName ($instanceId)..." -ForegroundColor Cyan

    $ssmCheckParams = @(
        'ssm', 'describe-instance-information',
        '--filters', "Key=InstanceIds,Values=$instanceId",
        '--region', $Region,
        '--profile', $AwsProfile,
        '--query', 'InstanceInformationList[0].PingStatus',
        '--output', 'text'
    )
    $pingStatus = aws @ssmCheckParams

    if ($pingStatus -ne 'Online') {
        throw "$InstanceName ($instanceId) is not SSM Online (PingStatus: $pingStatus). Start the instance and ensure the SSM agent is running before retrying."
    }

    Write-Host "[linux.post.build] $InstanceName ($instanceId) is SSM Online." -ForegroundColor Green

    # ── Step 1: Resize root EBS volume ────────────────────────────────────────
    Write-Host "[linux.post.build] [VolumeResize] Fetching root volume ID..." -ForegroundColor Cyan

    $volParams = @(
        'ec2', 'describe-instances',
        '--instance-ids', $instanceId,
        '--region', $Region,
        '--profile', $AwsProfile,
        '--query', 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId',
        '--output', 'text'
    )
    $volumeId = aws @volParams

    Write-Verbose "[linux.post.build] [VolumeResize] Root volume: $volumeId"

    $modifyParams = @(
        'ec2', 'modify-volume',
        '--volume-id', $volumeId,
        '--size', $VolumeSizeGB.ToString(),
        '--region', $Region,
        '--profile', $AwsProfile,
        '--query', 'VolumeModification.ModificationState',
        '--output', 'text'
    )
    $modState = aws @modifyParams
    Write-Host "[linux.post.build] [VolumeResize] Volume $volumeId modification state: $modState" -ForegroundColor Cyan

    # Poll until the EBS modification is complete (optimizing -> completed)
    $elapsed = 0
    while ($modState -notin @('completed', 'failed')) {
        Start-Sleep -Seconds 5
        $elapsed += 5

        $stateParams = @(
            'ec2', 'describe-volumes-modifications',
            '--volume-ids', $volumeId,
            '--region', $Region,
            '--profile', $AwsProfile,
            '--query', 'VolumesModifications[0].ModificationState',
            '--output', 'text'
        )
        $modState = aws @stateParams
        Write-Verbose "[linux.post.build] [VolumeResize] Modification state: $modState (${elapsed}s)"

        if ($elapsed -ge 120) {
            throw "[VolumeResize] EBS volume modification did not complete within 120 seconds."
        }
    }

    if ($modState -eq 'failed') {
        throw "[VolumeResize] EBS volume modification failed for $volumeId."
    }

    Write-Host "[linux.post.build] [VolumeResize] EBS volume resized to ${VolumeSizeGB}GB." -ForegroundColor Green

    # ── Step 2: Extend partition and filesystem on the instance ───────────────
    Invoke-SsmShellCommand -StepName 'GrowFilesystem' -Commands @(
        'sudo growpart /dev/nvme0n1 1'
        'sudo xfs_growfs /'
        'df -h /'
    ) -InstanceId $instanceId -Region $Region -AwsProfile $AwsProfile -TimeoutSeconds $CommandTimeoutSeconds

    # ── Step 3: Install PowerShell ────────────────────────────────────────────
    Invoke-SsmShellCommand -StepName 'InstallPowerShell' -Commands @(
        'sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc'
        'curl -sSL https://packages.microsoft.com/config/rhel/9/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo'
        'sudo dnf install -y powershell'
        'pwsh --version'
    ) -InstanceId $instanceId -Region $Region -AwsProfile $AwsProfile -TimeoutSeconds $CommandTimeoutSeconds

    # ── Step 4: Install Pester 5.x ────────────────────────────────────────────
    Invoke-SsmShellCommand -StepName 'InstallPester' -Commands @(
        'pwsh -Command "Install-Module Pester -MinimumVersion 5.0 -Force -Scope CurrentUser"'
        'pwsh -Command "Import-Module Pester; (Get-Module Pester).Version.ToString()"'
    ) -InstanceId $instanceId -Region $Region -AwsProfile $AwsProfile -TimeoutSeconds $CommandTimeoutSeconds

    # ── Step 5: Install AWS CLI v2 ────────────────────────────────────────────
    Invoke-SsmShellCommand -StepName 'InstallAwsCli' -Commands @(
        'curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip'
        'unzip -q /tmp/awscliv2.zip -d /tmp'
        'sudo /tmp/aws/install'
        'rm -rf /tmp/awscliv2.zip /tmp/aws'
        'aws --version'
    ) -InstanceId $instanceId -Region $Region -AwsProfile $AwsProfile -TimeoutSeconds $CommandTimeoutSeconds

    $msg = "Post-build steps completed for $InstanceName ($instanceId)"
    Write-Verbose "[linux.post.build] $msg at $(Get-Date -Format 'u')"
    Write-Host "[linux.post.build] [DONE] $msg" -ForegroundColor Green

    return [PSCustomObject]@{
        Success = $true
        Data    = [PSCustomObject]@{
            InstanceName = $InstanceName
            InstanceId   = $instanceId
            VolumeId     = $volumeId
            VolumeSizeGB = $VolumeSizeGB
        }
        Message = $msg
    }
}
catch {
    throw "linux.post.build failed: $($_.Exception.Message)"
}
