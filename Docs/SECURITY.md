# TACE.AWS.Build — Security

Authoritative security reference. Updated at the end of every implementation stage.

---

## Status

| Field | Value |
|---|---|
| Version | 0.1.0 |
| Last reviewed | 2026-03-16 |
| Findings resolved | 0 |
| Open items | 2 (see below) |
| Pester security tests | 0 (tests not yet written) |

---

## Security Mechanisms

### 1. Destruction Guard Rails

**Status:** Implemented (v0.1.0)

**Why:** `Remove-TaceInstance` and `Remove-TaceElasticIp` are irreversible. A single
accidental invocation can destroy running infrastructure and incur unrecoverable data loss.

**How:** Two independent gates are required before any destructive AWS API call:
1. `SupportsShouldProcess` — enables `-WhatIf` for dry-run and `-Confirm` for interactive prompt
2. Typed confirmation — the caller must type the exact instance name (for terminate) or
   public IP address (for EIP release) at an interactive prompt

**Contract:**
- `-WhatIf` shows the planned action and returns `Success=$false` without calling AWS
- If typed confirmation does not exactly match the expected value, operation cancels with `Success=$false`
- The typed value is compared with `-ceq` (case-sensitive exact match) against the parameter value

---

### 2. Launch Template ID Isolation

**Status:** Implemented (v0.1.0)

**Why:** APSC-DV-002400 — dynamic construction of AWS resource IDs from user input
is a form of injection risk. Launch Template IDs determine exactly what gets launched.

**How:**
- Launch Template IDs are read exclusively from `config/tace.aws.build.config.json`
- User input (`-ProfileName`) is used only as a config lookup key — it never reaches an AWS API call
- `Get-TaceLaunchTemplate` validates the resolved ID matches AWS format (`lt-[0-9a-f]+`) before returning
- Placeholder values (`lt-PLACEHOLDER`) are detected and blocked with a descriptive error

**Contract:** No user-supplied string is ever passed directly to `--launch-template` in an AWS CLI call.

---

### 3. Credential and Secret Hygiene

**Status:** Implemented (v0.1.0)

**Why:** APSC-DV-000160, WN22-CC-000460/470 — credentials must never appear in logs,
pipeline output, or process argument lists.

**How:**
- No password parameters in this module — AWS authentication is handled by the AWS CLI
  using IAM Identity Center (SSO) temporary credentials
- `Message` property on all return objects contains only instance names, IDs, and IP
  addresses — no tokens, no session credentials
- `Write-Verbose` output contains function name, action, and UTC timestamp only
- AWS CLI is invoked via splatted argument arrays — no string concatenation with user input

**Contract:** `Message` is always safe to write to a log file or display in a transcript.

---

### 4. Config File Security

**Status:** Defined (v0.1.0)

**Why:** `tace.aws.build.config.json` contains AWS resource identifiers. It does not
contain credentials, but misconfigured Launch Template IDs could cause unintended
instance types or configurations to be launched.

**How:**
- Config contains Launch Template ID references only — no AMI IDs, no security group IDs,
  no instance types. All instance spec lives in the AWS Launch Template.
- `Get-TaceLaunchTemplate` validates ID format and rejects placeholder values
- Config file should have read access restricted to the owning user account

**Contract:** Config file must not contain credentials, secrets, or hardcoded connection strings (APSC-DV-003235).

---

## Open Items

| ID | Severity | Description | Target |
|---|---|---|---|
| SEC-001 | LOW | Pester security context tests not yet written — `ArgumentList`, `Message`, and `Verbose` output not yet formally verified | v0.1.0 test pass |
| SEC-002 | LOW | `tace.aws.build.config.json` ACL not enforced by code — relies on filesystem permissions set by user | v0.2.0 |

---

## STIG Compliance Notes

| Control | Requirement | Status |
|---|---|---|
| APSC-DV-000160 | No plaintext credential storage | Met — no credential parameters in this module |
| APSC-DV-002000 | Explicit parameter validation on all public functions | Met — all parameters have ValidatePattern/ValidateNotNullOrEmpty |
| APSC-DV-002400 | No dynamic resource ID construction from user input | Met — Launch Template IDs from config only |
| APSC-DV-003235 | No hardcoded credentials or connection strings in source | Met |
| WN22-CC-000480 | Requires PS 7.0+ | Met — #Requires -Version 7.0 on all files |
