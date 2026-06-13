resource "null_resource" "playit_scaffolding" {
  connection {
    type        = "ssh"
    user        = "afterhours"
    private_key = file("~/.ssh/id_ed25519")
    host        = "192.168.1.170"
  }
  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/apps/playit/data",
      "sudo chown -R 1000:1000 ~/apps/playit/data"
    ]
  }
}

resource "docker_container" "playit" {
  name    = "playit"
  image   = "ghcr.io/playit-cloud/playit-agent:latest"
  restart = "unless-stopped"

# ==============================================================================
# 🔑 HOW TO GENERATE / RECOVER THE PLAYIT SECRET KEY
# ==============================================================================
# The modern Playit Docker image (v1.0+) is headless and will crash-loop if it 
# doesn't receive a SECRET_KEY environment variable on its very first boot.
#
# If you ever need to reset or generate a new key, run this 60-second wizard 
# workaround directly on your Proxmox Docker host terminal:
#
# 1. Download the legacy v0.15.0 binary (which contains the interactive setup wizard):
#    wget https://github.com/playit-cloud/playit-agent/releases/download/v0.15.0/playit-linux-amd64 -O playit-wizard
#    chmod +x playit-wizard
#
# 2. Run the wizard interactively:
#    ./playit-wizard
#
# 3. Open the generated 'playit.gg/claim/...' link in your browser to claim it.
# 4. Press Ctrl+C to stop the wizard, then extract your secret key:
#    cat ~/.config/playit_gg/playit.toml
#
# 5. Copy the long secret_key string, paste it into the 'env' block below, 
#    and run 'terraform apply'.
#
# 6. Clean up the host binary:
#    rm playit-wizard
# ==============================================================================

  env = [
    "SECRET_KEY=${var.playit_secret_key}"
  ]
  # Note: No 'ports' block is needed! 
  # Playit creates an outbound reverse-tunnel to their cloud, completely bypassing your ISP's CGNAT.

  volumes {
    # Maps the local folder we created in the scaffolding to Playit's internal config directory.
    # This ensures your secret key and claim link persist across container rebuilds/restarts.
    host_path      = "/home/afterhours/apps/playit/data"
    container_path = "/etc/playit"
  }

  # Attach to backend to seamlessly communicate with your Windrose game container
  networks_advanced { name = data.docker_network.backend.name }

  depends_on = [null_resource.playit_scaffolding]
}