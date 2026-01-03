<h1>Hashilab Core</h1>

<h2>Motivation</h2>

This project was born out of boredom during the Covid pandemic, when I wanted to replace my already existing Docker homelab with something more advanced. After playing around with k8s for a bit, I decided that Nomad is a great fit for a hobby project, compared to k8s which felt more like something you would do for a job.

With k8s, it felt to me like I was reciting the rotes of the church of Helm, without really understanding what I was doing or why. With Nomad and Consul, I could "grok" the concepts without making it a job and find solutions to the specific issues I was facing.

<h2>Goals of this project</h2>

My main goals for my new homelab were the following
- High-Availablity - I want to shut down or lose any node, and my cluster should heal itself. With all services being available again after a couple of seconds.
- Observability - I'm a sucker for graph p*rn, and want to have as much insight as possible into what my homelab is currently doing.
- Scratch my technical itch. Since I move into a sales position right before Covid, I needed some tech stuff to do.

To keep the jobs manageable, I've split them into three repositories
- [hashilab-core](https://github.com/matthiasschoger/hashilab-core): Basic infrastructure which contains load-balancing, reverse proxy, DNS and ingress management.
- [hashilab-support](https://github.com/matthiasschoger/hashilab-support): Additional operational stuff like metrics management, Cloudflare tunnel, maintenance tasks and much more stuff to run the cluster more effienctly.
- [hashilab-apps](https://github.com/matthiasschoger/hashilab-apps): End-user apps like Vaultwarden or Immich.

<h2>Hashilab-core</h2>

The "core" repository defines a bare-bone HA setup based on Nomad and Consul (Connect). 

CoreDNS resolves requests to *.lab.domain.tld to the floating IP managed by keepalived, assigned to one of the two compute nodes. Both compute nodes run an Consul ingress gateway, which picks up the traffic and routes it to traefik-home, where the traffic is finally routed to the target service based on annotations on that service. Super simple once it is set up.

- consul-ingress - Receives the traffic to the cluster and routes it to traefik-home via the Consul Connect Software Define Network. Other services like Loki or SMTP are routed directly to the respective services.
- core-dns - "it's always DNS", but with CoreDNS I can be sure that DNS is always working. Stateless, no moving parts, and spread over the two compute nodes. Robust as hell and does what it's supposed to do. 
- keepalived - Load-balancer which assigns a floating IP to one of the compute nodes. Assures that the floating IP points to a live node as long as one is available.
- nfs-csi-contoller - CSI which allows to mount NFS shares from my Synology into Nomad services and assures that only a single alloc is accessing the persistant data on the NAS share.
- traefik-home: Reverse proxy which picks up configurations from service annotations and routes the traffic to those services. Also provides Let's Encrypt certificates for all my services.

<h2>Deployment Notes</h2>

Before deploying a job file, you should set the following environment variable on the deploying machine
- NOMAD_VAR_base_domain=domain.tld

where 'domain.tld' is the domain you are using.

In addition, quite a few sensitive settings like passwords and email are stored in Nomad variables. Search for "nomadVar" to find the relevant locations.
