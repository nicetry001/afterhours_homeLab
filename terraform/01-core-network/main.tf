# 1. Create the SDN Simple Zone
resource "proxmox_sdn_zone_simple" "isolated_zone" {
  id   = "backend"
  ipam = "pve"
}

# 2. Create the Virtual Network (The isolated switch)
resource "proxmox_sdn_vnet" "internal_vnet" {
  id   = "vnet0"
  zone = proxmox_sdn_zone_simple.isolated_zone.id
}

# 3. Define your custom 10.6.7.0/24 Subnet
resource "proxmox_sdn_subnet" "internal_subnet" {
  vnet = proxmox_sdn_vnet.internal_vnet.id
  
  cidr    = "10.6.7.0/24"
  gateway = "10.6.7.1"
  snat    = true

  # Proxmox will automatically distribute IPs in this pool
  dhcp_range = {
    start_address = "10.6.7.100"
    end_address   = "10.6.7.200"
  }
}

# 4. Apply the SDN configuration to the Proxmox node
resource "proxmox_sdn_applier" "apply_sdn" {
  depends_on = [
    proxmox_sdn_subnet.internal_subnet
  ]
}