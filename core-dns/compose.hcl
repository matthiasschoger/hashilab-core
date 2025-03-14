variable "base_domain" {
  default = "missing.environment.variable"
}

job "coredns" {
  datacenters = ["home"]
  type        = "system"

  group "coredns" {

    network {
      port "dns" { static = "53"  }
      port "metrics" { static = "9153" }
      port "health" { }
    }

   task "server" {
      driver = "docker"

      config {
        # fixed version tag to allow for container caching
        # "latest" will always pull a new container from DockerHub, which would fail if no DNS is available
        image = "coredns/coredns:1.12.0" 

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

      #templates (corefile + lab.domain.tld zone file)
      template {
        destination = "local/coredns/corefile"
        change_mode   = "signal"
        change_signal = "SIGUSR1"
        data = <<EOH
### snippets for later use
(headers) {
  header { 
    response set ra # set RecursionAvailable flag
  }
}

(default) {
  errors
  prometheus {{ env "NOMAD_ADDR_metrics" }}
}

### fritz.box to resolve the network printer
fritz.box. {
  bind {{ env "NOMAD_IP_dns" }}

  hosts {
    172.16.1.1  fritz.box
  }

  import headers
  import default
}

### *.lab.${var.base_domain} floating IP
lab.${var.base_domain}. {
  bind {{ env "NOMAD_IP_dns" }}

  file /local/coredns/zones/db.home.lab lab.${var.base_domain}

  import headers
  import default
}

### resolve "unifi" to ingress gateway for Ubiquiti device adoption
unifi. {
  bind {{ env "NOMAD_IP_dns" }}

  hosts {
    192.168.0.3  unifi
  }

  import headers
  import default
}

### Local devices from the DHCP server (UXG-lite)
home. {
  bind {{ env "NOMAD_IP_dns" }}

  forward . 192.168.0.1:53 # router

  import default
}

### services registered in the Consul catalog
consul. {
  bind {{ env "NOMAD_IP_dns" }}

  forward . {{ env "NOMAD_IP_dns" }}:8600 # Consul running on the same machine

  import headers
  import default
}

### everything else (internet)
. {
  bind {{ env "NOMAD_IP_dns" }}

  cache {
    success 1000             # cache 1000*256 DNS entries max

    prefetch 5 10m           # prefetch entries which saw 5 queries in 10 minutes before they become stale
    serve_stale 1h immediate # serve stale cache entries (max age 1h), then validate
  }

  {{- $dns_forward := "192.168.0.1:53" }}{{- /* init with router IP */}}
  {{- range service "adguard-dns" }}{{- /* iterates over [0..1] instances of the adguard-dns service  */}}
    {{- $dns_forward = print .Address ":" .Port }}{{- /* overwrite with AdGuard ip:port if service is present */}}
  {{- end}} 
  forward . {{ $dns_forward }}{{- /* generate forward entry */}}
  
  import default
}

EOH
      }

      template {
        change_mode   = "signal"
        change_signal = "SIGUSR1"
        destination = "local/coredns/zones/db.home.lab"
        data = <<EOH
$ORIGIN lab.${var.base_domain}.
$TTL    604800
lab.${var.base_domain}.         IN SOA	ns1.lab.${var.base_domain}. admin.lab.${var.base_domain}. (
         {{ timestamp "unix" }}        ; Serial, current unix timestamp
             604800        ; Refresh
              86400        ; Retry
            2419200        ; Expire
             604800 )      ; Negative Cache TTL

; name servers - NS records
lab.${var.base_domain}.         IN NS	 ns1.lab.${var.base_domain}.
lab.${var.base_domain}.         IN NS	 ns2.lab.${var.base_domain}.

; name servers - A records
ns1                      IN A   192.168.0.30
ns2                      IN A   192.168.0.31

{{- /*  Point domains to the floating IP from keepalived */}}
; services - A records
lab.${var.base_domain}.         IN A   192.168.0.3
*                        IN A   192.168.0.3

EOH
      }
    }
  }
}
