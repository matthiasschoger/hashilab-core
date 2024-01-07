job "csi-nfs-plugin" {
  datacenters = ["home"]
  type = "system" # ensures that all nodes in the DC have a copy.

  group "nfs" {

    restart {
      interval = "30m"
      attempts = 10
      delay    = "15s"
      mode     = "fail"
    }

    task "plugin" {
      driver = "docker"

      config {
        image = "registry.k8s.io/sig-storage/nfsplugin:v4.3.0"
        args = [
          "--v=5",
          "--nodeid=${attr.unique.hostname}",
          "--endpoint=unix:///csi/csi.sock",
          "--drivername=nfs.csi.k8s.io"
        ]
        # node plugins must run as privileged jobs because they
        # mount disks to the host
        privileged = true
      }

      env {
        TZ = "Europe/Berlin"
      }

      csi_plugin {
        id        = "nfs"
        type      = "node"
        mount_dir = "/csi"
      }

      resources {
        memory = 100
        cpu = 200
      }
    }
  }
}

