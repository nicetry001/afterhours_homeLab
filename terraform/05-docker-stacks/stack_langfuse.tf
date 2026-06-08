# ==========================================
# LANGFUSE V3 INFRASTRUCTURE STACK (LATEST)
# ==========================================

# ------------------------------------------
# 1. PATH PERSISTENCE SCAFFOLDING
# ------------------------------------------
resource "null_resource" "langfuse_scaffolding" {
  connection {
    type        = "ssh"
    user        = "afterhours"
    private_key = file(pathexpand("~/.ssh/id_ed25519"))
    host        = "192.168.1.170"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/apps/langfuse/postgres",
      "mkdir -p ~/apps/langfuse/clickhouse",
      "mkdir -p ~/apps/langfuse/minio",
      "sudo chown -R 1000:1000 ~/apps/langfuse"
    ]
  }
}

# ------------------------------------------
# 2. SHARED ENVIRONMENT VARIABLES (DRY)
# ------------------------------------------
locals {
  langfuse_env = [
    "TZ=Asia/Manila",
    "NODE_ENV=production",
    "HOSTNAME=0.0.0.0",
    
    # Core DB 
    "DATABASE_URL=postgresql://langfuse:${urlencode(var.langfuse_db_password)}@langfuse-db:5432/langfuse",
    "REDIS_URL=redis://langfuse-redis:6379",
    
    # ClickHouse
    "CLICKHOUSE_URL=http://langfuse-clickhouse:8123",
    "CLICKHOUSE_USER=langfuse",
    "CLICKHOUSE_PASSWORD=${var.langfuse_db_password}",
    "CLICKHOUSE_DB=langfuse",
    # 🚀 THE FIX: Appended &x-cluster-name= to disable the driver's hardcoded cluster mode
    "CLICKHOUSE_CLUSTER_ENABLED=false",
    "CLICKHOUSE_MIGRATION_URL=clickhouse://langfuse-clickhouse:9000",
    # MinIO / S3
    "LANGFUSE_S3_EVENT_UPLOAD_BUCKET=langfuse",
    "LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT=http://langfuse-minio:9000",
    "LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID=${var.minio_s3_access_key}",
    "LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY=${var.minio_s3_secret_key}",
    "LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE=true",
    "LANGFUSE_S3_EVENT_UPLOAD_REGION=us-east-1",
    
    # Authentication Secrets
    "NEXTAUTH_SECRET=${var.langfuse_nextauth_secret}", 
    "SALT=${var.langfuse_salt}", 
    "NEXTAUTH_URL=http://192.168.1.170:3003", 
    "LANGFUSE_ENABLE_SIGNUP=true"
  ]
}

# ------------------------------------------
# 3. BACKEND STORAGE CONTAINERS
# ------------------------------------------
resource "docker_container" "langfuse_db" {
  name    = "langfuse-db"
  image   = "postgres:16-alpine"
  restart = "unless-stopped"
  env = [
    "POSTGRES_USER=langfuse",
    "POSTGRES_PASSWORD=${var.langfuse_db_password}", 
    "POSTGRES_DB=langfuse"
  ]
  volumes {
    host_path      = "/home/afterhours/apps/langfuse/postgres"
    container_path = "/var/lib/postgresql/data"
  }
  networks_advanced { name = data.docker_network.backend.name }
  depends_on = [null_resource.langfuse_scaffolding]
}

resource "docker_container" "langfuse_redis" {
  name    = "langfuse-redis"
  image   = "redis:7-alpine"
  restart = "unless-stopped"
  networks_advanced { name = data.docker_network.backend.name }
}

resource "docker_container" "langfuse_clickhouse" {
  name    = "langfuse-clickhouse"
  image   = "clickhouse/clickhouse-server:latest"
  restart = "unless-stopped"
  env = [
    "CLICKHOUSE_USER=langfuse",
    "CLICKHOUSE_PASSWORD=${var.langfuse_db_password}",
    "CLICKHOUSE_DB=langfuse"
  ]
  volumes {
    host_path      = "/home/afterhours/apps/langfuse/clickhouse"
    container_path = "/var/lib/clickhouse"
  }
  networks_advanced { name = data.docker_network.backend.name }
  depends_on = [null_resource.langfuse_scaffolding]
}

# ------------------------------------------
# 4. MINIO S3 BUCKET STORAGE
# ------------------------------------------
resource "docker_container" "langfuse_minio" {
  name    = "langfuse-minio"
  image   = "minio/minio:latest"
  restart = "unless-stopped"
  command = ["server", "/data", "--console-address", ":9001"]
  env = [
    "MINIO_ROOT_USER=${var.minio_root_user}",
    "MINIO_ROOT_PASSWORD=${var.minio_root_password}"
  ]
  volumes {
    host_path      = "/home/afterhours/apps/langfuse/minio"
    container_path = "/data"
  }
  networks_advanced { name = data.docker_network.backend.name }
  depends_on = [null_resource.langfuse_scaffolding]
}

# 🚀 Init Container to automatically create the "langfuse" S3 bucket
resource "docker_container" "langfuse_minio_init" {
  name    = "langfuse-minio-init"
  image   = "minio/mc:latest"
  restart = "no"
  entrypoint = ["/bin/sh", "-c"]
  command = [
    "sleep 10 && mc alias set minio http://langfuse-minio:9000 ${var.minio_root_user} ${var.minio_root_password} && mc mb minio/langfuse || true"
  ]
  networks_advanced { name = data.docker_network.backend.name }
  depends_on = [docker_container.langfuse_minio]

  lifecycle {
    ignore_changes = all
  }
}

# ------------------------------------------
# 5. LANGFUSE V3 ENGINES (Web + Worker)
# ------------------------------------------
resource "docker_container" "langfuse_worker" {
  name    = "langfuse-worker"
  image   = "langfuse/langfuse-worker:3" 
  restart = "unless-stopped"
  env     = local.langfuse_env
  
  networks_advanced { name = data.docker_network.backend.name }
  
  depends_on = [
    docker_container.langfuse_db,
    docker_container.langfuse_redis,
    docker_container.langfuse_clickhouse,
    docker_container.langfuse_minio_init
  ]
}

resource "docker_container" "langfuse_api" {
  name    = "langfuse-api"
  image   = "langfuse/langfuse:3" 
  restart = "unless-stopped"
  env     = local.langfuse_env

  ports {
    internal = 3000
    external = 3003
    ip       = "0.0.0.0"
    protocol = "tcp"
  }

  networks_advanced { name = data.docker_network.frontend.name }
  networks_advanced { name = data.docker_network.backend.name }

  depends_on = [docker_container.langfuse_worker]
}