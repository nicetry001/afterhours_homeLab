# ==============================================================================
# 🎮 WINDROSE DEDICATED SERVER (P2P INVITE MODE)
# ==============================================================================
resource "null_resource" "windrose_scaffolding" {
  connection {
    type        = "ssh"
    user        = "afterhours"
    private_key = file("~/.ssh/id_ed25519")
    host        = "192.168.1.170"
  }
  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/apps/windrose/data",
      "sudo chown -R 1000:1000 ~/apps/windrose/data"
    ]
  }
}

resource "docker_container" "windrose" {
  name    = "windrose"
  # Using wine-staging to ensure the C++ 2022 runtimes are installed for v0.10.0.6
  image   = "indifferentbroccoli/windrose-server-docker:wine-staging" 
  restart = "unless-stopped"
  
  # ⚠️ CRITICAL: Docker's default security blocks Wine from opening network sockets. 
  # Without this line, the server will silently crash on boot.
  security_opts = ["seccomp=unconfined"]
  network_mode = "host"

  env = [
    # Permissions
    "PUID=1000",
    "PGID=1000",

    # Server Identity & Rules
    "SERVER_NAME=Afterhours Pirate Ship",
    "SERVER_PASSWORD=${var.windrose_server_password}", 
    "MAX_PLAYERS=8",
    
    # Networking & Invites (Forces Epic P2P System)
    "USE_DIRECT_CONNECTION=false", 
    "INVITE_CODE=${var.windrose_invite_code}", 
    "P2P_PROXY_ADDRESS=192.168.1.170",
    "UPDATE_ON_START=true", 
    "WINE_VERBOSE=false"
  ]

  # Exposing only the standard UDP ports. 
  # (TCP is ignored since Epic's P2P Invite system handles the NAT punch-through!)
  ports {
    internal = 7777
    external = 7777
    protocol = "udp"
  }
  ports {
    internal = 7778
    external = 7778
    protocol = "udp"
  }

  volumes {
    # Maps the host data folder to the official image directory.
    # The container will automatically build the R5 and Saved folders inside here!
    host_path      = "/home/afterhours/apps/windrose/data"
    container_path = "/home/steam/server-files"
  }


  depends_on = [null_resource.windrose_scaffolding]
}