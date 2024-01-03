job "SERVICE_NAME" {
  datacenters = ["home"]
  type        = "service"

  group "SERVICE_NAME" {

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    restart {
      attempts = 5
      delay = "1m"
      mode = "fail"
    }

    network {
      port "http" { to = 3000 }
    }

    service {
      name = "${NOMAD_JOB_NAME}"

      port = "http"

      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
      }

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.${NOMAD_JOB_NAME}.rule=Host(`${NOMAD_JOB_NAME}.lab.home`)",
        "traefik.http.routers.${NOMAD_JOB_NAME}.entrypoints=websecure",
        "traefik.http.routers.${NOMAD_JOB_NAME}.tls=true",
        "traefik.http.routers.${NOMAD_JOB_NAME}.tls.certResolver=home"
      ]
    }

    task "server" {
      driver = "docker"

      config {
        image = "SERVICE_NAME:latest"

        ports = ["http"]
      }

      env { }

      resources {
        memory = 500
        cpu    = 200
      }

      volume_mount {
        volume      = "SERVICE_NAME"
        destination = "/data"
      }
    }

    volume "SERVICE_NAME" {
      type            = "csi"
      source          = "SERVICE_NAME"
      access_mode     = "single-node-writer"
      attachment_mode = "file-system"
    }
  }
}