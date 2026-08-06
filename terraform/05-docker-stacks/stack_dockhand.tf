# ==============================================================================
# 🐳 DOCKHAND DOCKER MANAGEMENT STACK
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. DIRECTORY SCAFFOLDING
# ------------------------------------------------------------------------------

resource "null_resource" "dockhand_scaffolding" {
  connection {
    type        = "ssh"
    user        = "afterhours"
    private_key = file("~/.ssh/id_ed25519")
    host        = "192.168.1.170"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/apps/dockhand",
      "sudo chown -R 1000:1000 ~/apps/dockhand"
    ]
  }
}

# ------------------------------------------------------------------------------
# 2. DOCKHAND CONTAINER
# ------------------------------------------------------------------------------

resource "docker_container" "dockhand" {
  name    = "dockhand"
  image   = "fnsys/dockhand:latest"
  restart = "unless-stopped"

  env = [
    "PUID=1000",
    "PGID=1000",
    "TZ=Asia/Manila",

    # Matching host and container paths are recommended when Dockhand
    # manages Compose stacks that contain relative bind mounts.
    "DATA_DIR=/home/afterhours/apps/dockhand"
  ]

  # Replace 999 with:
  # stat -c '%g' /var/run/docker.sock
  group_add = ["986"]

  ports {
    internal = 3000
    external = 3010
  }

  # Local Docker daemon management.
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }

  # Persistent database, stack definitions and Git data.
  # The path intentionally matches on the host and inside the container.
  volumes {
    host_path      = "/home/afterhours/apps/dockhand"
    container_path = "/home/afterhours/apps/dockhand"
  }

  networks_advanced {
    name = data.docker_network.backend.name
  }

  networks_advanced {
    name = data.docker_network.frontend.name
  }

  depends_on = [
    null_resource.dockhand_scaffolding
  ]
}