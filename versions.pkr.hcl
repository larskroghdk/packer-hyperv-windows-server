packer {
  required_version = ">= 1.16.2, < 2.0.0"
  required_plugins {
    windows-update = {
      source  = "github.com/rgl/windows-update"
      version = "= 0.18.4"
    }
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = "= 1.1.5"
    }
    windows-features = {
      source  = "github.com/larskroghdk/windows-features"
      version = "= 1.0.0"
    }
    windows-optimize = {
      source  = "github.com/larskroghdk/windows-optimize"
      version = "= 1.0.0"
    }
    windows-harden = {
      source  = "github.com/larskroghdk/windows-harden"
      version = "= 0.1.0"
    }
    windows-cleanup = {
      source  = "github.com/larskroghdk/windows-cleanup"
      version = "= 0.1.0"
    }
  }
}
