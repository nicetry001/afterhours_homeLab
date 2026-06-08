# Scaffolding for Cloudflare Tunnels data folder on vm-docker01
resource "null_resource" "cloudflared_scaffolding" {
  connection {
    type        = "ssh"
    user        = "afterhours"
    # FIXED: Wrapped in pathexpand() so Terraform can find your local SSH key
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    host        = "192.168.1.170"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/apps/cloudflared/config",
      "sudo chown -R 1000:1000 ~/apps/cloudflared"
    ]
  }
}

# Cloudflare Tunnels (cloudflared)
resource "docker_container" "cloudflared" {
  name    = "cloudflared"
  image   = "cloudflare/cloudflared:latest"
  restart = "unless-stopped"

  # FIXED: Tells the container to explicitly execute the tunnel loop on startup
  command = ["tunnel", "--no-autoupdate", "run"]

  env = [
    "TZ=Asia/Manila",
    "TUNNEL_TOKEN=${var.cloudflare_tunnel_token}"
  ]

  volumes {
    host_path      = "/home/afterhours/apps/cloudflared/config"
    container_path = "/etc/cloudflared"
  }

  networks_advanced {
    name = data.docker_network.backend.name
  }

  depends_on = [null_resource.cloudflared_scaffolding]
}