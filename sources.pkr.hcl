locals {
  image_id = "ws${var.server_version}-${lower(var.edition)}-${lower(var.installation_type)}-${var.image_version}-${var.build_id}"
  reports  = "${var.report_directory}/${local.image_id}"
  # Escape ampersands first so generated entities are not escaped twice.
  password_xml   = replace(replace(replace(replace(replace(var.administrator_password, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), "\"", "&quot;"), "'", "&apos;")
  image_name_xml = replace(replace(replace(var.image_name, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
}

source "hyperv-iso" "windows" {
  vm_name               = local.image_id
  generation            = 2
  enable_secure_boot    = true
  secure_boot_template  = "MicrosoftWindows"
  cpus                  = var.cpus
  memory                = var.memory_mb
  disk_size             = var.disk_size_mb
  enable_dynamic_memory = false
  switch_name           = var.switch_name
  iso_url               = var.iso_path
  iso_checksum          = var.iso_checksum
  headless              = true
  boot_wait             = "2s"
  boot_command          = ["<spacebar><wait1><spacebar><wait1><spacebar><wait1><spacebar>"]
  first_boot_device     = "DVD"
  cd_label              = "PACKER_BOOT"
  cd_content = {
    "Autounattend.xml" = templatefile("${path.root}/http/autounattend/Autounattend.xml.pkrtpl", {
      image_name = local.image_name_xml
      password   = local.password_xml
      locale     = var.locale
      keyboard   = var.keyboard_layout
      time_zone  = replace(replace(var.time_zone, "&", "&amp;"), "<", "&lt;")
    })
    "Bootstrap.ps1"  = file("${path.root}/scripts/bootstrap/Bootstrap.ps1")
    "bootstrap.json" = jsonencode({ port = var.winrm_port, allowed_address = var.winrm_allowed_address, netfx_source = var.netfx_source })
  }
  communicator   = "winrm"
  winrm_username = var.administrator_username
  winrm_password = var.administrator_password
  winrm_use_ssl  = true
  winrm_use_ntlm = true
  # Bootstrap creates a unique short-lived self-signed certificate. The build
  # switch must be isolated; the certificate is removed before generalization.
  winrm_insecure   = true
  winrm_port       = var.winrm_port
  winrm_timeout    = var.winrm_timeout
  shutdown_command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\ProgramData\\ImageFactory\\Finalize.ps1"
  shutdown_timeout = var.shutdown_timeout
  skip_export      = true
  skip_compaction  = false
  keep_registered  = false
  output_directory = "${var.output_directory}/${local.image_id}"
}
