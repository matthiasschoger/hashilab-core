job "traefik" {
  datacenters = ["home"]
  type        = "service"

  group "traefik" {
    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    network {
      mode = "bridge"

      port "metrics" { to = 8080 } # Prometheus metrics via API port

      port "envoy_metrics_api" { to = 9102 }
      port "envoy_metrics_home_https" { to = 9103 }
      port "envoy_metrics_cloudflare" { to = 9104 }
      port "envoy_metrics_home_http" { to = 9105 }
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

      port = 8080

      check {
        type     = "http"
        path     = "/ping"
        interval = "5s"
        timeout  = "2s"
        expose   = true # required for Connect
      }

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_api}" # make envoy metrics port available in Consul
        metrics_port = "${NOMAD_HOST_PORT_metrics}"
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
      name = "traefik-home-http"

      port = 80
      tags = ["home"]

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
      name = "traefik-home-https"

      port = 443
      tags = ["home"]

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

    # entrypoint for Cloudflare tunnel from cloudflared
    service {
      name = "traefik-cloudflare"

      port = 1080
      tags = ["internet"]

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_cloudflare}" # make envoy metrics port available in Consul
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

    # NOTE: If you are intrested in routing incomming traffic from your router, please have a look at earlier versions.
    #  I have changed the setup to Cloudflare tunnels, but you can find the original setup in the projects traefik and consul-ingress

    task "server" {

      driver = "docker"

      config {
        image = "traefik:latest"

        args = [ "--configFile=/local/traefik.yaml" ]
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