job "coredns" {
  datacenters = ["home"]
  type        = "system"

  group "coredns" {

    # distribute across the two compute nodes
#    count = 2
    constraint {
      attribute = "${node.class}"
      value     = "compute"
    }
#    constraint {
#      distinct_hosts = true
#    }

    network {
      port "dns" { static = "53"  }
      port "metrics" { static = "9153" }
      port "health" { }
    }

/* unfortunately, update max_parallel is not supported for "system" jobs
    update { # make sure that the second node gets updated only after the first deployment was successful
      max_parallel  = 1 
      auto_revert   = true
      health_check  = "checks"
      stagger       = "5s"
    }
*/

    service {
      name = "coredns"

      port = "dns"

      check {
        type     = "http"
        path     = "/health"
        port     = "health"
        interval = "5s"
        timeout  = "5s"
      }
    }

   task "server" {
      driver = "docker"

      config {
        # fixed version tag to allow for container caching
        # "latest" will always pull a new container from DockerHub, which would fail if no DNS is available
        image = "coredns/coredns:1.11.3" 

        args = ["-conf", "/local/coredns/corefile"]

        network_mode = "host"
        ports = ["dns", "metrics", "health"]
      }

      env {
        TZ = "Europe/Berlin"
      }

      resources {
        memory = 128
        cpu    = 100
      }

      #templates (corefile + lab.home zone file)
      template {
        destination = "local/coredns/corefile"
        change_mode   = "signal"
        change_signal = "SIGUSR1"
        data = <<EOH
### resolve immich.schoger.net to the local Traefik
#immich.schoger.net.:53 {
#  bind {{ env "NOMAD_IP_dns" }}

  # global health check
#  health :{{ env "NOMAD_PORT_health" }}

#  hosts {
#    192.168.0.3  immich.schoger.net
# }
#  header { 
#    response set ra # set RecursionAvailable flag
#  }

#  errors
#  prometheus {{ env "NOMAD_ADDR_metrics" }}
#}

### fritz.box to resolve the network printer
fritz.box.:53 {
  bind {{ env "NOMAD_IP_dns" }}

  # global health check
  health :{{ env "NOMAD_PORT_health" }}

  hosts {
    172.16.1.1  fritz.box
  }
  header { 
    response set ra # set RecursionAvailable flag
  }

  errors
  prometheus {{ env "NOMAD_ADDR_metrics" }}
}

### *.lab.home Traefik reverse proxy
lab.home.:53 {
  bind {{ env "NOMAD_IP_dns" }}

  file /local/coredns/zones/db.home.lab lab.home
  header { 
    response set ra # set RecursionAvailable flag
  }

  errors
  prometheus {{ env "NOMAD_ADDR_metrics" }}
}

### *.lab.schoger.net Traefik reverse proxy
lab.schoger.net.:53 {
  bind {{ env "NOMAD_IP_dns" }}

  file /local/coredns/zones/db.net.schoger.lab lab.schoger.net
  header { 
    response set ra # set RecursionAvailable flag
  }

  errors
  prometheus {{ env "NOMAD_ADDR_metrics" }}
}

### Local devices from the DHCP server (UXG-lite)
home. {
  bind {{ env "NOMAD_IP_dns" }}

  forward . 192.168.0.1:53 # router

  errors
  prometheus {{ env "NOMAD_ADDR_metrics" }}
}

### services registered in the Consul catalog
consul. {
  bind {{ env "NOMAD_IP_dns" }}

  forward . {{ env "NOMAD_IP_dns" }}:8600 # Consul running on the same machine
  header { 
    response set ra # set RecursionAvailable flag
  }

  errors
  prometheus {{ env "NOMAD_ADDR_metrics" }}
}

### everything else (internet)
. {
  bind {{ env "NOMAD_IP_dns" }}

  cache {
    success 100              # cache 100*256 DNS entries max

    prefetch 5 10m           # prefetch entries which saw 5 queries in 10 minutes before they become stale
    serve_stale 1h immediate # serve stale cache entries (max age 1h), then validate
  }

  {{- $dns_forward := "192.168.0.1:53" }}{{- /* init with router IP */}}
  {{- range service "adguard-dns" }}{{- /* iterates over [0..1] instances of the adguard-dns service  */}}
    {{- $dns_forward = print .Address ":" .Port }}{{- /* overwrite with AdGuard ip:port if service is present */}}
  {{- end}} 
  forward . {{ $dns_forward }}{{- /* generate forward entry */}}
  
  errors
  prometheus {{ env "NOMAD_ADDR_metrics" }}
}

EOH
      }

      template {
        change_mode   = "signal"
        change_signal = "SIGUSR1"
        destination = "local/coredns/zones/db.home.lab"
        data = <<EOH
$ORIGIN lab.home.
$TTL    604800
lab.home.         IN SOA	ns1.lab.home. admin.lab.home. (
                  1        ; Serial, TODO: use timestamp
             604800        ; Refresh
              86400        ; Retry
            2419200        ; Expire
             604800 )      ; Negative Cache TTL

; name servers - NS records
lab.home.         IN NS	 ns1.lab.home.
lab.home.         IN NS	 ns2.lab.home.

; name servers - A records
ns1               IN A   192.168.0.30
ns2               IN A   192.168.0.31

{{- /*  Point domains to the Traefik reverse proxy listening to the floating IP from keepalived */}}
; services - A records
lab.home.         IN A   192.168.0.3
*                 IN A   192.168.0.3

EOH
      }

      template {
        change_mode   = "signal"
        change_signal = "SIGUSR1"
        destination = "local/coredns/zones/db.net.schoger.lab"
        data = <<EOH
$ORIGIN lab.schoger.net.
$TTL    604800
lab.schoger.net.  IN SOA	ns1.lab.schoger.net. admin.lab.schoger.net. (
                  1        ; Serial, TODO: use timestamp
             604800        ; Refresh
              86400        ; Retry
            2419200        ; Expire
             604800 )      ; Negative Cache TTL

; name servers - NS records
lab.schoger.net.         IN NS	 ns1.lab.schoger.net.
lab.schoger.net.         IN NS	 ns2.lab.schoger.net.

; name servers - A records
ns1               IN A   192.168.0.30
ns2               IN A   192.168.0.31

{{- /*  Point domains to the Traefik reverse proxy listening to the floating IP from keepalived */}}
; services - A records
lab.schoger.net.         IN A   192.168.0.3
*                        IN A   192.168.0.3

EOH
      }
    }
  }
}
