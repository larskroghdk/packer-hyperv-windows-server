---
name: packer-hcl
description: Maintain this factory's Packer HCL2 sources, plugin constraints and schema compatibility.
---

Read ../../../docs/plugin-audit.md. Check plugin main registration, Config and generated HCL2Spec before editing attributes. Keep per-release differences in config while preserving one shared source/build. Validate dynamic provisioner blocks with a nonempty approved-package fixture as well as the six normal configurations. Use tests/static/Test-Project.ps1; a syntax-only check cannot verify plugin options.
