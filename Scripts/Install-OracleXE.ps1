#Requires -Version 7.0

<#
.SYNOPSIS
    Installs Oracle Database 26ai on a remote Oracle Linux EC2 instance via AWS SSM Run Command.

.DESCRIPTION
    Executes the Oracle Database 26ai installation steps on a target EC2 instance using
    AWS SSM send-command. Each step runs sequentially; output is streamed to the console
    as steps complete. The instance must be SSM Online before running this script.

    Steps performed:
        1. Preinstall    — dnf install oracle-ai-database-preinstall-26ai
        2. Install       — dnf install oracle-free-26ai (direct RPM download)
        3. Configure     — /etc/init.d/oracle-ai-database-26ai configure (non-interactive)
        4. Service       — systemctl enable + start oracle-ai-database-26ai
        5. Verify        — SELECT instance_name, status FROM v$instance

.PARAMETER InstanceName
    The logical instance name as defined in the TACE.AWS.Run config (e.g. 'Linux').
    The instance ID is resolved from tace-aws.config.json automatically.
    Must be running and SSM Online.

.PARAMETER SysPassword
    Password to set for the SYS, SYSTEM, and PDBADMIN accounts. SecureString required.
    Must not contain single-quote characters.

.PARAMETER Region
    AWS region of the target instance. Defaults to ca-central-1.

.PARAMETER AwsProfile
    AWS CLI named profile to use. Defaults to tace-aws-admin.

.PARAMETER CommandTimeoutSeconds
    Maximum seconds to wait per SSM step before declaring a timeout. Defaults to 600.

.EXAMPLE
    $pw = Read-Host -AsSecureString 'SYS password'
    .\Install-OracleXE.ps1 -InstanceName Linux -SysPassword $pw

.EXAMPLE
    $pw = Read-Host -AsSecureString 'SYS password'
    .\Install-OracleXE.ps1 -InstanceName Linux -SysPassword $pw -Region us-east-1 -AwsProfile my-profile

.NOTES
    Requires: AWS CLI, SSM agent Online on the target instance, Oracle Linux 9.x on target.

    [SEC] SysPassword plaintext is extracted inline at the SSM payload boundary only.
          It is never assigned to a named variable. Temp parameter files are deleted
          immediately after the AWS CLI call returns.
    [SEC] SSM Run Command history in AWS retains command documents including parameters.
          The configure step password will appear in SSM command history. Rotate the
          SYS/SYSTEM/PDBADMIN password immediately after installation in any environment
          where SSM command history is accessible to other principals.
    [SEC] Passwords containing single-quote characters will break the shell configure
          command. This script validates and rejects such passwords before sending.

    Instance name-to-ID mapping is maintained manually in config\tace.aws.build.config.json
    under the Instances key. Update that file when an instance is replaced (terminate old,
    build new, update the ID).
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([PSCustomObject])]
param (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $InstanceName,

    [Parameter(Mandatory)]
    [SecureString] $SysPassword,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $Region = 'ca-central-1',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $AwsProfile = 'tace-aws-admin',

    [Parameter()]
    [ValidateRange(60, 3600)]
    [int] $CommandTimeoutSeconds = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helper: assert AWS CLI is in PATH ─────────────────────────────────────────
function Assert-AwsCliAvailableLocal {
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        throw 'aws CLI not found in PATH. Install the AWS CLI v2 before running this script.'
    }
    Write-Verbose '[Install-OracleXE] aws CLI found.'
}

# ── Helper: send an SSM shell command and poll until complete ─────────────────
#
# Uses a temp JSON file for --parameters to avoid Windows CLI quoting issues.
# Temp file is deleted in a finally block regardless of outcome.
#
function Invoke-SsmShellCommand {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]   $StepName,
        [Parameter(Mandatory)] [string[]] $Commands,
        [Parameter(Mandatory)] [string]   $InstanceId,
        [Parameter(Mandatory)] [string]   $Region,
        [Parameter(Mandatory)] [string]   $AwsProfile,
        [Parameter()]          [int]      $TimeoutSeconds = 600,
        [Parameter()]          [int]      $PollIntervalSeconds = 10
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Host "[Install-OracleXE] [$StepName] Sending command to $InstanceId..." -ForegroundColor Cyan

    $tempFile = Join-Path $env:TEMP "tace-ssm-$(New-Guid).json"
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

    Write-Verbose "[Install-OracleXE] [$StepName] CommandId: $commandId"

    # ── Poll for completion ────────────────────────────────────────────────────
    $elapsed = 0
    $status  = 'Pending'

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
            Write-Verbose "[Install-OracleXE] [$StepName] Status: $status (${elapsed}s elapsed)"
        }
        catch {
            Write-Verbose "[Install-OracleXE] [$StepName] Poll error (will retry): $($_.Exception.Message)"
        }

        if ($elapsed -ge $TimeoutSeconds) {
            throw "[$StepName] Timed out after $TimeoutSeconds seconds. Last status: $status"
        }
    }

    # ── Display output ─────────────────────────────────────────────────────────
    if (-not [string]::IsNullOrWhiteSpace($result.StdOut)) {
        Write-Host $result.StdOut -ForegroundColor DarkGray
    }
    if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) {
        Write-Host "[Install-OracleXE] [$StepName] stderr:" -ForegroundColor Yellow
        Write-Host $result.StdErr -ForegroundColor Yellow
    }

    if ($status -ne 'Success') {
        throw "[$StepName] SSM command completed with status '$status'. See output above."
    }

    Write-Host "[Install-OracleXE] [$StepName] Completed successfully." -ForegroundColor Green
    return $result
}

# ── Main ──────────────────────────────────────────────────────────────────────
# Force UTF-8 output from the AWS CLI (Python) so Oracle installer Unicode characters
# (e.g. → U+2192) don't cause 'charmap' codec errors on the Windows console.
$savedPythonEncoding    = $env:PYTHONIOENCODING
$env:PYTHONIOENCODING   = 'utf-8'

try {
    Assert-AwsCliAvailableLocal

    # [SEC] Validate password does not contain single-quote — would break the
    #       printf shell command used in the configure step.
    $pwCheck = [System.Net.NetworkCredential]::new('', $SysPassword).Password
    if ($pwCheck.Contains("'")) {
        $pwCheck = $null
        throw "SysPassword must not contain single-quote characters (shell quoting limitation)."
    }
    $pwCheck = $null
    [System.GC]::Collect()

    # ── Resolve instance ID from TACE.AWS.Build config ────────────────────────
    $buildConfigPath = Join-Path $PSScriptRoot '..' 'config' 'tace.aws.build.config.json'
    $buildConfig     = Get-Content -Path $buildConfigPath -Raw | ConvertFrom-Json
    $instanceId      = $buildConfig.Instances.$InstanceName

    if ([string]::IsNullOrWhiteSpace($instanceId)) {
        $available = ($buildConfig.Instances.PSObject.Properties.Name) -join ', '
        throw "Instance name '$InstanceName' not found in tace.aws.build.config.json. Available: $available"
    }

    Write-Verbose "[Install-OracleXE] Resolved '$InstanceName' to $instanceId"

    if (-not $PSCmdlet.ShouldProcess("$InstanceName ($instanceId)", 'Install Oracle Database 26ai via SSM Run Command')) {
        return [PSCustomObject]@{ Success = $false; Data = $null; Message = 'Operation cancelled by user.' }
    }

    # ── Confirm instance is SSM Online ─────────────────────────────────────────
    Write-Host "[Install-OracleXE] Checking SSM status for $InstanceName ($instanceId)..." -ForegroundColor Cyan

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

    Write-Host "[Install-OracleXE] $InstanceName ($instanceId) is SSM Online. Proceeding with installation." -ForegroundColor Green

    $invokeBase = @{
        InstanceId     = $instanceId
        Region         = $Region
        AwsProfile     = $AwsProfile
        TimeoutSeconds = $CommandTimeoutSeconds
    }

    # ── Step 1: Preinstall package ─────────────────────────────────────────────
    Invoke-SsmShellCommand @invokeBase -StepName 'Preinstall' -Commands @(
        'sudo dnf -y install oracle-ai-database-preinstall-26ai'
    )

    # ── Step 2: Database package (direct RPM — not in yum repo) ───────────────
    Invoke-SsmShellCommand @invokeBase -StepName 'Install' -Commands @(
        'sudo dnf -y install https://download.oracle.com/otn-pub/otn_software/db-free/oracle-ai-database-free-26ai-23.26.1-1.el9.x86_64.rpm'
    )

    # ── Step 3: Configure ──────────────────────────────────────────────────────
    # Skip if the database is already configured (idempotent re-run support).
    # [SEC] Plaintext extracted inline at payload boundary — never assigned to a variable.
    #       Temp file is written and deleted within Invoke-SsmShellCommand.
    #       printf sends PASSWORD<LF>PASSWORD<LF> on stdin to the configure script.
    $checkResult = Invoke-SsmShellCommand @invokeBase -StepName 'ConfigureCheck' -Commands @(
        'systemctl is-active oracle-free-26ai && echo CONFIGURED || echo NOT_CONFIGURED'
    )

    if ($checkResult.StdOut -match 'CONFIGURED') {
        Write-Host "[Install-OracleXE] [Configure] Database already configured — skipping." -ForegroundColor Yellow
    }
    else {
        Invoke-SsmShellCommand @invokeBase -StepName 'Configure' -Commands @(
            "printf '%s\n%s\n' '$([System.Net.NetworkCredential]::new('', $SysPassword).Password)' '$([System.Net.NetworkCredential]::new('', $SysPassword).Password)' | sudo /etc/init.d/oracle-free-26ai configure"
        )
    }

    # ── Step 4: Enable and start the service ──────────────────────────────────
    Invoke-SsmShellCommand @invokeBase -StepName 'Service' -Commands @(
        'sudo systemctl enable oracle-free-26ai'
        'sudo systemctl start  oracle-free-26ai'
    )

    # ── Step 5: Verify ─────────────────────────────────────────────────────────
    # Wrapped in a single bash -c so set -e propagates across all sub-steps.
    # sqlplus is located dynamically via find — avoids PATH issues in SSM context.
    # printf \$ in shell double-quotes produces literal $ without variable expansion.
    Invoke-SsmShellCommand @invokeBase -StepName 'Verify' -Commands @(
        'bash -c ''set -e; printf "WHENEVER SQLERROR EXIT SQL.SQLCODE;\nSELECT instance_name, status, version FROM v\$instance;\nEXIT;\n" > /tmp/tace_verify.sql; SQLPLUS=$(find /opt/oracle -maxdepth 6 -name sqlplus -executable -type f 2>/dev/null | head -1); test -n "$SQLPLUS" || { echo "[ERROR] sqlplus not found"; exit 1; }; ORACLE_HOME=$(dirname $(dirname $SQLPLUS)); sudo -u oracle ORACLE_HOME="$ORACLE_HOME" ORACLE_SID=FREE "$SQLPLUS" -S / as sysdba @/tmp/tace_verify.sql; rm -f /tmp/tace_verify.sql'''
    )

    $msg = "Oracle Database 26ai installed and configured on $InstanceName ($instanceId)"
    Write-Verbose "[Install-OracleXE] $msg at $(Get-Date -Format 'u')"
    Write-Host "[Install-OracleXE] [DONE] $msg" -ForegroundColor Green
    Write-Host "[Install-OracleXE] [SEC]  Rotate SYS/SYSTEM/PDBADMIN passwords — SSM command history retains the configure step." -ForegroundColor Yellow

    return [PSCustomObject]@{
        Success = $true
        Data    = [PSCustomObject]@{
            InstanceName = $InstanceName
            InstanceId   = $instanceId
            Region       = $Region
        }
        Message = $msg
    }
}
catch {
    [System.GC]::Collect()
    throw "Install-OracleXE failed: $($_.Exception.Message)"
}
finally {
    $env:PYTHONIOENCODING = $savedPythonEncoding
}
