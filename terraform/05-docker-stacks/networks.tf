resource "null_resource" "core_networks" {
  # This creates your 3-Tier Enterprise network architecture
  connection {
    type        = "ssh"
    user        = "afterhours"
    private_key = file("~/.ssh/id_ed25519")
    host        = "192.168.1.170"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo docker network create net-frontend || true",
      "sudo docker network create net-backend || true",
      "sudo docker network create net-database || true"
    ]
  }
}