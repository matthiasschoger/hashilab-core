variable "base_domain" {
  default = "missing.environment.variable"
}

job "traefik" {
  datacenters = ["home", "dmz"]
  type        = "service"

  # Traefik instance for the home (internal) network
  group "traefik-home" {

    constraint {
      attribute = "${node.datacenter}"
      value     = "home"
    }

    network {
      mode = "bridge"

      port "metrics" { to = 8080 } # Prometheus metrics via API port

      port "envoy_metrics_api" { to = 9102 }
      port "envoy_metrics_home_http" { to = 9103 }
      port "envoy_metrics_home_https" { to = 9104 }
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
        "traefik.http.routers.traefik.rule=Host(`lab.${var.base_domain}`) || Host(`traefik.lab.${var.base_domain}`)",
        "traefik.http.routers.traefik.service=api@internal",
        "traefik.http.routers.traefik.entrypoints=websecure"
      ]
    }

    service {
      name = "traefik-home-http"

      port = 80

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_home_http}" # make envoy metrics port available in Consul
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
      name = "traefik-home-https"

      port = 443

      meta {
        envoy_metrics_port = "${NOMAD_HOST_PORT_envoy_metrics_home_https}" # make envoy metrics port available in Consul
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

    # NOTE: If you are interested in routing incomming traffic from your router via port forwarding, please have a look at earlier versions.
    #  In the meanwhile I have changed the setup to Cloudflare tunnels, but you can find the original setup in the jobs traefik and consul-ingress
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

      port "metrics" { to = 1080 } # Traefik metrics via API port
      port "crowdsec_metrics" { to = 6060 } # Crowdsec metrics 

      port "envoy_metrics_api" { to = 9102 }
      port "envoy_metrics_dmz_http" { to = 9103 }
    }

    ephemeral_disk {
      # Used to cache Crowdsec transient data, Nomad will try to preserve the disk between job updates.
      size    = 300 # MB
      migrate = true
    }

    service {
      name = "traefik-dmz-api"

      port = 1080

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
        crowdsec_metrics_port = "${NOMAD_HOST_PORT_crowdsec_metrics}"
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
        "traefik.http.routers.traefik-dmz.rule=Host(`dmz.lab.${var.base_domain}`)",
        "traefik.http.routers.traefik-dmz.entrypoints=websecure"
      ]
    }

    # Cloudflare entrypoint, is bound to localhost:80 in the cloudflared job via Consul Connect
    service {
      name = "traefik-dmz-http"

      port = 80

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
        destination = "${NOMAD_SECRETS_DIR}/certs/origin/${var.base_domain}.crt"
        perms = "600"
        data = <<EOH
{{- with nomadVar "nomad/jobs/traefik" }}{{- .origin_certificate }}{{- end }}
EOH
      }
      template {
        destination = "${NOMAD_SECRETS_DIR}/certs/origin/${var.base_domain}.key"
        perms = "600"
        data = <<EOH
{{- with nomadVar "nomad/jobs/traefik" }}{{- .origin_private_key }}{{- end }}
EOH
      }

      template {
        destination = "local/traefik.yaml"
        data = <<EOH
providers:
  file:
    directory: "/local/conf"
    watch: false
  consulcatalog:
    prefix: "dmz"
    connectaware: true
    exposedByDefault: false
    servicename: "traefik-dmz-api" # connects Traefik to the Consul service
    endpoint:
      address: "http://consul.service.consul:8500"

experimental:
  plugins:
    bouncer:
      moduleName: github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin
      version: v1.3.5
    cloudflare:
      moduleName: github.com/agence-gaya/traefik-plugin-cloudflare
      version: v1.2.0

entryPoints:
  cloudflare:
    address: :80
    http:
      middlewares:
        - cloudflare@file  # rewrite requesting IP from CF
        - crowdsec@file    # crowdsec bouncer
  traefik:
    address: :1080

tls:
  certificates:
    - certFile: ${NOMAD_SECRETS_DIR}/certs/origin/${var.base_domain}.crt
      keyFile: ${NOMAD_SECRETS_DIR}/certs/origin/${var.base_domain}.key

api:
  dashboard: true
  insecure: true

ping:
  entryPoint: "traefik"

log:
  level: INFO
#  level: DEBUG

accessLog:
  filePath: {{ env "NOMAD_ALLOC_DIR" }}/traefik/access.log # Traefik access log location
  format: json
  filters:
    statusCodes:
      - "200-299"  # log successful http requests
      - "400-599"  # log failed http requests
  bufferingSize: 0 # collect logs as in-memory buffer before writing into log file
  fields:
    headers:
      defaultMode: keep

metrics:
  prometheus:
    addEntryPointsLabels: true
    addRoutersLabels: true
    addServicesLabels: true

global:
  sendanonymoususage: true # Periodically send anonymous usage statistics.
EOH
      }

      template {
        destination = "local/conf/crowdsec.yaml"
        data = <<EOH
http:
  middlewares:
    cloudflare: # rewrites true request IP from CF header
      plugin:
        cloudflare:
          trustedCIDRs: [0.0.0.0/0] # allow all IPs
          overwriteRequestHeader: true
    crowdsec: # crowdsec
      plugin:
        bouncer:
          enabled: true
          defaultDecisionSeconds: 60
          crowdsecMode: live
          crowdsecAppsecEnabled: false
          crowdsecAppsecHost: localhost:7422
          crowdsecAppsecFailureBlock: true
          crowdsecAppsecUnreachableBlock: true
          crowdsecLapiKey: "{{- with nomadVar "nomad/jobs/traefik" }}{{- .crowdsec_bouncer_token }}{{- end }}"
          crowdsecLapiHost: localhost:8080
          crowdsecLapiScheme: http
          crowdsecLapiTLSInsecureVerify: false
          forwardedHeadersTrustedIPs:
            # private class ranges
            - 192.168.0.0/16
          clientTrustedIPs:
            # private class ranges
            - 192.168.0.0/16
EOH
      }

      resources {
        memory = 128
        cpu    = 400
      }
    }
  

    # see https://blog.lrvt.de/configuring-crowdsec-with-traefik/
    task "crowdsec" {

      driver = "docker"

      config {
        image = "crowdsecurity/crowdsec:latest"

        mounts = [ # map config files into container
          {
            type   = "bind"
            source = "local/crowdsec/config.yaml.local"
            target = "/etc/crowdsec/config.yaml.local"
          },
          {
            type   = "bind"
            source = "local/crowdsec/acquis.yaml"
            target = "/etc/crowdsec/acquis.yaml"
          }

        ]
      }

      env {
        TZ = "Europe/Berlin"

        COLLECTIONS = "crowdsecurity/traefik crowdsecurity/http-cve crowdsecurity/appsec-generic-rules crowdsecurity/appsec-virtual-patching crowdsecurity/sshd crowdsecurity/linux crowdsecurity/base-http-scenarios"
      }

      template {
        destination = "/local/crowdsec/config.yaml.local"
        data = <<EOH
common:
#  log_level: debug
  log_level: info

# config_paths:
#   data_dir: "{{ env "NOMAD_ALLOC_DIR" }}/data/crowdsec"

prometheus:
  enabled: true
  level: full
  listen_addr: 0.0.0.0

EOH
      }


      template {
        destination = "/local/crowdsec/acquis.yaml"
        data = <<EOH
poll_without_inotify: false
filenames:
  - {{ env "NOMAD_ALLOC_DIR" }}/traefik/*.log # Traefik access log location
labels:
  type: traefik

EOH
      }

      resources {
        memory = 128
        cpu    = 100
      }

      volume_mount {
        volume      = "crowdsec"
        destination = "/var/lib/crowdsec/data"
      }    
    }
  
    volume "crowdsec" {
      type            = "csi"
      source          = "crowdsec"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  }
}