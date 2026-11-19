---
name: security-hardening
description: Review or change this factory's hardening integration, temporary access and build-secret disposal.
---

Preserve hardening compatibility mode while WinRM is needed. Read deferred_plan and baseline exclusions before asserting compliance; fail on pending/failed results. Finalization closes the bootstrap listener/rule, deletes its certificate, invalidates the credential and hands shutdown to Sysprep. Consumers establish their own management access. Check cached answer-file cleanup and read-only captured-image evidence. Runner media/cache confidentiality is separate from Packer sensitive-variable masking.
