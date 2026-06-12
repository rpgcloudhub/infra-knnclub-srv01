# Inventário Operacional — prd-knn-hil-01 (KNNClub)

> Gerado em 2026-06-12 conforme GDSL → Observar → Inventário e documentação.
> Atualizar a cada mudança de infraestrutura.

## Servidor

| Campo | Valor |
|---|---|
| Hostname | prd-knn-hil-01 |
| Provedor | Hetzner Cloud — Hillsboro, Oregon (us-west) |
| IP público | 5.78.232.26 (oculto atrás da Cloudflare) |
| IP VPN | 10.66.0.1 (WireGuard, subnet 10.66.0.0/24) |
| SO | Ubuntu 26.04 LTS |
| Recursos | 2 vCPU / 7.6GB RAM / 75GB NVMe |
| Timezone | America/Sao_Paulo · NTP via chrony |

## Acesso

| Tipo | Como | Quem |
|---|---|---|
| SSH | `ssh rpg@10.66.0.1` (somente via VPN) | rpg (humano) |
| SSH | via IP 91.99.105.166 (exceção firewall) | jurumigo (Claude, admin) |
| Root | DESABILITADO (sudo via rpg/jurumigo) | — |
| Senha SSH | DESABILITADA (somente chaves) | — |
| Painéis web | somente via VPN (split-horizon DNS → 10.66.0.1) | rpg |

## Serviços (12 containers)

| Serviço | Imagem | Compose | Acesso |
|---|---|---|---|
| traefik | traefik:v3.6 | /srv/apps/traefik | portas 80/443 (só IPs Cloudflare) |
| knnclub_web | knnclub-web (build) | /srv/apps/knnclub | https://knnclub.com |
| knnclub_api | knnclub-api (build) | /srv/apps/knnclub | https://api.knnclub.com |
| knnclub_postgres | postgres:16-alpine | /srv/apps/knnclub | interno |
| knnclub_redis | redis:7-alpine | /srv/apps/knnclub | interno |
| knnclub_minio | minio/minio | /srv/apps/knnclub | interno (bucket: knnclub) |
| uptime-kuma | louislam/uptime-kuma:2 | /srv/apps/uptime-kuma | https://uptime.knnclub.com (VPN) |
| netdata | netdata/netdata:stable | /srv/apps/netdata | https://netdata.knnclub.com (VPN) |
| loki | grafana/loki:3 | /srv/apps/logs | interno (retenção 15d) |
| promtail | grafana/promtail:3 | /srv/apps/logs | interno |
| grafana | grafana/grafana:latest | /srv/apps/logs | https://grafana.knnclub.com (VPN) |
| homepage | gethomepage:latest | /srv/apps/homepage | https://home.knnclub.com (VPN) |

## Dados persistentes (/srv/data/)

knnclub (postgres, redis, minio, logs) · traefik (certs LE em letsencrypt/acme.json, tls.yml.bak = cert Origin aposentado, cf-token) · uptime-kuma · netdata · loki · grafana · promtail · homepage

## Rede e segurança

- **DNS/CDN:** Cloudflare (domínio registrado lá). Proxied: @, api, www. DNS-only → 10.66.0.1: uptime, netdata, grafana, home.
- **TLS:** Let's Encrypt via DNS-01 (resolver `le`, token CF em /srv/data/traefik/cf-token). Renovação automática.
- **Firewall:** ufw deny default (22 só VPN+91.99.105.166; 51820/udp aberto) + chain CLOUDFLARE_V4 (80/443 só Cloudflare, script /usr/local/bin/cloudflare-firewall.sh, cron semanal seg 4h + @reboot).
- **WAF Cloudflare:** 3 custom rules (scanners, paths proibidos, geo-block CN/RU/IR/KP).
- **fail2ban:** sshd, 5 tentativas → ban 30min.
- **VPN:** WireGuard wg0, 1 peer (rpg). Config: /etc/wireguard/wg0.conf.

## Monitoramento e alertas

| Camada | Ferramenta | Alerta |
|---|---|---|
| Disponibilidade | Uptime Kuma (monitores: web, api) | Discord webhook |
| Recursos (CPU/RAM/disco) | Netdata (alertas stock) | Discord webhook |
| Erros em logs | Grafana alert rule "Erros em massa" (>10 err/5min, pending 5m) | Discord webhook |

## Procedimentos rápidos

- **Deploy do app:** `cd /srv/apps/knnclub && git pull && docker compose up -d --build`
- **Logs de um serviço:** Grafana → Explore → Loki → `{container="knnclub_api"}` (ou `docker logs -f <nome>`)
- **Reiniciar serviço:** `cd /srv/apps/<serviço> && docker compose restart`
- **Reboot do host:** seguro — tudo volta sozinho (restart: unless-stopped; teste validado: 26s de downtime)
- **Firewall Cloudflare:** reaplicar manualmente com `sudo /usr/local/bin/cloudflare-firewall.sh`
- **Snapshots:** painel Hetzner antes de toda mudança estrutural (padrão `fase-<etapa>-ok`)

## Pendências conhecidas

- Fase MANTER do GDSL: backup automatizado (postgres+minio), housekeeping, rotina de atualizações
- Super-admin do app (banco zerado)
- Umami (analytics) próprio ou remoção do .env
- /metrics da API: restringir à rede interna no Traefik
