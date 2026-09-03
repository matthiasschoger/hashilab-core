job "csi-iscsi" {
  datacenters = ["home", "dmz"]
  type        = "system" # runs on every client node

  group "node" {
    task "plugin" {
      driver = "docker"

      config {
        image        = "democraticcsi/democratic-csi:v1.9.5" # pin a version
        network_mode = "host"
        ipc_mode     = "host"
        privileged   = true

        args = [
          "--csi-version=1.5.0",
          "--csi-name=org.democratic-csi.synology-iscsi",
          "--driver-config-file=${NOMAD_SECRETS_DIR}/driver-config-file.yaml",
          "--log-level=info",
          "--csi-mode=node",
          "--server-socket=/csi-data/csi.sock",
        ]

        # gives the plugin's iscsiadm/iscsid access to the host's
        # kernel modules, iscsi initiator state, and device nodes
        mount {
          type     = "bind"
          target   = "/host"
          source   = "/"
          readonly = false
        }
        mount {
          type   = "bind"
          target = "/lib/modules"
          source = "/lib/modules"
        }
        mount {
          type   = "bind"
          target = "/etc/iscsi"
          source = "/etc/iscsi"
        }
      }

      csi_plugin {
        id        = "csi-iscsi"
        type      = "node"
        mount_dir = "/csi-data"
      }

      template {
        destination = "${NOMAD_SECRETS_DIR}/driver-config-file.yaml"
        # avoid `env = true`; this file must stay YAML, not env-var format

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
        image = "democraticcsi/democratic-csi:v1.9.5"

        args = [
          "--csi-version=1.5.0",
          "--csi-name=org.democratic-csi.synology-iscsi",
          "--driver-config-file=${NOMAD_SECRETS_DIR}/driver-config-file.yaml",
          "--log-level=info",
          "--csi-mode=controller",
          "--server-socket=/csi-data/csi.sock",
        ]
      }

      csi_plugin {
        id        = "csi-iscsi"
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
{{- end }}
EOH
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }
}  
}