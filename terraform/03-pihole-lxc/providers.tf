terraform {
  required_version = ">= 1.5.0"

  cloud {
    organization = "afterhours-homeLab"

    workspaces {
      name = "afterhours-lxc-pihole" # Inherits Local mode automatically thanks to your global change!
    }
  }
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.107.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = true
  ssh {
    agent = true
  }

}
