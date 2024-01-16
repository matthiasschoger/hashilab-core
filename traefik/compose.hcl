job "traefik" {
  datacenters = ["home"]
  type        = "service"

  group "traefik" {
    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    restart {
      attempts = 3
      delay = "1m"
      mode = "fail"
    }

    network {
      mode = "bridge"

      port "api" { static = 18080 }

      port "envoy_metrics_api" { to = 9102 }
      port "envoy_metrics_home_https" { to = 9103 }
      port "envoy_metrics_inet_https" { to = 9104 }
      port "envoy_metrics_home_http" { to = 9105 }
      port "envoy_metrics_inet_http" { to = 9106 }
    }

    ephemeral_disk {
      # Used to store the JSON cert stores, Nomad will try to preserve the disk between job updates.
      # Preserving the JSON store prevents Let's Encrypt from banning you for a certain time if you request too many certs 
      #  in a short timeframe due to Traefik re-deployments
      size    = 300 # MB
      migrate = true
    }

    service {
      name = "traefik-api"

      port = 18080

      check {
        type     = "http"
        path     = "/ping"
        interval = "5s"
        timeout  = "2s"
        expose   = true # required for Connect
      }

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_api}" # make envoy metrics port available in Consul
      }
      connect {
        sidecar_service { 
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }
            upstreams {
              destination_name = "smallstep"
              local_bind_port  = 9443
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }

      tags = [
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.traefik.rule=Host(`lab.home`) || Host(`traefik.lab.home`)",
        "traefik.http.routers.traefik.service=api@internal",
        "traefik.http.routers.traefik.entrypoints=websecure"
      ]
    }

    service {
      name = "traefik-home-https"
      task ="server"

      port = 443
      tags = ["internal"]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_home_https}" # make envoy metrics port available in Consul
      }
      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9103"
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }
    }

    service {
      name = "traefik-inet-https"
      task = "server"

      port = 1443
      tags = ["internet"]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_inet_https}" # make envoy metrics port available in Consul
      }
      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9104"
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }
    }

    service {
      name = "traefik-home-http"
      task = "server"

      port = 80
      tags = ["internal"]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_home_http}" # make envoy metrics port available in Consul
      }
      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9105"
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }
    }

    service {
      name = "traefik-inet-http"
      task = "server"

      port = 1080
      tags = ["internet"]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_inet_http}" # make envoy metrics port available in Consul
      }
      connect {
        sidecar_service {
          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9106"
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }
    }

    # main task, Traefik
    task "server" {

      driver = "docker"

      config {
        image = "traefik:latest"

        args = [ "--configFile=/local/traefik.yaml" ]
      }

      template {
        destination = "secrets/variables.env"
        env             = true
        data            = <<EOH
{{- with nomadVar "nomad/jobs/traefik" }}
{{- .lego_ddns_auth_key }} = "{{- .lego_ddns_auth_value }}"
LEGO_PROVIDER = "{{- .lego_provider }}"
CA_EMAIL = "{{- .ca_email }}"
{{- end }}
EOH
      }

      env {
        LEGO_CA_SYSTEM_CERT_POOL = true
        LEGO_CA_CERTIFICATES = "${NOMAD_SECRETS_DIR}/intermediate_ca.crt"
        TZ = "Europe/Berlin"
      }

      template {
        destination = "local/traefik.yaml"
        data        = file("traefik.yaml")
      }

      template {
        destination = "${NOMAD_SECRETS_DIR}/intermediate_ca.crt"
        perms = "600"
        data = <<EOH
{{- with nomadVar "nomad/jobs/traefik" }}{{- .ca_certificate }}{{- end }}
EOH
      }

      dynamic "template" {
        for_each = fileset(".", "conf/*")

        content {
          data            = file(template.value)
          destination     = "local/${template.value}"
        }
      }

      resources {
        memory = 128
        cpu    = 100
      }
    }
  }
}