# ==========================================
# FLOWISE STACK INFRASTRUCTURE
# ==========================================
# ------------------------------------------
# 1. DIRECTORY SCAFFOLDING
# ------------------------------------------
resource "null_resource" "flowise_scaffolding" {
  connection {
    type        = "ssh"
    user        = "afterhours"
    # FIXED: Wrapped in pathexpand() so Terraform can read your local SSH key
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    host        = "192.168.1.170"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/apps/flowise/data",
      "sudo chown -R 1000:1000 ~/apps/flowise"
    ]
  }
}

# ------------------------------------------
# 2. EXPLICIT IMAGE PULL (Prevents deployment state freezes)
# ------------------------------------------
resource "docker_image" "flowise" {
  name         = "flowiseai/flowise:latest"
  keep_locally = true
}

# ------------------------------------------
# 3. FLOWISE APPLICATION CORE (UI + API)
# ------------------------------------------
resource "docker_container" "flowise" {
  name    = "flowise"
  # Pulls from the explicit image resource
  image   = docker_image.flowise.image_id
  restart = "unless-stopped"

  env = [
    # Basic authentication
    "FLOWISE_USERNAME=admin",
    "FLOWISE_PASSWORD=${var.flowise_password}",
    
    # Database config (SQLite default)
    "DATABASE_TYPE=sqlite",
    "DATABASE_PATH=/data",
    
    # FIXED: Persistence paths mapped into your volume (protects keys, canvas configs, and logs)
    "SECRETKEY_PATH=/data",
    "BLOB_STORAGE_PATH=/data/storage",
    "LOG_PATH=/data/logs"
  ]

  ports {
    # FIXED: Flowise internally listens on port 3000 by default, not 3001!
    internal = 3000
    external = 3004  # Safely avoids conflict with Dify (3000), Grafana (3002), Langfuse (3003)
  }

  volumes {
    host_path      = "/home/afterhours/apps/flowise/data"
    container_path = "/data"
  }

  networks_advanced { name = data.docker_network.frontend.name }
  networks_advanced { name = data.docker_network.backend.name }

  depends_on = [null_resource.flowise_scaffolding]
}