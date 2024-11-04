job "csi-nfs" {
  datacenters = ["home", "dmz"]
  type = "system" # ensures that all nodes in the DCs have a copy.

  group "plugin" {

    task "plugin" {
      driver = "docker"

      config {
        image = "registry.k8s.io/sig-storage/nfsplugin:v4.8.0"
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
        memory = 64
        cpu = 100
      }
    }
  }

  group "controller" {

    constraint {
      attribute = "${node.datacenter}"
      value     = "home"
    }

    task "controller" {
      driver = "docker"

      config {
        image = "registry.k8s.io/sig-storage/nfsplugin:v4.8.0"
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

