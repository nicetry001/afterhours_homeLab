# Scaffolding for Prometheus + Grafana data folders on vm-docker01
resource "null_resource" "prometheus_grafana_scaffolding" {
  connection {
    type        = "ssh"
    user        = "afterhours"
    private_key = file("~/.ssh/id_ed25519")
    host        = "192.168.1.170"
  }

  # Step 1: Securely create the required system directories
  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/apps/prometheus-grafana/prometheus/data",
      "mkdir -p ~/apps/prometheus-grafana/prometheus/config",
      "mkdir -p ~/apps/prometheus-grafana/grafana/data"
    ]
  }

  # Step 2: 🚀 Stream the rendered configuration template file natively without string conflicts
  provisioner "file" {
    content     = templatefile("${path.module}/prometheus.tpl", {})
    destination = "/home/afterhours/apps/prometheus-grafana/prometheus/config/prometheus.yml"
  }

  # Step 3: Correct user ownership permissions for the folders
  provisioner "remote-exec" {
    inline = [
      "sudo chown -R 1000:1000 ~/apps/prometheus-grafana/prometheus ~/apps/prometheus-grafana/grafana"
    ]
  }
}

# ------------------------------------------
# HARDWARE SENSOR (Node Exporter)
# ------------------------------------------
resource "docker_container" "node_exporter" {
  name    = "node-exporter"
  image   = "prom/node-exporter:latest"
  restart = "unless-stopped"
  hostname = "vm-docker01"
  
  # Needs to see the host's raw file system to measure disk/CPU
  volumes {
    host_path      = "/"
    container_path = "/rootfs"
    read_only      = true
  }
  volumes {
    host_path      = "/proc"
    container_path = "/host/proc"
    read_only      = true
  }
  volumes {
    host_path      = "/sys"
    container_path = "/host/sys"
    read_only      = true
  }

  command = [
    "--path.procfs=/host/proc",
    "--path.sysfs=/host/sys",
    "--path.rootfs=/rootfs"
  ]

  networks_advanced { name = data.docker_network.backend.name }
}

# ------------------------------------------
# DOCKER SENSOR (cAdvisor)
# ------------------------------------------
resource "docker_container" "cadvisor" {
  name    = "cadvisor"
  image   = "gcr.io/cadvisor/cadvisor:latest"
  restart = "unless-stopped"
  
  # Needs privileged access to Docker's internal engine sockets
  privileged = true

  volumes {
    host_path      = "/"
    container_path = "/rootfs"
    read_only      = true
  }
  volumes {
    host_path      = "/var/run"
    container_path = "/var/run"
    read_only      = false
  }
  volumes {
    host_path      = "/sys"
    container_path = "/sys"
    read_only      = true
  }
  volumes {
    host_path      = "/var/lib/docker"
    container_path = "/var/lib/docker"
    read_only      = true
  }

  networks_advanced { name = data.docker_network.backend.name }
}

# Prometheus
resource "docker_container" "prometheus" {
  name    = "prometheus"
  image   = "prom/prometheus:latest"
  restart = "unless-stopped"
  
  # Run as the user defined in your scaffolding chown command
  user = "1000:1000" 

  env = [
    "TZ=Asia/Manila"
  ]

  ports {
    internal = 9090
    external = 9090
  }

  # Data volume
  volumes {
    host_path      = "/home/afterhours/apps/prometheus-grafana/prometheus/data"
    container_path = "/prometheus"
  }

  # Config file volume
  volumes {
    host_path      = "/home/afterhours/apps/prometheus-grafana/prometheus/config/prometheus.yml"
    container_path = "/etc/prometheus/prometheus.yml"
  }

  networks_advanced {
    name = data.docker_network.frontend.name
  }

  networks_advanced {
    name = data.docker_network.backend.name
  }

  depends_on = [null_resource.prometheus_grafana_scaffolding]
}

# Grafana
resource "docker_container" "grafana" {
  name    = "grafana"
  image   = "grafana/grafana:latest"
  restart = "unless-stopped"
  
  # Run as the user defined in your scaffolding chown command
  user = "1000:1000"

  env = [
    "TZ=Asia/Manila",
    "GF_SERVER_ROOT_URL=http://192.168.1.170:3002",
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}"
  ]

  ports {
    internal = 3000
    external = 3002
  }

  volumes {
    host_path      = "/home/afterhours/apps/prometheus-grafana/grafana/data"
    container_path = "/var/lib/grafana"
  }

  networks_advanced {
    name = data.docker_network.frontend.name
  }

  networks_advanced {
    name = data.docker_network.backend.name
  }

  depends_on = [null_resource.prometheus_grafana_scaffolding]
}