job "consul-ingress" {
  datacenters = ["home"]
  type        = "system"

  group "ingress-tcp" {

    network {
      mode = "bridge"

      # NOTE: Remember to add a port allocation to the network block when registering additional listeners!
      port  "smtp" { static = 25 }
      port  "home-http" { static = 80 }
      port  "home-https" { static = 443 }
      port  "cloudflare-dyndns" { static = 1080 }
      port  "loki" { static = 3100 }
      
      port  "unifi-speedtest" { static = 6789 }
      port  "unifi-inform" { static = 8080 }

      port  "envoy_metrics" { to = 9102 }
    }

    service {
      name = "ingress-gateway"

      tags = [ "diun.enable=false" ] # don't check with diun, the proxy container is packaged with Consul

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

            # NOTE: Remember to add a port allocation to the network block when registering additional listeners!

            # Protonmail bridge
            listener {
              port     = 25
              protocol = "tcp"

              service {
                name = "protonmail-smtp"
              }
            }
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
            # incoming IP update requests from the Fritz!Box router
            listener { 
              port     = 1080
              protocol = "tcp"

              service {
                name = "cloudflare-dnsupdate"
              }
            }
            # Loki ingress, simplifies logging from the DMZ
            listener {
              port     = 3100
              protocol = "tcp"

              service {
                name = "loki"
              }
            }
            # Unifi Network speedtest ingress
            listener {
              port     = 6789
              protocol = "tcp"

              service {
                name = "unifi-network-speedtest"
              }
            }
            # Unifi Network inform ingress, required for adopting Unifi devices on the network.
            #  Default is http://unifi:8080, make sure that DNS is configured to the ingress IP accordingly.
            listener {
              port     = 8080
              protocol = "tcp"

              service {
                name = "unifi-network-inform"
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