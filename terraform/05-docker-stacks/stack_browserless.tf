# ==========================================
# BROWSERLESS STACK INFRASTRUCTURE
# ==========================================

# ------------------------------------------
# 1. BROWSERLESS SERVICE
# ------------------------------------------
resource "docker_container" "browserless" {
  name    = "browserless"
  image   = "ghcr.io/browserless/chromium:latest"
  restart = "unless-stopped"

  env = [
    "TZ=Asia/Manila",
    
    # 💡 Connection limits prevent the container from eating all your VM's RAM
    "MAX_CONCURRENT_SESSIONS=10",
    "MAX_QUEUE_LENGTH=10",
    
    # 💡 OPTIONAL BUT RECOMMENDED: Uncomment and add a variable to lock down your scraper
    # "TOKEN=${var.browserless_token}" 
  ]

  ports {
    # Browserless listens on 3000 internally. 
    internal = 3000
    external = 3005  # Safely avoids Flowise (3004), Langfuse (3003), Grafana (3002), etc.
  }

  # Only needs backend access to talk to Flowise/n8n/Dify, unless you want it public
  networks_advanced { name = data.docker_network.backend.name }
}