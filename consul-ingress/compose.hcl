job "consul-ingress" {
  datacenters = ["home"]
  type        = "system"

  group "ingress-tcp" {

    network {
      mode = "bridge"

      # NOTE: Remember to add a port allocation to the network block when registering an additional listener!
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

      tags = [ "diun.enable=false" ] # don't check with diun

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
            # Unifi Network inform ingress, required for adopting Unifi devices on the network
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
            memory = 128
          }
        }
      }
    }
  }

  # Ingress proxy for UDP traffic
  group "ingress-udp" {

    network {
      mode = "host"

      # Unifi Network
      port "stun"         { static = 3478 }  # UDP
      port "discovery"    { static = 10001 } # UDP
      port "discovery-l2" { static = 1900 }  # UDP
    }

    task "nginx" {

      driver = "docker"

      config {
        image = "nginxinc/nginx-unprivileged:alpine"

        volumes = [ "local/conf.d/stream.conf:/etc/nginx/stream.conf" ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      template {
        destination = "local/conf.d/stream.conf"
        change_mode   = "signal"
        change_signal = "SIGHUP"

        data = <<EOH
stream {

{{- $unifi_network_stun := service "unifi-network-stun" }}
{{- if $unifi_network_stun }}
    upstream unifi-network-stun {
  {{- range $unifi_network_stun }}
        server {{ print .Address ":" .Port }};
  {{- end }} 
    }

    server {
        listen 3478 udp;
        proxy_pass unifi-network-stun;

        proxy_responses 1;
    }
{{- end }} 

{{ $unifi_network_discovery := service "unifi-network-discovery" }}
{{- if $unifi_network_discovery }}
    upstream unifi-network-discovery {
  {{- range $unifi_network_discovery }}
        server {{ print .Address ":" .Port }};
  {{- end }} 
    }

    server {
        listen 10001 udp;
        proxy_pass unifi-network-discovery;

        proxy_responses 1;
    }
{{- end }} 

{{ $unifi_network_discovery_l2 := service "unifi-network-discovery-l2" }}
{{- if $unifi_network_discovery_l2 }}
    upstream unifi-network-discovery-l2 {
  {{- range $unifi_network_discovery_l2 }}
        server {{ print .Address ":" .Port }};
  {{- end }} 
    }

    server {
        listen 1900 udp;
        proxy_pass unifi-network-discovery-l2;

        proxy_responses 1;
    }
{{- end }} 
}
EOH
      }

      resources {
        memory = 32
        cpu    = 20
      }
    }
  }
}