#Requires -Version 7.0

function New-TaceInstance {
    <#
    .SYNOPSIS
        Launches a new TACE EC2 instance from a named AWS Launch Template profile.

    .DESCRIPTION
        Resolves the named profile to an AWS Launch Template ID, launches a new EC2
        instance, waits for it to reach running state, allocates a new Elastic IP,
        associates the EIP with the instance, and optionally updates the TACE.AWS.Run
        module config with the new instance details.

        Instance names follow the pattern {ProfileName}-{NN} (e.g. tace-linux-02).
        The number auto-increments from the highest existing instance of that profile,
        or can be overridden with -InstanceNumber.

    .PARAMETER ProfileName
        The named launch template profile to use (e.g. 'tace-linux', 'tace-windows').
        Must match a key under LaunchTemplates in tace.aws.build.config.json.

    .PARAMETER InstanceNumber
        Optional. Override the auto-incremented instance number. Must be a positive
        integer. If omitted, the next available number is determined automatically.

    .PARAMETER Wait
        When specified, waits for the instance to reach running state and SSM Online
        status before returning. Recommended — EIP association requires running state.

    .PARAMETER MaxWaitSeconds
        Maximum number of seconds to wait when -Wait is specified. Defaults to 300.

    .PARAMETER Region
        AWS region to launch the instance in. Defaults to config DefaultRegion.

    .PARAMETER Profile
        AWS CLI profile to use. Defaults to config DefaultProfile.

    .EXAMPLE
        New-TaceInstance -ProfileName tace-linux -Wait

        Launches the next tace-linux instance (e.g. tace-linux-02), waits until
        running and SSM Online, allocates and associates an Elastic IP.

    .EXAMPLE
        New-TaceInstance -ProfileName tace-windows -InstanceNumber 3 -Wait

        Launches tace-windows-03 from the tace-windows Launch Template.

    .OUTPUTS
        PSCustomObject — Success, Data (InstanceId, InstanceName, ElasticIp,
        AllocationId, PublicDnsName), Message.

    .NOTES
        [SEC] Launch Template ID is read from config only — never from user input.
        [SEC] No credentials or sensitive values are written to Message or Verbose output.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ProfileName,

        [Parameter()]
        [ValidateRange(1, 99)]
        [int] $InstanceNumber,

        [Parameter()]
        [switch] $Wait,

        [Parameter()]
        [ValidateRange(30, 600)]
        [int] $MaxWaitSeconds = 300,

        [Parameter()]
        [string] $Region = $script:DefaultRegion,

        [Parameter()]
        [string] $Profile = $script:DefaultProfile
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    try {
        Assert-AwsCliAvailable
        $template = Get-TaceLaunchTemplate -ProfileName $ProfileName

        # ── Resolve instance name ─────────────────────────────────────────────
        if (-not $PSBoundParameters.ContainsKey('InstanceNumber')) {
            $listParams = @(
                'ec2', 'describe-instances',
                '--filters',
                    "Name=tag:Name,Values=$ProfileName-*",
                    'Name=instance-state-name,Values=running,stopped,stopping,pending',
                '--region', $Region,
                '--profile', $Profile,
                '--query', 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value',
                '--output', 'json'
            )
            $existingNames = @(aws @listParams | ConvertFrom-Json | ForEach-Object { $_ } | ForEach-Object { $_ })
            $existingNumbers = @($existingNames | Where-Object { $_ -match "-(\d+)$" } | ForEach-Object {
                [int]($Matches[1])
            })
            $InstanceNumber = if ($existingNumbers.Count -gt 0) { ($existingNumbers | Measure-Object -Maximum).Maximum + 1 } else { 1 }
        }

        $instanceName = '{0}-{1:D2}' -f $ProfileName, $InstanceNumber
        Write-Verbose "[New-TaceInstance] Resolved instance name: $instanceName"

        if (-not $PSCmdlet.ShouldProcess($instanceName, 'Launch EC2 instance from Launch Template')) {
            return [PSCustomObject]@{ Success = $false; Data = $null; Message = 'Operation cancelled by user.' }
        }

        # ── Launch instance ───────────────────────────────────────────────────
        Write-Verbose "[New-TaceInstance] Launching $instanceName from template $($template.TemplateId)"

        $launchParams = @(
            'ec2', 'run-instances',
            '--launch-template', "LaunchTemplateId=$($template.TemplateId)",
            '--tag-specifications', "ResourceType=instance,Tags=[{Key=Name,Value=$instanceName}]",
            '--region', $Region,
            '--profile', $Profile,
            '--query', 'Instances[0].{InstanceId:InstanceId,State:State.Name}',
            '--output', 'json'
        )
        $launched = aws @launchParams | ConvertFrom-Json
        $instanceId = $launched.InstanceId
        Write-Host "[New-TaceInstance] Launched $instanceName ($instanceId) — state: $($launched.State)" -ForegroundColor Cyan

        # ── Wait for running + SSM Online ─────────────────────────────────────
        if ($Wait) {
            Write-Host "[New-TaceInstance] Waiting for $instanceId to be running and Online in SSM..." -ForegroundColor DarkGray
            $elapsed = 0
            $ready   = $false

            while (-not $ready -and $elapsed -lt $MaxWaitSeconds) {
                Start-Sleep -Seconds 10
                $elapsed += 10

                try {
                    $stateParams = @(
                        'ec2', 'describe-instances',
                        '--instance-ids', $instanceId,
                        '--region', $Region,
                        '--profile', $Profile,
                        '--query', 'Reservations[0].Instances[0].State.Name',
                        '--output', 'text'
                    )
                    $state = aws @stateParams

                    if ($state -eq 'running') {
                        $ssmParams = @(
                            'ssm', 'describe-instance-information',
                            '--filters', "Key=InstanceIds,Values=$instanceId",
                            '--region', $Region,
                            '--profile', $Profile,
                            '--query', 'InstanceInformationList[0].PingStatus',
                            '--output', 'text'
                        )
                        $ssmStatus = aws @ssmParams
                        if ($ssmStatus -eq 'Online') {
                            $ready = $true
                            Write-Host "[New-TaceInstance] $instanceId is running and Online in SSM." -ForegroundColor Green
                        }
                        else {
                            Write-Verbose "[New-TaceInstance] $instanceId running, SSM: $ssmStatus (${elapsed}s)"
                        }
                    }
                    else {
                        Write-Verbose "[New-TaceInstance] $instanceId state: $state (${elapsed}s)"
                    }
                }
                catch {
                    Write-Verbose "[New-TaceInstance] Polling error (will retry): $($_.Exception.Message)"
                }
            }

            if (-not $ready) {
                Write-Warning "[New-TaceInstance] $instanceId did not reach Online within $MaxWaitSeconds seconds. EIP will still be allocated."
            }
        }

        # ── Allocate Elastic IP ───────────────────────────────────────────────
        Write-Verbose "[New-TaceInstance] Allocating Elastic IP for $instanceName"

        $allocParams = @(
            'ec2', 'allocate-address',
            '--domain', 'vpc',
            '--tag-specifications', "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$instanceName-eip}]",
            '--region', $Region,
            '--profile', $Profile,
            '--query', '{PublicIp:PublicIp,AllocationId:AllocationId}',
            '--output', 'json'
        )
        $eip = aws @allocParams | ConvertFrom-Json
        Write-Host "[New-TaceInstance] Allocated EIP $($eip.PublicIp) ($($eip.AllocationId))" -ForegroundColor Cyan

        # ── Associate EIP ─────────────────────────────────────────────────────
        Write-Verbose "[New-TaceInstance] Associating EIP with $instanceId"

        $assocParams = @(
            'ec2', 'associate-address',
            '--instance-id', $instanceId,
            '--allocation-id', $eip.AllocationId,
            '--region', $Region,
            '--profile', $Profile,
            '--output', 'json'
        )
        $null = aws @assocParams
        Write-Host "[New-TaceInstance] EIP $($eip.PublicIp) associated with $instanceName." -ForegroundColor Green

        # ── Prompt to update TACE.AWS.Run config ──────────────────────────────
        $runConfigPath = Join-Path $PSScriptRoot '..' $script:Config.RunModuleConfigPath
        $runConfigPath = [System.IO.Path]::GetFullPath($runConfigPath)

        if (Test-Path $runConfigPath) {
            $updatePrompt = "Update TACE.AWS.Run config at '$runConfigPath' to include $instanceName ($instanceId)? [Y/N]"
            $answer = Read-Host $updatePrompt

            if ($answer -match '^[Yy]') {
                $runConfig    = Get-Content $runConfigPath -Raw | ConvertFrom-Json
                $backupPath   = $runConfigPath -replace '\.json$', (".backup.{0}.json" -f (Get-Date -Format 'yyyyMMddHHmmss'))
                Copy-Item -Path $runConfigPath -Destination $backupPath
                Write-Host "[New-TaceInstance] Backup saved: $backupPath" -ForegroundColor DarkGray

                $runConfig.Instances | Add-Member -MemberType NoteProperty -Name $instanceName -Value $instanceId -Force
                $runConfig | ConvertTo-Json -Depth 5 | Set-Content -Path $runConfigPath -Encoding UTF8
                Write-Host "[New-TaceInstance] TACE.AWS.Run config updated." -ForegroundColor Green
            }
            else {
                Write-Host "[New-TaceInstance] Config not updated. Add manually: `"$instanceName`": `"$instanceId`"" -ForegroundColor Yellow
            }
        }
        else {
            Write-Warning "[New-TaceInstance] TACE.AWS.Run config not found at expected path: $runConfigPath"
            Write-Host "[New-TaceInstance] Add manually: `"$instanceName`": `"$instanceId`"" -ForegroundColor Yellow
        }

        $msg = "Launched $instanceName ($instanceId) with EIP $($eip.PublicIp)"
        Write-Verbose "[New-TaceInstance] $msg at $(Get-Date -Format 'u')"

        return [PSCustomObject]@{
            Success = $true
            Data    = [PSCustomObject]@{
                InstanceId   = $instanceId
                InstanceName = $instanceName
                ElasticIp    = $eip.PublicIp
                AllocationId = $eip.AllocationId
            }
            Message = $msg
        }
    }
    catch {
        $errorMessage = $($_.Exception.Message)
        throw "New-TaceInstance failed: $errorMessage"
    }
}
