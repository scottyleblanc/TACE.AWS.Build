# TACE.AWS.Build

PowerShell module for EC2 instance and Elastic IP lifecycle management via AWS Launch Templates.
Build new instances from named profiles and safely tear them down.

> **Module family:** `TACE.AWS.Build` handles infrastructure lifecycle (create, destroy).
> Day-to-day instance operations (start, stop, connect, status) are handled by the
> companion module `TACE.AWS.Run`.

---

## Prerequisites

See [PREREQUISITES.md](PREREQUISITES.md) for full requirements. Summary:
- PowerShell 7.0+
- AWS CLI v2
- IAM Identity Center (SSO) configured with profile `tace-aws-admin`
- AWS Launch Templates created for each instance profile (see Configuration below)

---

## Installation

```powershell
Import-Module .\TACE.AWS.Build.psd1
```

Or add to your PowerShell profile:

```powershell
Import-Module (Join-Path $HOME 'dev\TACE\repos\TACE.AWS.Build\TACE.AWS.Build.psd1') -ErrorAction Stop
```

---

## Functions

| Function | Description |
|---|---|
| `New-TaceInstance` | Launch a new EC2 instance from a named Launch Template profile, allocate and associate an Elastic IP |
| `Remove-TaceInstance` | Terminate an EC2 instance (irreversible, double-gated) |
| `Remove-TaceElasticIp` | Disassociate and release an Elastic IP (irreversible, double-gated) |

---

## Quick Start

```powershell
# Launch a second Linux instance (auto-names it tace-linux-02)
New-TaceInstance -ProfileName tace-linux -Wait

# Launch a specific instance number
New-TaceInstance -ProfileName tace-windows -InstanceNumber 3 -Wait

# Dry-run teardown — see what would be done
Remove-TaceInstance -InstanceId i-0abc123 -InstanceName tace-linux-02 -WhatIf
Remove-TaceElasticIp -AllocationId eipalloc-0abc123 -PublicIp 15.157.x.x -WhatIf

# Actual teardown — requires typed confirmation at each step
Remove-TaceInstance -InstanceId i-0abc123 -InstanceName tace-linux-02
Remove-TaceElasticIp -AllocationId eipalloc-0abc123 -PublicIp 15.157.x.x
```

---

## Configuration

### Module config — `config/tace.aws.build.config.json`

```json
{
    "DefaultRegion": "ca-central-1",
    "DefaultProfile": "tace-aws-admin",
    "RunModuleConfigPath": "..\\TACE.AWS.Run\\config\\tace-aws.config.json",
    "LaunchTemplates": {
        "tace-linux": {
            "TemplateId": "lt-PLACEHOLDER",
            "TemplateName": "tace-linux",
            "Description": "Oracle Linux 9, t3.medium"
        },
        "tace-windows": {
            "TemplateId": "lt-PLACEHOLDER",
            "TemplateName": "tace-windows",
            "Description": "Windows Server 2022, t3.medium"
        }
    }
}
```

Before `New-TaceInstance` will work, replace each `lt-PLACEHOLDER` with the actual AWS
Launch Template ID (format: `lt-xxxxxxxxxxxxxxxxx`). See PREREQUISITES.md for how to
create Launch Templates in AWS.

### Instance naming

New instances are named `{ProfileName}-{NN}` where `NN` auto-increments from the highest
existing instance of that profile. Override with `-InstanceNumber`.

| Example call | Instance name |
|---|---|
| `New-TaceInstance -ProfileName tace-linux` (first) | `tace-linux-01` |
| `New-TaceInstance -ProfileName tace-linux` (second) | `tace-linux-02` |
| `New-TaceInstance -ProfileName tace-linux -InstanceNumber 5` | `tace-linux-05` |

---

## Output Contract

All public functions return:

```powershell
[PSCustomObject]@{
    Success = [bool]
    Data    = $null | [PSCustomObject]   # payload — see per-function docs
    Message = [string]                   # always safe to log
}
```

---

## Teardown Order

When removing an instance and its EIP, always terminate the instance first:

1. `Remove-TaceInstance` — terminates the instance
2. `Remove-TaceElasticIp` — releases the EIP

Releasing the EIP before termination will leave the instance running without a
persistent IP, and the EIP cannot be re-associated after release.

---

## Design Decision — AWS Launch Templates

This module uses AWS Launch Templates (native AWS feature, no cost) rather than
local JSON template files. Rationale:

- Launch Templates are versioned natively in AWS — full change history
- Visible and launchable from the AWS Console as a fallback
- No dependency on local config for instance spec — spec lives in AWS
- Enables future Auto Scaling Group integration if needed
- Keeps PowerShell code focused on orchestration, not instance spec management

The module stores only the Launch Template **ID reference** in local config. All instance
spec (AMI, instance type, security groups, IAM profile, etc.) is managed in the Launch
Template itself via the AWS Console or CLI.

TODO: `New-TaceLaunchTemplate` — generate a new AWS Launch Template from a local profile
definition (future feature, see TODO.md).

---

## Current Security State

**Last reviewed:** 2026-03-16 | **Version:** 0.1.0

- All destructive operations require `-WhatIf`-compatible SupportsShouldProcess + typed confirmation
- Launch Template IDs are read from config only — never from user input
- No credentials or sensitive values in `Message`, `Verbose` output, or `ArgumentList`
- `[SEC]` tagged items in source mark all security requirements

---

## Module Structure

```
TACE.AWS.Build/
  TACE.AWS.Build.psd1         # Module manifest
  TACE.AWS.Build.psm1         # Root module — loads config, private/public functions
  config/
    tace.aws.build.config.json  # Region, profile, Launch Template IDs
  Public/
    New-TaceInstance.ps1
    Remove-TaceInstance.ps1
    Remove-TaceElasticIp.ps1
  Private/
    Assert-AwsCliAvailable.ps1
    Get-TaceLaunchTemplate.ps1
  Tests/
    New-TaceInstance.Tests.ps1
    Remove-TaceInstance.Tests.ps1
    Remove-TaceElasticIp.Tests.ps1
    TACE.AWS.Build.Module.Tests.ps1
    UnitTests.pester.ps1
  Docs/
    README.md
    TODO.md
    CHANGELOG.md
    SECURITY.md
    PREREQUISITES.md
    DESIGN.md
  Scripts/
```
