# Full configuration options can be found at https://www.nomadproject.io/docs/configuration

datacenter = "home"
data_dir  = "/opt/nomad/data"

bind_addr = "0.0.0.0"

client {
  enabled = true
  servers = ["192.168.0.20", "192.168.0.21", "192.168.0.22"]
}

consul {
  address = "localhost:8500"
}

plugin "raw_exec" {
  config {
    enabled = true
  }
}

plugin "docker" {
  config {
    allow_privileged = true
    # default caps
    allow_caps = ["audit_write", "chown", "dac_override", "fowner", "fsetid", "kill", "mknod", "net_bind_service", "setfcap", "setgid", "setpcap", "setuid", "sys_chroot",
                  "NET_ADMIN","NET_BROADCAST","NET_RAW"] # added to default for the keepalived container

    # extra labels for log scraping
    extra_labels = ["job_name", "task_group_name", "task_name", "namespace", "node_name"]

    volumes {
      # required for bind mounting host directories
      enabled = true
    }
  }
}

telemetry {
  prometheus_metrics = true
  collection_interval = "1s"

  disable_hostname = true

  publish_allocation_metrics = true
  publish_node_metrics = true
}

