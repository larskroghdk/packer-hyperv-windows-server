---
name: github-actions
description: Maintain hosted validation and protected self-hosted live build workflows for this factory.
---

Keep PR validation on hosted Windows and pin sibling plugin source commits. The self-hosted live job is workflow_dispatch on trusted main, uses hyperv-build environment protection and requires explicit live input. Do not interpolate dispatch input into shell source; pass it through environment variables. Publish reports on failure and VHDX only on full success. External storage uses an existing mounted path and runner identity, with hash verification and no overwrite.
