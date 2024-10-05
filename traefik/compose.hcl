job "traefik" {
  datacenters = ["home", "dmz"]
  type        = "service"

  # Traefik instance for the home (internal) network
  group "traefik-home" {
    constraint {
      attribute = "${node.datacenter}"
      value     = "home"
    }
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
      name = "traefik-home-api"

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
#        "traefik.http.routers.traefik.rule=Host(`lab.home`) || Host(`traefik.lab.home`)",
        "traefik.http.routers.traefik.rule=Host(`lab.schoger.net`) || Host(`traefik.lab.schoger.net`)",
        "traefik.http.routers.traefik.tls.certresolver=le",
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

    # wait for step CA to be healthy before starting Traefik. Otherwise, cert creation might fail and Trarfik is too stupid to retry.
    task "wait-for-smallstep" {

      driver = "docker"

      config {
        image        = "busybox:1.28"
        command      = "sh"
        args         = ["-c", "echo -n 'Waiting for service'; until nslookup smallstep.service.consul 2>&1 >/dev/null; do echo '.'; sleep 2; done"]
      }

      lifecycle {
        hook = "prestart"
        sidecar = false
      }
    }

    # NOTE: If you are interested in routing incomming traffic from your router via port forwarding, please have a look at earlier versions.
    #  I have changed the setup to Cloudflare tunnels, but you can find the original setup in the jobs traefik and consul-ingress
    task "server" {

      driver = "docker"

      config {
        image = "traefik:latest"

        args = [ "--configFile=/local/traefik.yaml" ]
      }

      env {
        TZ = "Europe/Berlin"

        LEGO_CA_SYSTEM_CERT_POOL = true
        LEGO_CA_CERTIFICATES = "${NOMAD_SECRETS_DIR}/intermediate_ca.crt"
      }

      template {
        destination = "secrets/variables.env"
        env         = true
        perms       = 400
        data        = <<EOH
{{- with nomadVar "nomad/jobs/traefik" }}
CF_DNS_API_TOKEN = "{{- .cf_dns_api_token }}"
{{- end }}
EOH
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
        memory = 256
        cpu    = 400
      }
    }
  }


  # Traefik instance for the DMZ, routes traffic from cloudflared to the desired services
  group "traefik-dmz" {

    constraint {
      attribute = "${node.datacenter}"
      value     = "dmz"
    }

    network {
      mode = "bridge"

      port "metrics" { to = 8080 } # Prometheus metrics via API port

      port "envoy_metrics_api" { to = 9102 }
      port "envoy_metrics_dmz_http" { to = 9103 }
    }

    service {
      name = "traefik-dmz-api"

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
          }
        }

        sidecar_task {
          resources {
            cpu    = 50
            memory = 48
          }
        }
      }

      tags = [ # registers the DMZ Traefik instance with the home instance
        "traefik.enable=true",
        "traefik.consulcatalog.connect=true",
        "traefik.http.routers.traefik-dmz.rule=Host(`dmz.lab.home`)",
        "traefik.http.routers.traefik-dmz.entrypoints=websecure"
      ]
    }

    # Cloudflare entrypoint, is bound to localhost:80 in the cloudflared job via Consul Connect
    service {
      name = "traefik-dmz-http"

      port = 80

      tags = ["dmz"]
      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_dmz_http}" # make envoy metrics port available in Consul
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

    task "server" {

      driver = "docker"

      config {
        image = "traefik:latest"

        args = [ "--configFile=/local/traefik.yaml" ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      template {
        destination = "${NOMAD_SECRETS_DIR}/certs/origin/schoger.net.crt"
        perms = "600"
        data = <<EOH
{{- with nomadVar "nomad/jobs/traefik" }}{{- .origin_certificate }}{{- end }}
EOH
      }
      template {
        destination = "${NOMAD_SECRETS_DIR}/certs/origin/schoger.net.key"
        perms = "600"
        data = <<EOH
{{- with nomadVar "nomad/jobs/traefik" }}{{- .origin_private_key }}{{- end }}
EOH
      }

      template {
        destination = "local/traefik.yaml"
        data = <<EOH
providers:
  consulcatalog:
    prefix: "dmz"
    connectaware: true
    exposedByDefault: false
    servicename: "traefik-dmz-api" # connects Traefik to the Consul service
    endpoint:
      address: "http://consul.service.consul:8500"

entryPoints:
  cloudflare:
    address: :80
  traefik:
    address: :8080

tls:
  certificates:
    - certFile: ${NOMAD_SECRETS_DIR}/certs/origin/schoger.net.crt
      keyFile: ${NOMAD_SECRETS_DIR}/certs/origin/schoger.net.key

api:
  dashboard: true
  insecure: true

ping:
  entryPoint: "traefik"

log:
  level: INFO
#  level: DEBUG

metrics:
  prometheus:
    addEntryPointsLabels: true
    addRoutersLabels: true
    addServicesLabels: true

global:
  sendanonymoususage: true # Periodically send anonymous usage statistics.
EOH
      }

      resources {
        memory = 128
        cpu    = 400
      }
    }
  }
}