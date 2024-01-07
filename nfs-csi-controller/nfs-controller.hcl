job "csi-nfs-controller" {
  datacenters = ["home"]
  type = "system"

  constraint {
    attribute = "${node.class}"
    value     = "compute"
  }

  group "nfs" {

    task "controller" {
      driver = "docker"

      config {
        image = "registry.k8s.io/sig-storage/nfsplugin:v4.3.0"
        args = [
          "--v=5",
          "--nodeid=${attr.unique.hostname}",
          "--endpoint=unix:///csi/csi.sock",
          "--drivername=nfs.csi.k8s.io"
        ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      csi_plugin {
        id        = "nfs"
        type      = "controller"
        mount_dir = "/csi"
      }

      resources {
        memory = 64
        cpu    = 100
      }
    }
  }
}

