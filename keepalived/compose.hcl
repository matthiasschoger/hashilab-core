job "keepalived" {
  datacenters = ["home"]
  type = "system"

  constraint {
    attribute = "${node.class}"
    value     = "compute"
  }

  group "keepalived" {

    task "keepalived" {
      driver = "docker"

      config {
        image = "osixia/keepalived:2.0.20"
        network_mode = "host"

        volumes = [
            "local/keepalived/:/container/environment/01-custom"
        ]

        cap_add = ["NET_ADMIN", "NET_BROADCAST", "NET_RAW"]
      }

      # FIXME: filter for only nodes with class = "compute"
      # {{- if eq .NodeClass "compute" }} # does not work
      # https://developer.hashicorp.com/nomad/api-docs/nodes
      template {
        destination = "local/keepalived/env.yaml"
        data        = <<EOH
KEEPALIVED_INTERFACE: {{ sockaddr "GetPrivateInterfaces | include \"network\" \"192.168.0.0/24\" | attr \"name\"" }}
KEEPALIVED_UNICAST_PEERS:
{{- with $node := node -}}
{{ range nodes }}
{{- if ne .Address $node.Node.Address }}
  - {{ .Address }}
{{- end -}}
{{- end -}}
{{- end }}

KEEPALIVED_VIRTUAL_IPS:
  - 192.168.0.3/24
EOH
      }

      env {
        TZ = "Europe/Berlin"
      }

      resources {
        memory = 32
        cpu    = 50
      }
    }
  }
}

