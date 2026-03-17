# TACE.AWS.Build — TODO

Active build checklist. Items migrate to CHANGELOG.md on completion.

## v0.1.0 — Current

- [x] Scaffold module structure (Public, Private, Tests, Docs, Scripts, config)
- [x] Module manifest (TACE.AWS.Build.psd1) — identity, PSGallery fields
- [x] Module loader (TACE.AWS.Build.psm1) — config load, private/public dot-source
- [x] config/tace.aws.build.config.json — region, profile, Launch Template placeholders
- [x] Private: Assert-AwsCliAvailable
- [x] Private: Get-TaceLaunchTemplate — resolve profile name to Launch Template ID
- [x] Public: New-TaceInstance — launch from Launch Template, allocate + associate EIP, prompt to update Run config
- [x] Public: Remove-TaceInstance — terminate with -WhatIf + typed name confirmation
- [x] Public: Remove-TaceElasticIp — disassociate + release with -WhatIf + typed IP confirmation
- [x] Docs: README.md, TODO.md, CHANGELOG.md, SECURITY.md, PREREQUISITES.md, DESIGN.md
- [ ] Create AWS Launch Templates in console for tace-linux and tace-windows profiles
- [ ] Update config/tace.aws.build.config.json with real Launch Template IDs
- [ ] Pester tests — New-TaceInstance
- [ ] Pester tests — Remove-TaceInstance
- [ ] Pester tests — Remove-TaceElasticIp
- [ ] Pester tests — TACE.AWS.Build.Module (config loading)
- [ ] Activate TACE.AWS.Build import in PowerShell profile (currently commented out)
- [ ] Create GitHub repo scottyleblanc/TACE.AWS.Build and push initial commit

## v0.2.0 — Planned

- [ ] New-TaceLaunchTemplate — generate an AWS Launch Template from a local profile definition
- [ ] Get-TaceInstance — list all instances with profile, name, state, EIP (extends TACE.AWS.Run)
- [ ] Update-TaceRunConfig — explicit function to sync new instance details to TACE.AWS.Run config
- [ ] Pester tests for all v0.2.0 functions
