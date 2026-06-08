global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['192.168.1.169:9100']
        labels:
          instance: 'sproxmox01 (Host)'
          
      - targets: ['node-exporter:9100']
        labels:
          instance: 'vm-docker01 (Docker Node)'
          
      - targets: ['192.168.1.173:9100']
        labels:
          instance: 'vm-hermes01 (AI Agent/Apps)'

      - targets: ['192.168.1.171:9100']
        labels:
          instance: 'lxc-pihole01 (DNS)'

      - targets: ['192.168.1.172:9100']
        labels:
          instance: 'lxc-tailscale01 (VPN)'

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']