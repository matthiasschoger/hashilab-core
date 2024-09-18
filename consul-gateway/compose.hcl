job "consul-gateway-home" {
  datacenters = ["home"]
  type        = "service"

  group "gateway" {

    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }

    network {
      mode = "bridge"

      port "mesh" { static = "8443" }
    }

    service {
      name = "mesh-gateway"

      tags = [ "diun.enable=false" ] # don't check with diun

      # The mesh gateway connect service should be configured to use a port from
      # the host_network capable of cross-datacenter connections.
      port = "mesh"

      connect {
        gateway {
          mesh {
            # No configuration options in the mesh block.
          }

          proxy { }
        }

        sidecar_task {
          resources {
            cpu    = 100
            memory = 64
          }
        }
      }
    }
  }
}