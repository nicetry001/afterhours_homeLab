# Scaffolding for Stirling-PDF data folder on vm-docker01
resource "null_resource" "stirling_scaffolding" {
  connection {
    type        = "ssh"
    user        = "afterhours"
    private_key = file("~/.ssh/id_ed25519")
    host        = "192.168.1.170"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/apps/stirling-pdf/trainingData",
      "mkdir -p ~/apps/stirling-pdf/extraConfigs",
      "sudo chown -R 1000:1000 ~/apps/stirling-pdf"
    ]
  }
}

# Stirling-PDF
resource "docker_container" "stirling_pdf" {
  name    = "stirling-pdf"
  image   = "frooodle/s-pdf:latest"
  restart = "unless-stopped"

  env = [
    "DOCKER_ENABLE_SECURITY=false",
    "INSTALL_BOOK_AND_ADVANCED_HTML_OPS=false",
    "LANGS=en_US" # Downloads English OCR pack
  ]

  ports {
    internal = 8080
    external = 8089 # Access it via port 8089 so it doesn't clash with NocoDB
  }

  volumes {
    host_path      = "/home/afterhours/apps/stirling-pdf/trainingData"
    container_path = "/usr/share/tessdata" # Where the OCR AI stores its language models
  }
  
  volumes {
    host_path      = "/home/afterhours/apps/stirling-pdf/extraConfigs"
    container_path = "/configs" 
  }

  networks_advanced {
    name = data.docker_network.frontend.name
  }

  networks_advanced {
    name = data.docker_network.backend.name
  }

  depends_on = [null_resource.stirling_scaffolding]
}