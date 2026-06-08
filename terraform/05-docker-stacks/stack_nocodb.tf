# Scaffolding for NocoDB data folder on vm-docker01
resource "null_resource" "nocodb_scaffolding" {
  connection {
    type        = "ssh"
    user        = "afterhours"
    private_key = file("~/.ssh/id_ed25519")
    host        = "192.168.1.170"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/apps/nocodb/data",
      "sudo chown -R 1000:1000 ~/apps/nocodb/data"
    ]
  }
}

# NocoDB
resource "docker_container" "nocodb" {
  name    = "nocodb"
  image   = "nocodb/nocodb:latest"
  restart = "unless-stopped"

  env = [
    # 💡 REMOVED "NC_DB=sqlite" to prevent the Invalid URL crash
    "NC_LOG_LEVEL=info",
    "NC_AUTH_JWT_SECRET=${var.nocodb_jwt_secret}",
    "NC_AUTH_LOCAL_STRATEGY=***", // Ensure this matches your strategy config
    "NC_AUTH_LOCAL_ENABLE_SIGN_UP=true",
    "NC_PUBLIC_URL=http://192.168.1.170:8081"
  ]

  ports {
    internal = 8080  # 💡 Fixed to match NocoDB's default internal port
    external = 8081
  }

  volumes {
    host_path      = "/home/afterhours/apps/nocodb/data"
    container_path = "/usr/app/data"
  }

  networks_advanced {
    name = data.docker_network.frontend.name
  }

  networks_advanced {
    name = data.docker_network.backend.name
  }

  depends_on = [null_resource.nocodb_scaffolding]
}