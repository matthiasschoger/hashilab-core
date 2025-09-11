# Full configuration options can be found at https://www.nomadproject.io/docs/configuration

advertise {
  # don't advertise the docker network on 172.16/12
  http = "{{ GetPrivateInterfaces | include \"network\" \"192.168.0.0/16\" | attr \"address\" }}"
  rpc  = "{{ GetPrivateInterfaces | include \"network\" \"192.168.0.0/16\" | attr \"address\" }}"
  serf = "{{ GetPrivateInterfaces | include \"network\" \"192.168.0.0/16\" | attr \"address\" }}"
}

server {
  enabled = true
  bootstrap_expect = 3
}

acl {
  enabled = true
}

