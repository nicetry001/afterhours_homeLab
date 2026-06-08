terraform {
  required_version = ">= 1.5.0"

  cloud {
    organization = "afterhours-homeLab"
    workspaces {
      name = "afterhours-core-network"
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
}
