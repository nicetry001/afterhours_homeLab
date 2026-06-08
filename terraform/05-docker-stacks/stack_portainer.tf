resource "null_resource" "deploy_portainer" {
  # Forces Terraform to redeploy the stack if you run 'apply' again
  # triggers = {
  #   always_run = timestamp()
  # }

  connection {
    type        = "ssh"
    user        = "afterhours"
    private_key = file("~/.ssh/id_ed25519")
    host        = "192.168.1.170"
  }

  # 1. Prepare the remote directory structure
  provisioner "remote-exec" {
    inline = [
      "mkdir -p ~/apps/portainer/data"
    ]
  }

  # 2. Write the Portainer configuration file natively
  provisioner "file" {
    destination = "/home/afterhours/apps/portainer/docker-compose.yml"
    content     = <<-EOT
      version: '3.8'

      services:
        portainer:
          image: portainer/portainer-ce:latest
          container_name: portainer
          restart: unless-stopped
          ports:
            - "9000:9000"
          volumes:
            - /var/run/docker.sock:/var/run/docker.sock
            - ./data:/data
    EOT
  }

  # 3. Trigger the build and launch process
  provisioner "remote-exec" {
    inline = [
      "cd ~/apps/portainer",
      "sudo docker compose up -d"
    ]
  }
}