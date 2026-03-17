# TACE AWS Infrastructure — Build and Installation Guide

**Version:** 1.1  
**Region:** ca-central-1 (Canada)  
**Requirements:** PowerShell 7+, AWS CLI v2  

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1 — Account Foundation](#phase-1--account-foundation)
4. [Phase 2 — Network Foundation](#phase-2--network-foundation)
5. [Phase 3 — Security Baseline](#phase-3--security-baseline)
6. [Phase 4 — Compute](#phase-4--compute)
7. [Phase 5 — TACE.AWS Module](#phase-5--taceaws-module)
8. [Phase 6 — Operational Hygiene](#phase-6--operational-hygiene)
9. [Appendix A — Cost Reference](#appendix-a--cost-reference)
10. [Appendix B — Deferred Phases](#appendix-b--deferred-phases)

---

## Overview

This document describes the complete build process for the TACE AWS infrastructure environment. It covers account setup, network configuration, security baseline, compute provisioning, and the TACE.AWS PowerShell module. The environment is built using the AWS CLI from PowerShell 7+ and follows a security-first approach with IAM Identity Center authentication and Session Manager for instance access.

### Architecture Summary

| Component | Value |
|---|---|
| VPC CIDR | 10.x.0.0/16 (choose non-conflicting range) |
| Region | ca-central-1 (Canada) |
| Availability Zones | ca-central-1a, ca-central-1b |
| Public Subnets | 2 (one per AZ) |
| Private Subnets | 2 (one per AZ) |
| Linux Instance | Oracle Linux 9, t3.medium |
| Windows Instance | Windows Server 2022, t3.medium |
| Access Method | AWS Systems Manager Session Manager |
| Authentication | IAM Identity Center (SSO) |

---

## Prerequisites

- AWS CLI v2 — verify with `aws --version` (must show 2.x)
- PowerShell 7+ — verify with `$PSVersionTable.PSVersion` (must show Major: 7)
- AWS Session Manager Plugin — verify with `session-manager-plugin --version`
- 1Password with a dedicated vault for AWS credentials (recommended: `AWS.TACE`)
- An active AWS account with root access for initial setup

### Install Session Manager Plugin (Windows)

```powershell
Invoke-WebRequest `
    -Uri "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/windows/SessionManagerPluginSetup.exe" `
    -OutFile "$env:TEMP\SessionManagerPluginSetup.exe"

Start-Process `
    -FilePath "$env:TEMP\SessionManagerPluginSetup.exe" `
    -ArgumentList "/S" `
    -Wait

# Verify
session-manager-plugin --version
```

---

## Phase 1 — Account Foundation

### Step 1.1 — Secure the Root Account

> **Console only.** Use root credentials only for this step. Root should never be used after Phase 1 is complete.

1. Sign in to the AWS Console with root credentials.
2. Navigate to account menu → **Security credentials**.
3. Enable MFA on root. Store MFA seed in 1Password.
4. Verify no root access keys exist. Delete any that do.
5. Navigate to **IAM** and set an **Account Alias**.

### Step 1.2 — Enable IAM Identity Center

1. Search for **IAM Identity Center** in the Console.
2. Click **Enable**. Select `ca-central-1` as home region.
3. Leave identity source as **Identity Center directory**.

### Step 1.3 — Create SSO Admin User

1. IAM Identity Center → **Users** → **Add user**.
2. Enter username, email, name. Complete password setup via verification email.

### Step 1.4 — Create Permission Set

1. IAM Identity Center → **Permission sets** → **Create permission set**.
2. Select **Predefined** → **AdministratorAccess**.
3. Session duration: **8 hours**.

### Step 1.5 — Assign User to Account

1. IAM Identity Center → **AWS accounts** → select account → **Assign users or groups**.
2. Select SSO user and `AdministratorAccess` permission set.

### Step 1.6 — Configure AWS CLI for SSO

```powershell
aws configure sso --profile <your-profile-name>
```

Prompts:

```
SSO session name:         <your-profile-name>
SSO start URL:            https://<your-alias>.awsapps.com/start
SSO region:               ca-central-1
SSO registration scopes:  [press Enter]

CLI default client Region:  ca-central-1
CLI default output format:  json
CLI profile name:           <your-profile-name>
```

> Use the `awsapps.com/start` URL — not the newer regional `app.aws` URL.

### Step 1.7 — Verify CLI Access

```powershell
aws sts get-caller-identity --profile <your-profile-name>
```

Expected: `Arn` contains `assumed-role` with `AWSReservedSSO`.

### Step 1.8 — Store SSO Context in 1Password

| Field | Value |
|---|---|
| Vault | AWS.TACE |
| Item | aws-sso-config |
| SSO Start URL | https://\<alias\>.awsapps.com/start |
| SSO Region | ca-central-1 |
| Profile name | \<your-profile-name\> |
| Account ID | 12-digit AWS account ID |
| Account alias | Your account alias |

### Step 1.9 — Enable Billing Alerts

First enable in Console: **Billing and Cost Management → Billing Preferences → Alert preferences → Receive CloudWatch Billing Alerts**.

```powershell
# Create SNS topic (must be us-east-1)
$snsArn = aws sns create-topic `
    --name billing-alerts `
    --region us-east-1 `
    --profile <your-profile-name> `
    --query 'TopicArn' `
    --output text

# Subscribe email — confirm via the email AWS sends
aws sns subscribe `
    --topic-arn $snsArn `
    --protocol email `
    --notification-endpoint your@email.com `
    --region us-east-1 `
    --profile <your-profile-name>

# Create alarm
aws cloudwatch put-metric-alarm `
    --profile <your-profile-name> `
    --region us-east-1 `
    --alarm-name "Monthly-Bill-25USD" `
    --alarm-description "Alert when estimated charges exceed 25 USD" `
    --metric-name EstimatedCharges `
    --namespace AWS/Billing `
    --statistic Maximum `
    --period 86400 `
    --threshold 25 `
    --comparison-operator GreaterThanThreshold `
    --dimensions Name=Currency,Value=USD `
    --evaluation-periods 1 `
    --alarm-actions $snsArn `
    --treat-missing-data notBreaching
```

### Phase 1 Checklist

- [ ] Root MFA enabled, no root access keys
- [ ] Account alias set
- [ ] IAM Identity Center enabled in ca-central-1
- [ ] SSO user created, password set
- [ ] AdministratorAccess permission set created (8 hour session)
- [ ] User assigned to account
- [ ] AWS CLI profile configured and verified
- [ ] SSO context stored in 1Password
- [ ] Billing alarm set at $25 USD

---

## Phase 2 — Network Foundation

### Step 2.1 — Check Existing VPCs

```powershell
aws ec2 describe-vpcs `
    --region ca-central-1 `
    --profile <your-profile-name> `
    --query 'Vpcs[].{ID:VpcId,CIDR:CidrBlock,Default:IsDefault,Name:Tags[?Key==`Name`].Value|[0]}' `
    --output table
```

Choose a non-conflicting CIDR block. Recommended: `10.x.0.0/16`.

### Step 2.2 — Create VPC

```powershell
$vpcId = aws ec2 create-vpc `
    --cidr-block 10.x.0.0/16 `
    --region ca-central-1 `
    --profile <your-profile-name> `
    --query 'Vpc.VpcId' `
    --output text

aws ec2 modify-vpc-attribute --vpc-id $vpcId --enable-dns-hostnames --region ca-central-1 --profile <your-profile-name>
aws ec2 create-tags --resources $vpcId --tags "Key=Name,Value=tace-vpc" --region ca-central-1 --profile <your-profile-name>

# Verify DNS hostnames — expected: true
aws ec2 describe-vpc-attribute --vpc-id $vpcId --attribute enableDnsHostnames --region ca-central-1 --profile <your-profile-name> --query 'EnableDnsHostnames.Value'
```

### Step 2.3 — Create Subnets

| Name | CIDR | AZ |
|---|---|---|
| tace-public-subnet-a | 10.x.1.0/24 | ca-central-1a |
| tace-public-subnet-b | 10.x.2.0/24 | ca-central-1b |
| tace-private-subnet-a | 10.x.11.0/24 | ca-central-1a |
| tace-private-subnet-b | 10.x.12.0/24 | ca-central-1b |

```powershell
$pubSubnetA = aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.x.1.0/24 --availability-zone ca-central-1a --region ca-central-1 --profile <your-profile-name> --query 'Subnet.SubnetId' --output text
aws ec2 create-tags --resources $pubSubnetA --tags "Key=Name,Value=tace-public-subnet-a" --region ca-central-1 --profile <your-profile-name>

$pubSubnetB = aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.x.2.0/24 --availability-zone ca-central-1b --region ca-central-1 --profile <your-profile-name> --query 'Subnet.SubnetId' --output text
aws ec2 create-tags --resources $pubSubnetB --tags "Key=Name,Value=tace-public-subnet-b" --region ca-central-1 --profile <your-profile-name>

$privSubnetA = aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.x.11.0/24 --availability-zone ca-central-1a --region ca-central-1 --profile <your-profile-name> --query 'Subnet.SubnetId' --output text
aws ec2 create-tags --resources $privSubnetA --tags "Key=Name,Value=tace-private-subnet-a" --region ca-central-1 --profile <your-profile-name>

$privSubnetB = aws ec2 create-subnet --vpc-id $vpcId --cidr-block 10.x.12.0/24 --availability-zone ca-central-1b --region ca-central-1 --profile <your-profile-name> --query 'Subnet.SubnetId' --output text
aws ec2 create-tags --resources $privSubnetB --tags "Key=Name,Value=tace-private-subnet-b" --region ca-central-1 --profile <your-profile-name>
```

### Step 2.4 — Create and Attach Internet Gateway

```powershell
$igwId = aws ec2 create-internet-gateway --region ca-central-1 --profile <your-profile-name> --query 'InternetGateway.InternetGatewayId' --output text
aws ec2 create-tags --resources $igwId --tags "Key=Name,Value=tace-igw" --region ca-central-1 --profile <your-profile-name>
aws ec2 attach-internet-gateway --internet-gateway-id $igwId --vpc-id $vpcId --region ca-central-1 --profile <your-profile-name>
```

### Step 2.5 — Create Route Tables

```powershell
# Public route table
$pubRtId = aws ec2 create-route-table --vpc-id $vpcId --region ca-central-1 --profile <your-profile-name> --query 'RouteTable.RouteTableId' --output text
aws ec2 create-tags --resources $pubRtId --tags "Key=Name,Value=tace-public-rt" --region ca-central-1 --profile <your-profile-name>
aws ec2 create-route --route-table-id $pubRtId --destination-cidr-block 0.0.0.0/0 --gateway-id $igwId --region ca-central-1 --profile <your-profile-name>
aws ec2 associate-route-table --route-table-id $pubRtId --subnet-id $pubSubnetA --region ca-central-1 --profile <your-profile-name>
aws ec2 associate-route-table --route-table-id $pubRtId --subnet-id $pubSubnetB --region ca-central-1 --profile <your-profile-name>

# Private route table
$privRtId = aws ec2 create-route-table --vpc-id $vpcId --region ca-central-1 --profile <your-profile-name> --query 'RouteTable.RouteTableId' --output text
aws ec2 create-tags --resources $privRtId --tags "Key=Name,Value=tace-private-rt" --region ca-central-1 --profile <your-profile-name>
aws ec2 associate-route-table --route-table-id $privRtId --subnet-id $privSubnetA --region ca-central-1 --profile <your-profile-name>
aws ec2 associate-route-table --route-table-id $privRtId --subnet-id $privSubnetB --region ca-central-1 --profile <your-profile-name>

# Tag the auto-created main route table
# Identify the unnamed table from describe-route-tables output
aws ec2 create-tags --resources <main-rt-id> --tags "Key=Name,Value=tace-main-rt" --region ca-central-1 --profile <your-profile-name>
```

### Phase 2 Checklist

- [ ] VPC created, DNS hostnames enabled
- [ ] 4 subnets — 2 public, 2 private, one pair per AZ
- [ ] Internet Gateway created and attached
- [ ] Public route table — IGW route, both public subnets associated
- [ ] Private route table — local only, both private subnets associated
- [ ] All route tables tagged

---

## Phase 3 — Security Baseline

### Step 3.1 — Create IAM Role and Instance Profile

```powershell
aws iam create-role `
    --role-name tace-ec2-ssm-role `
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{"Effect": "Allow","Principal": {"Service": "ec2.amazonaws.com"},"Action": "sts:AssumeRole"}]
    }' `
    --profile <your-profile-name>

aws iam attach-role-policy --role-name tace-ec2-ssm-role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore --profile <your-profile-name>
aws iam create-instance-profile --instance-profile-name tace-ec2-instance-profile --profile <your-profile-name>
aws iam add-role-to-instance-profile --instance-profile-name tace-ec2-instance-profile --role-name tace-ec2-ssm-role --profile <your-profile-name>
```

### Step 3.2 — Create Security Groups

```powershell
$sgLinuxId = aws ec2 create-security-group --group-name tace-linux-sg --description "TACE Linux instances - Session Manager access only" --vpc-id $vpcId --region ca-central-1 --profile <your-profile-name> --query 'GroupId' --output text
aws ec2 create-tags --resources $sgLinuxId --tags "Key=Name,Value=tace-linux-sg" --region ca-central-1 --profile <your-profile-name>

$sgWinId = aws ec2 create-security-group --group-name tace-windows-sg --description "TACE Windows instances - Session Manager access only" --vpc-id $vpcId --region ca-central-1 --profile <your-profile-name> --query 'GroupId' --output text
aws ec2 create-tags --resources $sgWinId --tags "Key=Name,Value=tace-windows-sg" --region ca-central-1 --profile <your-profile-name>
```

### Step 3.3 — Configure Outbound Rules (HTTPS Only)

```powershell
# Remove default allow-all, add HTTPS only — repeat for both SGs
foreach ($sgId in @($sgLinuxId, $sgWinId)) {
    aws ec2 revoke-security-group-egress --group-id $sgId --protocol -1 --port -1 --cidr 0.0.0.0/0 --region ca-central-1 --profile <your-profile-name>
    aws ec2 authorize-security-group-egress --group-id $sgId --protocol tcp --port 443 --cidr 0.0.0.0/0 --region ca-central-1 --profile <your-profile-name>
}
```

### Step 3.4 — Grant Instance Role S3 Read Access

Allows EC2 instances to pull files from the TACE staging prefix in S3. Scoped to the
`staging/` prefix only — no broader S3 access is granted.

```powershell
aws iam put-role-policy `
    --role-name tace-ec2-ssm-role `
    --policy-name tace-s3-ec2-read `
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": "s3:GetObject",
                "Resource": "arn:aws:s3:::tacedata-s3-bucket-02/staging/*"
            },
            {
                "Effect": "Allow",
                "Action": "s3:ListBucket",
                "Resource": "arn:aws:s3:::tacedata-s3-bucket-02",
                "Condition": {
                    "StringLike": {
                        "s3:prefix": "staging/*"
                    }
                }
            }
        ]
    }' `
    --profile <your-profile-name>
```

To upload files from your laptop to the staging prefix:

```powershell
aws s3 cp <local-path> s3://tacedata-s3-bucket-02/staging/ `
    --recursive --profile <your-profile-name> --region ca-central-1
```

To pull files down on the instance via SSM:

```bash
aws s3 cp s3://tacedata-s3-bucket-02/staging/<folder>/ ~/<folder>/ --recursive
```

### Phase 3 Checklist

- [ ] IAM role created with AmazonSSMManagedInstanceCore policy
- [ ] Instance profile created and role attached
- [ ] S3 read policy (`tace-s3-ec2-read`) attached — scoped to `staging/` prefix
- [ ] Linux and Windows Security Groups created
- [ ] Both SGs — zero inbound, HTTPS 443 outbound only

---

## Phase 4 — Compute

### Step 4.1 — Find AMI IDs

```powershell
# Oracle Linux 9
aws ec2 describe-images `
    --region ca-central-1 --profile <your-profile-name> `
    --filters "Name=name,Values=*Oracle*Linux*9*" "Name=architecture,Values=x86_64" "Name=state,Values=available" `
    --query 'sort_by(Images, &CreationDate)[-5:].{ID:ImageId,Name:Name,Date:CreationDate}' `
    --output table

# Windows Server 2022
aws ec2 describe-images `
    --region ca-central-1 --profile <your-profile-name> `
    --owners amazon `
    --filters "Name=name,Values=Windows_Server-2022-English-Full-Base*" "Name=architecture,Values=x86_64" "Name=state,Values=available" `
    --query 'sort_by(Images, &CreationDate)[-1].{ID:ImageId,Name:Name,Date:CreationDate}' `
    --output table
```

Select `Oracle Linux 9 LATEST x86_64`. Accept Marketplace subscription if prompted.

> **OS selection:** Oracle Linux 9 is fully certified for Oracle Database 19c, 21c, and 23ai. It is free on EC2 with no OS licensing surcharge. Oracle Linux 10 is not yet recommended — database certification lags new OS releases by 12-18 months.

### Step 4.2 — Launch Linux Instance

The user data script installs the SSM agent on first boot. Required because Oracle Linux 9 Marketplace AMIs do not include it by default.

```powershell
$userData = @"
#!/bin/bash
dnf install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
"@

$userDataEncoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($userData))

$linuxInstanceId = aws ec2 run-instances `
    --image-id <oracle-linux-9-ami-id> `
    --instance-type t3.medium `
    --subnet-id <public-subnet-a-id> `
    --security-group-ids <linux-sg-id> `
    --iam-instance-profile Name=tace-ec2-instance-profile `
    --associate-public-ip-address `
    --metadata-options "HttpTokens=required,HttpEndpoint=enabled" `
    --user-data $userDataEncoded `
    --region ca-central-1 --profile <your-profile-name> `
    --query 'Instances[0].InstanceId' --output text

aws ec2 create-tags --resources $linuxInstanceId --tags "Key=Name,Value=tace-linux-01" --region ca-central-1 --profile <your-profile-name>
```

### Step 4.3 — Launch Windows Instance

```powershell
$winInstanceId = aws ec2 run-instances `
    --image-id <windows-server-2022-ami-id> `
    --instance-type t3.medium `
    --subnet-id <public-subnet-a-id> `
    --security-group-ids <windows-sg-id> `
    --iam-instance-profile Name=tace-ec2-instance-profile `
    --associate-public-ip-address `
    --metadata-options "HttpTokens=required,HttpEndpoint=enabled" `
    --region ca-central-1 --profile <your-profile-name> `
    --query 'Instances[0].InstanceId' --output text

aws ec2 create-tags --resources $winInstanceId --tags "Key=Name,Value=tace-windows-01" --region ca-central-1 --profile <your-profile-name>
```

### Step 4.4 — Allocate and Associate Elastic IPs

```powershell
$eipLinux = aws ec2 allocate-address --domain vpc --region ca-central-1 --profile <your-profile-name> --query '{AllocationId:AllocationId,IP:PublicIp}' --output json | ConvertFrom-Json
aws ec2 create-tags --resources $eipLinux.AllocationId --tags "Key=Name,Value=tace-linux-eip" --region ca-central-1 --profile <your-profile-name>

$eipWindows = aws ec2 allocate-address --domain vpc --region ca-central-1 --profile <your-profile-name> --query '{AllocationId:AllocationId,IP:PublicIp}' --output json | ConvertFrom-Json
aws ec2 create-tags --resources $eipWindows.AllocationId --tags "Key=Name,Value=tace-windows-eip" --region ca-central-1 --profile <your-profile-name>

aws ec2 associate-address --instance-id $linuxInstanceId --allocation-id $eipLinux.AllocationId --region ca-central-1 --profile <your-profile-name>
aws ec2 associate-address --instance-id $winInstanceId --allocation-id $eipWindows.AllocationId --region ca-central-1 --profile <your-profile-name>
```

### Step 4.5 — Verify Session Manager Connectivity

Allow 5-10 minutes after launch for the SSM agent to install and register.

```powershell
aws ssm describe-instance-information `
    --region ca-central-1 --profile <your-profile-name> `
    --query 'InstanceInformationList[].{ID:InstanceId,Name:ComputerName,Platform:PlatformName,Status:PingStatus,Version:AgentVersion}' `
    --output table
```

Both instances must show `Online` before proceeding.

### Step 4.6 — Set Windows Administrator Password

Required on first connection. Run from a separate terminal:

```powershell
aws ssm start-session --target <windows-instance-id> --region ca-central-1 --profile <your-profile-name>
# In the session shell:
net user Administrator YourChosenPassword123!
exit
```

### Step 4.7 — Record Infrastructure Details in 1Password

Store all resource IDs in `AWS.TACE / tace-infrastructure` in 1Password.

### Phase 4 Checklist

- [ ] Oracle Linux 9 Marketplace subscription accepted
- [ ] Linux instance launched with SSM agent user data
- [ ] Windows instance launched
- [ ] Elastic IPs allocated and associated
- [ ] Both instances Online in SSM
- [ ] Windows Administrator password set
- [ ] All resource IDs stored in 1Password

---

## Phase 5 — TACE.AWS Modules

The original `TACE.AWS` module has been split into two purpose-built modules:

| Module | Purpose | Repo path |
|---|---|---|
| `TACE.AWS.Build` | Instance lifecycle — launch, teardown, Elastic IPs, provisioning scripts | `dev/TACE/repos/TACE.AWS.Build/` |
| `TACE.AWS.Run` | Day-to-day operations — start, stop, connect, status | `dev/TACE/repos/TACE.AWS.Run/` |

### Step 5.1 — Module Structure

**TACE.AWS.Build**

```
TACE.AWS.Build/
  TACE.AWS.Build.psd1              # Module manifest
  TACE.AWS.Build.psm1              # Root module — loads config, private/public functions
  config/
    tace.aws.build.config.json     # Region, profile, instance IDs, Launch Template IDs
  Public/
    New-TaceInstance.ps1           # Launch instance from Launch Template, allocate + associate EIP
    Remove-TaceInstance.ps1        # Terminate instance with typed confirmation
    Remove-TaceElasticIp.ps1       # Disassociate and release EIP
  Private/
    Assert-AwsCliAvailable.ps1     # Validates AWS CLI v2
    Get-TaceLaunchTemplate.ps1     # Resolves profile name to Launch Template ID
  Scripts/
    Install-OracleXE.ps1           # Install Oracle Database 26ai via SSM Run Command
    linux.post.build.ps1           # Post-build: volume resize, filesystem extend, PowerShell install
  Tests/
  Docs/
    TACE-AWS-INSTALL.md            # This document
```

**TACE.AWS.Run**

```
TACE.AWS.Run/
  TACE.AWS.Run.psd1                # Module manifest
  TACE.AWS.Run.psm1                # Root module — loads config, private/public functions, aliases
  config/
    tace-aws.config.json           # Region, profile, instance IDs
  Public/
    Connect-TaceInstance.ps1
    Connect-TaceLinux.ps1
    Connect-TaceWindows.ps1
    Get-TaceInstanceStatus.ps1
    Start-TaceInstance.ps1
    Start-TaceLinux.ps1
    Start-TaceWindows.ps1
    Stop-TaceInstance.ps1
    Stop-TaceLinux.ps1
    Stop-TaceWindows.ps1
  Private/
    Assert-AwsCliAvailable.ps1     # Validates AWS CLI v2 and Session Manager plugin
    Assert-InstanceOnline.ps1      # Validates SSM registration status
  Tests/
  Docs/
```

### Step 5.2 — Update Instance Config

Both modules maintain their own config. Update both after launching instances.

**TACE.AWS.Build** — `config/tace.aws.build.config.json`:

```json
{
    "DefaultRegion": "ca-central-1",
    "DefaultProfile": "tace-aws-admin",
    "Instances": {
        "Linux":   "<linux-instance-id>",
        "Windows": "<windows-instance-id>"
    },
    "LaunchTemplates": {
        "tace-linux": {
            "TemplateId": "<launch-template-id>",
            "TemplateName": "tace-linux",
            "Description": "Oracle Linux 9, t3.medium — TACE standard Linux instance"
        },
        "tace-windows": {
            "TemplateId": "<launch-template-id>",
            "TemplateName": "tace-windows",
            "Description": "Windows Server 2022, t3.medium — TACE standard Windows instance"
        }
    }
}
```

**TACE.AWS.Run** — `config/tace-aws.config.json`:

```json
{
    "DefaultRegion": "ca-central-1",
    "DefaultProfile": "tace-aws-admin",
    "Instances": {
        "Linux":   "<linux-instance-id>",
        "Windows": "<windows-instance-id>"
    }
}
```

> Both `Instances` sections are maintained manually. Update them when an instance is replaced (terminate old, build new, update the ID in both files).

### Step 5.3 — Import Modules

```powershell
Import-Module ./TACE.AWS.Build.psd1
Import-Module ./TACE.AWS.Run.psd1
```

Add both to PowerShell profile for automatic import:

```powershell
# In $PROFILE
Import-Module <path-to>/TACE.AWS.Build/TACE.AWS.Build.psd1
Import-Module <path-to>/TACE.AWS.Run/TACE.AWS.Run.psd1
```

### Step 5.4 — Verify Module Functions

```powershell
# Check functions available in each module
Get-Command -Module TACE.AWS.Build
Get-Command -Module TACE.AWS.Run

# Check instance status
get-tace-status | Format-Table
```

### Step 5.5 — Post-Build: Provision a New Linux Instance

After `New-TaceInstance` completes, run the post-build script to resize the root volume and install PowerShell, then install Oracle Database 26ai:

```powershell
# Build
New-TaceInstance -ProfileName tace-linux -Wait

# Post-build (volume resize to 30GB + PowerShell install)
& '<path-to>/TACE.AWS.Build/Scripts/linux.post.build.ps1' -InstanceName Linux

# Install Oracle Database 26ai
$pw = Read-Host -AsSecureString 'SYS password'
& '<path-to>/TACE.AWS.Build/Scripts/Install-OracleXE.ps1' -InstanceName Linux -SysPassword $pw
```

### Step 5.6 — Daily Workflow

```powershell
# Start environment
start-tace-linux -Wait
start-tace-windows -Wait

# Connect
connect-tace-linux       # Linux shell session
connect-tace-windows     # Windows RDP (auto-launches mstsc)

# Check status at any time
get-tace-status | Format-Table

# Stop environment when done
stop-tace-linux -Wait
stop-tace-windows -Wait
```

### Phase 5 Checklist

- [ ] TACE.AWS.Build — instance IDs and Launch Template IDs updated in `tace.aws.build.config.json`
- [ ] TACE.AWS.Run — instance IDs updated in `tace-aws.config.json`
- [ ] Both modules import without errors
- [ ] `get-tace-status` returns both instances
- [ ] `connect-tace-linux` opens shell session
- [ ] `connect-tace-windows` opens RDP tunnel and launches mstsc
- [ ] `start-tace-linux -Wait` and `start-tace-windows -Wait` start instances
- [ ] `stop-tace-linux -Wait` and `stop-tace-windows -Wait` stop instances
- [ ] Both module imports added to PowerShell profile
- [ ] Post-build script run on new Linux instances (`linux.post.build.ps1`)
- [ ] Oracle Database 26ai installed on Linux instance (`Install-OracleXE.ps1`)

---

## Appendix A — Cost Reference

Assumes on-demand pricing, ca-central-1, ~220 hours/month runtime.

| Resource | Rate | Est. Monthly |
|---|---|---|
| Linux EC2 (t3.medium, Oracle Linux 9) | ~$0.0464/hr | ~$10.21 |
| Windows EC2 (t3.medium, Windows Server 2022) | ~$0.0928/hr | ~$20.42 |
| EBS — Linux root (30GB gp3) | $0.088/GB-month | ~$2.64 |
| EBS — Windows root (60GB gp3) | $0.088/GB-month | ~$5.28 |
| Elastic IP — Linux (220 hrs) | $0.005/hr | ~$1.10 |
| Elastic IP — Windows (220 hrs) | $0.005/hr | ~$1.10 |
| S3 — scripts, configs, logs (<5GB) | ~$0.025/GB-month | ~$0.13 |
| Secrets Manager (5 secrets) | $0.40/secret/month | ~$2.00 |
| VPC, subnets, IGW, route tables, SGs | free | $0.00 |
| **Total (~220 hrs/month)** | | **~$42–46** |

> Elastic IPs accrue charges whether instances are running or stopped. Release EIPs when permanently decommissioning.

---

## Appendix B — Deferred Phases

| Phase | Description |
|---|---|
| Phase 6 | Operational Hygiene — CloudWatch monitoring, cost anomaly detection |
| Phase 7 | DNS and Website — Route 53, CloudFront, ACM certificate, S3 static website |
| Phase 8 | Email — WorkMail, SES domain verification, SPF/DKIM/DMARC, mailboxes |
