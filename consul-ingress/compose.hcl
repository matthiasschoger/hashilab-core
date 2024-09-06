job "consul-ingress" {
  datacenters = ["home"]
  type        = "system"

  group "ingress" {
    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    network {
      mode = "bridge"

      port  "smtp" { static = 25 }
      port  "home-http" { static = 80 }
      port  "home-https" { static = 443 }
      port  "cloudflare-dyndns" { static = 1080 }
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

            # NOTE: Remember to add a port allocation to the network block when registering an additional listener!
            # Treafik ports
            listener {
              port     = 25
              protocol = "tcp"

              service {
                name = "protonmail-smtp"
              }
            }
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
            # incoming IP update requests from the Fritz!Box router
            listener { 
              port     = 1080
              protocol = "tcp"

              service {
                name = "cloudflare-dyndns"
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
/*
          name = "connect-gateway-consul-ingress"
          #      "connect-gateway-<service>" when used as a gateway

          driver = "docker"

          config {
            image = "${meta.connect.gateway_image}"
            #       "${meta.connect.gateway_image}" when used as a gateway

            args = [
              "-c",
              "${NOMAD_SECRETS_DIR}/envoy_bootstrap.json",
              "-l",
              "debug",
              "--concurrency",
              "${meta.connect.proxy_concurrency}",
              "--disable-hot-restart"
            ]
          }          
*/          
          resources {
            cpu    = 100
            memory = 64
          }
        }
      }
    }
  }
}