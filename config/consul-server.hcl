# Full configuration options can be found at https://www.consul.io/docs/agent/config

datacenter = "home"
data_dir = "/opt/consul"

advertise_addr = "{{ GetPrivateInterfaces | include \"network\" \"192.168.0.0/16\" | attr \"address\" }}"
bind_addr = "{{ GetPrivateInterfaces | include \"network\" \"192.168.0.0/16\" | attr \"address\" }}"
client_addr = "0.0.0.0"

retry_join = ["192.168.0.20", "192.168.0.21", "192.168.0.22"]

server = true # act as a server with three nodes
bootstrap_expect=3

# reqired for Consul Connect, see https://developer.hashicorp.com/nomad/docs/integrations/consul-connect
ports {
  grpc = 8502
}

connect {
  enabled = true
}

# enable prometheus metrics
# see https://developer.hashicorp.com/consul/tutorials/kubernetes-features/service-mesh-observability
telemetry {
  prometheus_retention_time = "10m"
  disable_hostname = true
}

ui_config {
  enabled = true
  metrics_provider = "prometheus"
  metrics_proxy {
    base_url = "https://prometheus.lab.home"
  }
  dashboard_url_templates {
    service = "https://grafana.lab.home/d/{{Service.Meta.dashboard}}"
  }
}