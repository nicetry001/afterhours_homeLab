# ==========================================
# DIFY AI STACK INFRASTRUCTURE (dify.tf)
# ==========================================

# ------------------------------------------
# 1. DIRECTORY SCAFFOLDING
# ------------------------------------------
resource "null_resource" "dify_scaffolding" {
  connection {
    type        = "ssh"
    user        = "afterhours"
    private_key = file("~/.ssh/id_ed25519")
    host        = "192.168.1.170"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/apps/dify/db",
      "mkdir -p ~/apps/dify/qdrant",
      "mkdir -p ~/apps/dify/plugins",
      "sudo chown -R 1000:1000 ~/apps/dify"
    ]
  }
}

# ------------------------------------------
# 2. CORE BACKEND SERVICES (DB, CACHE, VECTOR)
# ------------------------------------------

# Qdrant Vector Database
resource "docker_container" "qdrant" {
  name    = "dify-qdrant"
  image   = "qdrant/qdrant:latest"
  restart = "unless-stopped"
  
  ports {
    internal = 6333
    external = 6333
  }

  volumes {
    host_path      = "/home/afterhours/apps/dify/qdrant"
    container_path = "/qdrant/storage"
  }

  networks_advanced { name = data.docker_network.backend.name }
  depends_on = [null_resource.dify_scaffolding]
}

# Redis Cache
resource "docker_container" "dify_redis" {
  name    = "dify-redis"
  image   = "redis:6-alpine"
  restart = "unless-stopped"
  
  networks_advanced { name = data.docker_network.backend.name }
}

# Dify Core Database (Postgres)
resource "docker_container" "dify_db" {
  name    = "dify-db"
  image   = "postgres:15-alpine"
  restart = "unless-stopped"
  
  env = [
    "POSTGRES_USER=postgres",
    "POSTGRES_PASSWORD=${var.dify_db_pass}",
    "POSTGRES_DB=dify"
  ]
  ports {
    internal = 5432
    external = 5432
  }

  volumes {
    host_path      = "/home/afterhours/apps/dify/db"
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced { name = data.docker_network.backend.name }
  depends_on = [null_resource.dify_scaffolding]
}

# ------------------------------------------
# 3. DIFY APPLICATION CORE (API, WORKER, WEB)
# ------------------------------------------

# Shared Environment Variables for Dify Engine
# Shared Environment Variables for Dify Engine
locals {
  dify_env = [
    "SECRET_KEY=${var.dify_secret_key}",
    "DB_USERNAME=postgres",
    "DB_PASSWORD=${var.dify_db_pass}",
    "DB_HOST=dify-db",
    "DB_PORT=5432",
    "DB_DATABASE=dify",
    "REDIS_HOST=dify-redis",
    "REDIS_PORT=6379",
    "CELERY_BROKER_URL=redis://dify-redis:6379/1",
    
    # Vector Store Configuration (Qdrant)
    "VECTOR_STORE=qdrant",
    "QDRANT_HOST=dify-qdrant",
    "QDRANT_PORT=6333",
    
    # Server Settings (Ports aligned to leave 80/443 free for future Nginx)
    "APP_WEB_URL=http://192.168.1.170:3000",
    "CONSOLE_WEB_URL=http://192.168.1.170:3000",
    "API_URL=http://192.168.1.170:5001",
    "LOG_LEVEL=INFO",

    # Proper Dify Internal Microservice Authentication
    "INNER_API=true",
    "INNER_API_KEY=${var.dify_plugin_token}",
    "PLUGIN_DAEMON_KEY=${var.dify_secret_key}",
    "PLUGIN_DAEMON_URL=http://192.168.1.170:5002",
  ]
}

# Dify Plugin System Daemon
resource "docker_container" "dify_plugin_daemon" {
  name    = "dify-plugin-daemon"
  image   = "langgenius/dify-plugin-daemon:0.6.0-local"
  restart = "unless-stopped"

  env = [
    "MODE=production",
    "LOG_LEVEL=INFO",
    "SERVER_PORT=5002",
    "SERVER_KEY=${var.dify_secret_key}",
    "DIFY_INNER_API_URL=http://192.168.1.170:5001",
    "DIFY_INNER_API_KEY=${var.dify_plugin_token}",
    "DB_USERNAME=postgres",
    "DB_PASSWORD=${var.dify_db_pass}",
    "DB_HOST=192.168.1.170",
    "DB_PORT=5432",
    "DB_DATABASE=dify",
    "STORAGE_DIR=/app/storage",
    "PLUGIN_REMOTE_INSTALLING_HOST=0.0.0.0",
    "PLUGIN_REMOTE_INSTALLING_PORT=5003",
    "PLUGIN_WORKING_PATH=/app/storage/cwd",
    "REDIS_HOST=dify-redis",
    "REDIS_PORT=6379"
  ]

  ports {
    internal = 5002
    external = 5002
  }

  networks_advanced { name = data.docker_network.frontend.name }
  networks_advanced { name = data.docker_network.backend.name }

  volumes {
    host_path      = "/home/afterhours/apps/dify/plugins"
    container_path = "/app/storage"
  }

  depends_on = [
    null_resource.dify_scaffolding,
    docker_container.dify_db,
    
  ]
}

# Dify Server API Engine
resource "docker_container" "dify_api" {
  name    = "dify-api"
  image   = "langgenius/dify-api:latest"
  restart = "unless-stopped"
  command = ["/bin/sh", "-c", "/usr/src/app/docker/entrypoint.sh"]
  
  env = local.dify_env

  ports {
    internal = 5001
    external = 5001
  }

  networks_advanced { name = data.docker_network.backend.name }
  networks_advanced { name = data.docker_network.frontend.name }
  
  depends_on = [
    docker_container.dify_db, 
    docker_container.dify_redis, 
    docker_container.qdrant
  ]
}

# Dify Background Worker
resource "docker_container" "dify_worker" {
  name    = "dify-worker"
  image   = "langgenius/dify-api:latest"
  restart = "unless-stopped"
  command = ["/bin/sh", "-c", "/usr/src/app/docker/entrypoint.sh"]
  
  env = concat(local.dify_env, ["MODE=worker"])

  networks_advanced { name = data.docker_network.backend.name }
  
  depends_on = [docker_container.dify_api]
}

# Dify Web Frontend Visual UI
resource "docker_container" "dify_web" {
  name    = "dify-web"
  image   = "langgenius/dify-web:latest"
  restart = "unless-stopped"
  
  env = [
    "CONSOLE_API_URL=http://192.168.1.170:5001",
    "APP_API_URL=http://192.168.1.170:5001"
  ]

  ports {
    internal = 3000
    external = 3000  
  }

  networks_advanced { name = data.docker_network.frontend.name }
  
  depends_on = [docker_container.dify_api]
}