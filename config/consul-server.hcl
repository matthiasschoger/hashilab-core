# Full configuration options can be found at https://www.consul.io/docs/agent/config

server = true # act as a server with three nodes
bootstrap_expect=3

ui_config {
  enabled = true
  metrics_provider = "prometheus"
  metrics_proxy {
    base_url = "https://prometheus.lab.schoger.net"
  }
}