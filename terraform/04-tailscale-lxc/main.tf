resource "proxmox_virtual_environment_container" "tailscale_lxc" {
  node_name    = "sproxmox01"
  vm_id        = 201
  description  = "Tailscale Subnet Router"
  tags         = ["vpn", "terraform"]
  unprivileged = true

  features {
    nesting = true
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst" 
    type             = "debian"
  }

  cpu { cores = 1 }
  memory { 
    dedicated = 512 
    swap      = 512
  }
  disk { 
    datastore_id = "local-lvm"
    size         = 4 
  }

  network_interface { 
    name   = "eth0"
    bridge = "vmbr0"
    firewall = false
  }
  network_interface { 
    name   = "eth1"
    bridge = "vnet0"
    firewall = false
  }

  initialization {
    hostname = "lxc-tailscale01"
    ip_config {
      ipv4 {
        address = "192.168.1.172/24"
        gateway = "192.168.1.1"
      }
    }
    ip_config {
      ipv4 { address = "10.6.7.172/24" }
    }
    user_account {
      keys = [var.afterhours_pub_key]
    }
  }
}

# Separated Provisioner with Host-Wait Protection
resource "null_resource" "tailscale_provisioner" {
  depends_on = [proxmox_virtual_environment_container.tailscale_lxc]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file("~/.ssh/id_ed25519")
    host        = "192.168.1.172"
  }

  provisioner "file" {
    content     = var.tailscale_auth_key
    destination = "/tmp/tailscale_key"
  }

  provisioner "remote-exec" {
    inline = [
      # 1. The Smart Loop: Holds the script until you link the hardware!
      # pct set 201 -dev0 /dev/net/tun # run this in the Proxmox host shell after deployment to link the TUN device
      # pct reboot 201 (reboot tailscale after deployment is complete and the TUN device is linked)
      "until [ -c /dev/net/tun ]; do echo 'Waiting for you to run pct set on the Proxmox host shell...'; sleep 5; done",
      "echo 'TUN device detected! Proceeding with installation...'",

      # 2. Update system and install prerequisite tools
      "apt-get update",
      "apt-get install -y curl gpg systemd",

      # 3. Add Tailscale Repo for Debian 13 (Trixie)
      "mkdir -p -m 0755 /usr/share/keyrings",
      "curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null",
      "curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list",
      
      # 4. Install Tailscale (Standard Kernel Mode)
      "apt-get update && apt-get install -y tailscale",
      "systemctl daemon-reload",
      "systemctl restart tailscaled",
      "sleep 5",

      # 5. Enable Kernel IP Routing for the container namespace
      # Enable Kernel IP Routing
      "echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.d/99-tailscale.conf",
      "sysctl -w net.ipv4.ip_forward=1 || true",

      # Connect to the mesh by reading the local file with $( ), then shred the file
      "tailscale up --authkey=$(cat /tmp/tailscale_key) --advertise-routes=192.168.1.0/24,10.6.7.0/24 2> /tmp/tailscale_err.log || (cat /tmp/tailscale_err.log && exit 1)",
      "rm -f /tmp/tailscale_key"
    ]
  }
}