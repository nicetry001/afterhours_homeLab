terraform {
  required_version = ">= 1.5.0"

  cloud {
    organization = "afterhours-homeLab"
    workspaces {
      name = "afterhours-docker-stacks"
    }
  }

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }

    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.4.0"
    }
  }
}

provider "docker" {
  host     = "ssh://afterhours@192.168.1.170:22"
  ssh_opts = ["-o", "StrictHostKeyChecking=no", "-i", pathexpand("~/.ssh/id_ed25519")]
}