job "keepalived" {
  datacenters = ["home"]
  type = "system"

  group "keepalived" {

    task "keepalived" {
      driver = "docker"

      config {
        network_mode = "host"

        image = "shawly/keepalived:2.3.1"

        volumes = [
            "local/keepalived.conf:/etc/keepalived/keepalived.conf"
        ]

        cap_add = ["NET_ADMIN", "NET_BROADCAST", "NET_RAW"]
      }

      env {
        KEEPALIVED_CUSTOM_CONFIG = true # use config at /etc/keepalived/keepalived.conf instead of env

        TZ = "Europe/Berlin"
      }

      template {
        destination = "local/keepalived.conf"
        change_mode = "restart"   # restart container when the key flips to another node
        data        = <<EOH
{{- $myNode := env "node.unique.id" -}}
{{- $traefikNode := keyOrDefault "traefik-host-id" "" -}}
vrrp_instance VI_HOMELAB {
    interface {{ sockaddr "GetPrivateInterfaces | include \"network\" \"192.168.0.0/24\" | attr \"name\"" }}

    virtual_router_id 51
    priority {{ if eq $myNode $traefikNode }}150{{ else }}100{{ end }}
    advert_int 1

    virtual_ipaddress {
        192.168.0.3/24
    }
}
EOH
      }

      resources {
        memory = 32
        cpu    = 50
      }
    }
  }
}

