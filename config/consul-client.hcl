# Full configuration options can be found at https://www.consul.io/docs/agent/config

datacenter = "home"
data_dir = "/opt/consul"

advertise_addr = "{{ GetPrivateInterfaces | include \"network\" \"192.168.0.0/16\" | attr \"address\" }}"
client_addr = "127.0.0.1 {{ GetPrivateInterfaces | include \"network\" \"192.168.0.0/16\" | attr \"address\" }}"
bind_addr = "{{ GetPrivateInterfaces | include \"network\" \"192.168.0.0/16\" | attr \"address\" }}"

retry_join = ["192.168.0.20", "192.168.0.21", "192.168.0.22"]

# reqired for Consul Connect, see https://developer.hashicorp.com/nomad/docs/integrations/consul-connect
ports {
  grpc = 8502
}
connect {
  enabled = true
}

enable_local_script_checks = true

# enable prometheus metrics
# see https://developer.hashicorp.com/consul/tutorials/kubernetes-features/service-mesh-observability
telemetry {
  prometheus_retention_time = "10m"
  disable_hostname = true
}
