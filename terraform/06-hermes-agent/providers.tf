terraform {
  required_version = ">= 1.5.0"

  cloud {
    organization = "afterhours-homeLab"

    workspaces {
      name = "afterhours-hermes-nodes" # Inherits Local mode automatically thanks to your global change!
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
    agent = false
    username = "root"
    private_key = file("~/.ssh/id_ed25519")
  }
}
