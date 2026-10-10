# Proxies

updatool never runs a proxy of its own: it writes **one route file** for the
proxy you already have and lets that proxy reload gracefully.

## Traefik (file provider)

```bash
PROXY=traefik
TRAEFIK_FILE=/opt/traefik/dynamic/shop.yml   # inside the file-provider DIRECTORY
TRAEFIK_RULE='Host(`shop.example.com`)'
TRAEFIK_ENTRYPOINTS=websecure
TRAEFIK_CERTRESOLVER=letsencrypt
NETWORK=web                                  # Traefik and the slots share it
```

Traefik must watch a **directory**:

```yaml
# traefik static config
providers:
  file:
    directory: /dynamic
    watch: true
```

and that directory must be bind-mounted as a directory (`-v /opt/traefik/dynamic:/dynamic:ro`).
A single-file bind mount keeps pointing at the old inode after the atomic rename.

Already have routers (middlewares, redirects) you want to keep? Set
`TRAEFIK_SERVICE_ONLY=1`: updatool writes only `http.services.<APP>`, and your
routers keep `service: <APP>`. Remove that service from your own file first —
Traefik rejects a service defined twice.

## Caddy

```bash
PROXY=caddy
CADDY_FILE=/etc/caddy/upstreams/shop.caddy
CADDY_RELOAD="docker exec caddy caddy reload --config /etc/caddy/Caddyfile"
```

```caddyfile
shop.example.com {
    import /etc/caddy/upstreams/shop.caddy   # updatool writes: reverse_proxy shop-green:3000
}
```

`caddy reload` is graceful: open connections finish on the old config.

## Nginx

```bash
PROXY=nginx
NGINX_FILE=/etc/nginx/conf.d/shop-upstream.conf
NGINX_RELOAD="docker exec nginx sh -c 'nginx -t && nginx -s reload'"
```

```nginx
# updatool writes: upstream shop { server shop-green:3000; keepalive 16; }
server {
    server_name shop.example.com;
    location / { proxy_pass http://shop; proxy_http_version 1.1; proxy_set_header Connection ""; }
}
```

Always test before reloading (`nginx -t && …`): `nginx -s reload` alone returns
success even when the new config is invalid.

## Proxy on the host (not in Docker)

Publish the slots on two local ports instead of sharing a network:

```bash
SLOT_HOST_PORTS="3001 3002"   # blue → 127.0.0.1:3001, green → 127.0.0.1:3002
```

## No proxy

`PROXY=none` runs everything except the route switch — useful for workers,
queues and cron containers, combined with `HOOK_POST_SWITCH`.
