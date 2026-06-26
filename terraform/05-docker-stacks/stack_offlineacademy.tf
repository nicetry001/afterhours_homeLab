# ==============================================================================
# 🎓 OFFLINEACADEMY LEARNING CENTER
# ==============================================================================
resource "null_resource" "offlineacademy_scaffolding" {
  connection {
    type        = "ssh"
    user        = "afterhours"
    private_key = file("~/.ssh/id_ed25519")
    host        = "192.168.1.170" # ⚠️ Update this if vm-hermes01 uses a different IP
  }
  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/apps/offlineacademy/data",
      "sudo chown -R 1000:1000 ~/apps/offlineacademy/data"
    ]
  }
}

resource "docker_container" "offlineacademy" {
  name    = "offlineacademy"
  image   = "nicetry247/offlineacademy:latest"
  restart = "unless-stopped"
  
  env = [
    "DATABASE_URL=file:/app/prisma/data/dev.db",
    "COURSES_ROOT=/app/My_Courses",
    "NEXT_PUBLIC_APP_URL=http://192.168.1.170:6969", # ⚠️ Update this to match your target VM IP
    "QUIZAPI_KEY=" # Add your QuizAPI key here if you want AI quizzes
  ]

  ports {
    internal = 6767
    external = 6969
  }

  volumes {
    # 🗄️ SQLite Database Persistence Folder
    host_path      = "/home/afterhours/apps/offlineacademy/data"
    container_path = "/app/prisma/data"
  }

  volumes {
    # 💾 Video Course Library Folder (Your Samba/CIFS Network Share)
    host_path      = "/mnt/usb-datastore/courses"
    container_path = "/app/My_Courses"
  }

  # Attach to backend to talk to other containers, frontend to expose to users
  networks_advanced { name = data.docker_network.backend.name }
  networks_advanced { name = data.docker_network.frontend.name }

  depends_on = [null_resource.offlineacademy_scaffolding]
}