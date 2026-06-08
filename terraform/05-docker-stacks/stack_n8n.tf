# We use a tiny script just to ensure the host folder exists with the correct 1000:1000 permissions
resource "null_resource" "n8n_scaffolding" {
  connection {
    type        = "ssh"
    user        = "afterhours"
    private_key = file("~/.ssh/id_ed25519")
    host        = "192.168.1.170"
  }
  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/apps/n8n/data",
      "sudo chown -R 1000:1000 ~/apps/n8n/data"
    ]
  }
}

resource "docker_container" "n8n" {
  name    = "n8n"
  image   = "docker.n8n.io/n8nio/n8n:latest"
  restart = "unless-stopped"
  
  env = [
    "GENERIC_TIMEZONE=Asia/Manila",
    "TZ=Asia/Manila",
    "N8N_SECURE_COOKIE=false"
  ]

  ports {
    internal = 5678
    external = 5678
  }

  volumes {
    # Maps the local folder we created in the scaffolding to the internal n8n data folder
    host_path      = "/home/afterhours/apps/n8n/data"
    container_path = "/home/node/.n8n"
  }

  # Attach to backend to talk to other containers, frontend to expose to users
  networks_advanced { name = data.docker_network.backend.name }
  networks_advanced { name = data.docker_network.frontend.name }

  depends_on = [null_resource.n8n_scaffolding]
}