build {
  name    = "windows-server"
  sources = ["source.hyperv-iso.windows"]

  provisioner "powershell" {
    script           = "scripts/guest/Prepare.ps1"
    environment_vars = ["FACTORY_SERVER=${var.server_version}", "FACTORY_EDITION=${var.edition}", "FACTORY_INSTALLATION=${var.installation_type}", "FACTORY_NETFX_SOURCE=${var.netfx_source}"]
    timeout          = var.provisioning_timeout
  }
  provisioner "windows-features" {
    remove              = ["PowerShell-V2"]
    ignore_unavailable  = true
    restart_if_required = true
    restart_timeout     = var.reboot_timeout
    operation_timeout   = var.provisioning_timeout
    report_path         = "${local.reports}/features-remove.json"
  }
  provisioner "windows-features" {
    install             = ["NET-Framework-Core"]
    source              = var.netfx_source
    limit_access        = true
    restart_if_required = true
    restart_timeout     = var.reboot_timeout
    operation_timeout   = var.provisioning_timeout
    report_path         = "${local.reports}/features-netfx.json"
  }
  provisioner "windows-optimize" {
    profile            = var.optimization_profile
    reboot_if_required = true
    restart_timeout    = var.reboot_timeout
    report_path        = "${local.reports}/optimization.json"
    timeout            = var.provisioning_timeout
  }
  provisioner "windows-harden" {
    baseline           = "auto"
    profile            = var.hardening_profile
    mode               = "compatibility"
    reboot_if_required = true
    restart_timeout    = var.reboot_timeout
    report_path        = "${local.reports}/hardening.json"
    timeout            = var.provisioning_timeout
  }
  # Each package gets its own supported Packer restart boundary. Operators must
  # order checkpoint prerequisites before their target cumulative update.
  dynamic "provisioner" {
    for_each = var.approved_oob_packages
    labels   = ["file"]
    content {
      source      = provisioner.value.path
      destination = "C:/ProgramData/PackerCleanup/Staging/${provisioner.value.kb}.msu"
    }
  }
  provisioner "file" {
    content     = jsonencode(var.approved_oob_packages)
    destination = "C:/ProgramData/ImageFactory/oob.json"
  }
  provisioner "file" {
    source      = "scripts/guest/Install-ApprovedPackage.ps1"
    destination = "C:/Windows/Temp/packer-factory-oob.ps1"
  }
  dynamic "provisioner" {
    for_each = var.approved_oob_packages
    labels   = ["windows-restart"]
    content {
      restart_command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\Windows\\Temp\\packer-factory-oob.ps1 -KB ${provisioner.value.kb} -Sha256 ${provisioner.value.sha256}"
      restart_timeout = var.reboot_timeout
      timeout         = var.provisioning_timeout
    }
  }
  provisioner "windows-update" {
    search_criteria    = var.update_search_criteria
    filters            = ["exclude:$_.Title -match 'Preview'", "include:$true"]
    update_limit       = var.update_limit
    update_max_retries = var.update_max_retries
    restart_timeout    = var.reboot_timeout
    timeout            = var.update_timeout
  }
  provisioner "windows-restart" {
    restart_timeout = var.reboot_timeout
  }
  # Updates may alter policies or services. Re-inspect through the same plugins
  # before issuing a release; these passes perform no additional changes.
  provisioner "windows-optimize" {
    profile     = var.optimization_profile
    dry_run     = true
    report_path = "${local.reports}/optimization-validation.json"
    timeout     = var.provisioning_timeout
  }
  provisioner "windows-harden" {
    baseline    = "auto"
    profile     = var.hardening_profile
    mode        = "compatibility"
    dry_run     = true
    report_path = "${local.reports}/hardening-validation.json"
    timeout     = var.provisioning_timeout
  }
  provisioner "windows-cleanup" {
    profile                = var.cleanup_profile
    component_store        = true
    windows_update         = true
    provisioning_artifacts = true
    artifact_paths = [
      var.netfx_source,
      "C:\\Windows\\Panther\\Unattend.xml",
      "C:\\Windows\\Panther\\Unattend\\Unattend.xml",
      "C:\\Windows\\System32\\Sysprep\\Unattend.xml",
      "C:\\Windows\\Temp\\packer-windows-update.ps1",
      "C:\\Windows\\Temp\\packer-windows-update-elevated.ps1",
      "C:\\Windows\\Temp\\packer-factory-oob.ps1",
      "C:\\Windows\\Temp\\packer-windows-update-pending-reboot-elevated.ps1"
    ]
    pending_reboot_policy = "error"
    validate_system       = true
    required_services     = ["WinRM", "RpcSs"]
    required_features     = ["NetFx3"]
    sysprep               = false
    operation_timeout     = var.provisioning_timeout
    report_path           = "${local.reports}/cleanup.json"
  }
  provisioner "powershell" {
    script           = "scripts/guest/Validate.ps1"
    environment_vars = ["FACTORY_SERVER=${var.server_version}", "FACTORY_EDITION=${var.edition}", "FACTORY_INSTALLATION=${var.installation_type}", "FACTORY_SEARCH=${var.update_search_criteria}"]
    timeout          = var.provisioning_timeout
  }
  provisioner "file" {
    direction   = "download"
    source      = "C:/ProgramData/ImageFactory/validation.json"
    destination = "${local.reports}/validation.json"
  }
  provisioner "file" {
    source      = "scripts/guest/Finalize.ps1"
    destination = "C:/ProgramData/ImageFactory/Finalize.ps1"
  }
  # No guest provisioner follows finalizer staging. The builder owns shutdown.
  post-processor "manifest" {
    output     = "${local.reports}/packer-manifest.json"
    strip_path = false
    custom_data = {
      server_version    = var.server_version
      edition           = var.edition
      installation_type = var.installation_type
      image_version     = var.image_version
      image_id          = local.image_id
      iso_checksum      = var.iso_checksum
    }
  }
}
