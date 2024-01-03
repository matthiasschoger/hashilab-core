job "consul-ingress" {
  datacenters = ["home"]
  type        = "system"

  group "ingress" {
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

      port  "home-http" { static = 80 }
      port  "home-https" { static = 443 }
      port  "inet-http" { static = 1080 }
      port  "inet-https" { static = 1443 }
      port  "loki" { static = 3100 }

      port  "envoy_metrics" { to = 9102 }
    }

    service {
      name = "ingress-gateway"

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics}" # make envoy metrics port available in Consul
      }
      connect {
        gateway {
          # Consul Ingress Gateway Configuration Entry.
          ingress {
            # Nomad will automatically manage the Configuration Entry in Consul
            # given the parameters in the ingress block.
            #
            # Additional options are documented at
            # https://www.nomadproject.io/docs/job-specification/gateway#ingress-parameters

            # Treafik ports
            listener {
              port     = 80
              protocol = "tcp"

              service {
                name = "traefik-home-http"
              }
            }
            listener {
              port     = 443
              protocol = "tcp"

              service {
                name = "traefik-home-https"
              }
            }          
            listener {
              port     = 1080
              protocol = "tcp"

              service {
                name = "traefik-inet-http"
              }
            }
            listener {
              port     = 1443
              protocol = "tcp"

              service {
                name = "traefik-inet-https"
              }
            }
            listener {
              port     = 3100
              protocol = "tcp"

              service {
                name = "loki"
              }
            }
          }

          proxy {
            config {
              envoy_prometheus_bind_addr = "0.0.0.0:9102"
            }
          }
        }

        sidecar_task {
          resources {
            cpu    = 100
            memory = 128
          }
        }
      }
    }
  }
}