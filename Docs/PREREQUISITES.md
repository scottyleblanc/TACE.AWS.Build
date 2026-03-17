# TACE.AWS.Build — Prerequisites

---

## Language

| Requirement | Value |
|---|---|
| Minimum version | PowerShell 7.0 |
| Tested against | PowerShell 7.5.4 |

All `.ps1` files include `#Requires -Version 7.0`.

---

## External Tools

| Tool | Version | Required by | Install |
|---|---|---|---|
| AWS CLI | v2.x | All public functions | [AWS CLI install guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) |

Verify with:
```powershell
aws --version   # must show aws-cli/2.x
```

---

## AWS Account Setup

The following must exist in your AWS account before this module will function:

### IAM Identity Center (SSO)

Profile `tace-aws-admin` must be configured in `~/.aws/config`:
```ini
[profile tace-aws-admin]
sso_start_url = https://<your-alias>.awsapps.com/start
sso_region    = ca-central-1
sso_account_id = <your-account-id>
sso_role_name  = AdministratorAccess
region         = ca-central-1
output         = json
```

Refresh credentials before use:
```powershell
aws sso login --profile tace-aws-admin
```

### AWS Launch Templates

Before `New-TaceInstance` will work, you must create an AWS Launch Template for each
instance profile and update `config/tace.aws.build.config.json` with the template IDs.

**Creating a Launch Template (console):**

1. Open EC2 console → Launch Templates → Create launch template
2. Name it exactly as the profile name (e.g. `tace-linux`)
3. Configure:
   - AMI — select your desired OS (e.g. Oracle Linux 9 from AWS Marketplace)
   - Instance type — e.g. `t3.medium`
   - Key pair — None (access via SSM only)
   - Network settings — do not include subnet (subnet is resolved at launch time)
   - Security groups — select `tace-linux-sg` or `tace-windows-sg`
   - IAM instance profile — `tace-ec2-instance-profile`
   - Advanced → IMDSv2 → Required
   - Tags — add `Name` tag if desired
4. Copy the Launch Template ID (format: `lt-xxxxxxxxxxxxxxxxx`)
5. Update `config/tace.aws.build.config.json`:
   ```json
   "tace-linux": {
       "TemplateId": "lt-xxxxxxxxxxxxxxxxx",
       ...
   }
   ```

**Verify a Launch Template exists:**
```powershell
aws ec2 describe-launch-templates --profile tace-aws-admin --output table
```

---

## Test Framework

| Requirement | Value |
|---|---|
| Framework | Pester 5.x |
| Minimum version | 5.0 |
| Install | `Install-Module Pester -MinimumVersion 5.0` |

Run tests:
```powershell
Invoke-Pester ./Tests/ -Output Detailed
```

Unit tests mock all AWS CLI calls — no real AWS account or credentials required for testing.

---

## Execution Policy

| Context | Minimum policy |
|---|---|
| Interactive development | `RemoteSigned` |
| Automated / CI | `RemoteSigned` |

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Platform Support

| Platform | Status |
|---|---|
| Windows 11 (PowerShell 7+) | Supported — primary development platform |
| Linux (PowerShell 7+) | Expected — no Windows-specific code |
| macOS (PowerShell 7+) | Expected — no Windows-specific code |

---

## Known Limitations

- `New-TaceInstance` prompts interactively to update TACE.AWS.Run config — not suitable for fully unattended automation in v0.1.0
- SSO credentials expire after 8 hours — must refresh with `aws sso login` before each session
- Launch Template IDs are region-specific — config must be updated if deploying to a different region
