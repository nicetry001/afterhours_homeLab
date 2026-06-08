
resource "proxmox_virtual_environment_container" "lxc-pihole01" {
  node_name   = "sproxmox01"
  vm_id       = 200
  description = "Managed by Terraform - Ad-Blocking DNS Server"
  tags        = ["terraform", "dns"]

  unprivileged = true # Enforces critical kernel boundary isolation

  features {
    nesting = true
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
    type             = "debian"
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 512
    swap      = 512
  }

  disk {
    datastore_id = "local-lvm"
    size         = 8
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  network_interface {
    name   = "eth1"
    bridge = "vnet0"
  }

  initialization {
    hostname = "lxc-pihole01"

    ip_config {
      ipv4 {
        address = "192.168.1.171/24"
        gateway = "192.168.1.1"
      }
    }

    ip_config {
      ipv4 {
        address = "10.6.7.171/24"
      }
    }

    user_account {
      keys = [var.afterhours_pub_key]
    }
  }

  provisioner "remote-exec" {
    inline = [
      # 1. Update OS and install dependencies (added ca-certificates for secure downloads)
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update",
      "apt-get install -y curl sqlite3 ca-certificates",

      # 2. Pre-seed Pi-hole's required configuration so unattended mode works
      "mkdir -p /etc/pihole",
      "cat <<EOF > /etc/pihole/setupVars.conf",
      "PIHOLE_INTERFACE=eth0",
      "IPv4_address=192.168.1.171/24",
      "PIHOLE_DNS_1=8.8.8.8",
      "PIHOLE_DNS_2=1.1.1.1",
      "QUERY_LOGGING=true",
      "INSTALL_WEB_SERVER=true",
      "INSTALL_WEB_INTERFACE=true",
      "LIGHTTPD_ENABLED=true",
      "EOF",

      # 3. Install Pi-hole silently
      "curl -sSL https://install.pi-hole.net -o install.sh",
      "PIHOLE_SKIP_OS_CHECK=true bash install.sh --unattended",

      # Give SQLite a few seconds to unlock the database after installation
      "sleep 5",

      # 4. Inject the Gold Standard blocklists
      "sqlite3 /etc/pihole/gravity.db \"INSERT OR IGNORE INTO adlist (address, enabled, comment) VALUES ('https://raw.githubusercontent.com/hagezi/dns-blocklists/main/adblock/pro.txt', 1, 'HaGeZi Pro');\"",
      "sqlite3 /etc/pihole/gravity.db \"INSERT OR IGNORE INTO adlist (address, enabled, comment) VALUES ('https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts', 1, 'Steven Black Master');\"",

      # 5. Compile gravity and set password using ABSOLUTE paths (fixes the 127 error!)
      "/usr/local/bin/pihole -g",
      "/usr/local/bin/pihole setpassword '${var.pihole_password}'",
      "pihole-FTL --config ntp.sync.active false" # Disable NTP sync in FTL to prevent time drift issues in LXC environments, since proxmox handles time synchronization for the container
    ]

    connection {
      type        = "ssh"
      user        = "root"
      private_key = file("~/.ssh/id_ed25519") # Terraform uses your key to get in
      host        = "192.168.1.171"
    }
  }


}