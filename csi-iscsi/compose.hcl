job "csi-iscsi" {
  datacenters = ["home", "dmz"]
  type        = "system" # runs on every client node

  group "node" {
    task "plugin" {
      driver = "docker"

      config {
        image        = "democraticcsi/democratic-csi:v1.9.5" # pin version
        network_mode = "host"
        ipc_mode     = "host"
        privileged   = true

        args = [
          "--csi-version=1.5.0",
          "--csi-name=org.democratic-csi.synology-iscsi",
          "--driver-config-file=${NOMAD_SECRETS_DIR}/driver-config-file.yaml",
          "--log-level=warn",
          "--csi-mode=node",
          "--server-socket=/csi-data/csi.sock",
        ]

        mount {
          type     = "bind"
          target   = "/host"
          source   = "/"
          readonly = false
        }

        mount {
          type     = "bind"
          target   = "/run/udev"
          source   = "/run/udev"
          readonly = true
        }
      }

      env {
        TZ = "Europe/Berlin"
      }

      csi_plugin {
        id        = "iscsi"
        type      = "node"
        mount_dir = "/csi-data"
      }

      template {
        destination = "${NOMAD_SECRETS_DIR}/driver-config-file.yaml"
        # avoid `env = true`; this file must stay YAML, not env-var format

        data = <<EOH
{{- with nomadVar "nomad/jobs/csi-iscsi" }}
driver: synology-iscsi
iscsi:
  targetPortal: "{{- .dsm_host }}"
  baseiqn: "iqn.2000-01.com.synology:csi."
  lunTemplate:
    type: "BLUN"
  lunSnapshotTemplate:
    is_locked: true
    is_app_consistent: true
{{- end }}
EOH
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
  }

  group "controller" {
    constraint {
      attribute = "${node.datacenter}"
      value     = "home"
    }

    task "plugin" {
      driver = "docker"

      config {
        image = "democraticcsi/democratic-csi:v1.9.5" # pin version

        args = [
          "--csi-version=1.5.0",
          "--csi-name=org.democratic-csi.synology-iscsi",
          "--driver-config-file=${NOMAD_SECRETS_DIR}/driver-config-file.yaml",
          "--log-level=warn",
          "--csi-mode=controller",
          "--server-socket=/csi-data/csi.sock",
          "--server-address=0.0.0.0",
          "--server-port=9000",        ]
      }

      env {
        TZ = "Europe/Berlin"
      }

      csi_plugin {
        id        = "iscsi"
        type      = "controller"
        mount_dir = "/csi-data"
      }

      template {
        destination = "${NOMAD_SECRETS_DIR}/driver-config-file.yaml"

        data = <<EOH
{{- with nomadVar "nomad/jobs/csi-iscsi" }}
driver: synology-iscsi
httpConnection:
  protocol: https
  host: "{{- .dsm_host }}"
  port: 5001
  username: "{{- .dsm_user }}"
  password: "{{- .dsm_pass }}"
  allowInsecure: true
  session: "democratic-csi"
  serialize: true
synology:
  volume: /volume2
iscsi:
  targetPortal: "{{- .dsm_host }}"
  baseiqn: "iqn.2000-01.com.synology:csi."
  lunTemplate:
    type: "BLUN" # btrfs thin provisioning
    dev_attribs:
        - dev_attrib: emulate_tpu # space reclamation
          enable: 1
        - dev_attrib: can_snapshot # snapshots
          enable: 1
  lunSnapshotTemplate:
    is_locked: true
    is_app_consistent: true
  targetTemplate:
    auth_type: 0
    max_sessions: 1 # number of parallel initiators, leave at 1 unless you have a cluster-aware system
{{- end }}
EOH
      }

      resources {
        cpu    = 50
        memory = 128
      }
    }
}  
}