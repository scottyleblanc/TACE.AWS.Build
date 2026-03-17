# TACE.AWS.Build — Changelog

All notable changes to this module are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [0.1.0] — Unreleased

### Added
- Module scaffold: Public, Private, Tests, Docs, Scripts, config directories
- `New-TaceInstance` — launch EC2 instance from named AWS Launch Template profile; auto-increment instance naming; allocate and associate Elastic IP; prompt to update TACE.AWS.Run config with backup
- `Remove-TaceInstance` — terminate EC2 instance with SupportsShouldProcess (-WhatIf) + typed instance name confirmation gate
- `Remove-TaceElasticIp` — disassociate and release Elastic IP with SupportsShouldProcess (-WhatIf) + typed public IP confirmation gate
- Private helper `Assert-AwsCliAvailable` — validates AWS CLI v2
- Private helper `Get-TaceLaunchTemplate` — resolves profile name to AWS Launch Template ID with placeholder detection
- Module config `tace.aws.build.config.json` — region, profile, Launch Template ID references (placeholder values — update before use)
- Full Docs suite: README.md, TODO.md, CHANGELOG.md, SECURITY.md, PREREQUISITES.md, DESIGN.md
