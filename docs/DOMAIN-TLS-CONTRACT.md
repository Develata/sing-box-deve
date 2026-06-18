# Domain TLS and archive gateway contract

## Deployment presets

`sing-box-deve` exposes three installation presets:

- `reality-only`: deploy only `vless-reality`; no domain certificate is required.
- `reality-plus-domain`: deploy `vless-reality,hysteria2,tuic,naive`; a trusted domain certificate is required.
- `full`: deploy every supported sing-box public inbound (`vless-reality,vless-ws,shadowsocks-2022,naive,hysteria2,tuic`); a trusted domain certificate is required because the set includes domain-certificate protocols.

Manual `--protocols` remains supported. The domain-certificate gate is protocol-driven, not wizard-only: if a selected protocol requires a trusted certificate, CLI and config rebuild flows must enforce the same gate.

## Domain-certificate protocols

The following public protocols require a user-controlled domain and a valid certificate:

- `hysteria2`
- `tuic`
- `naive`

Future ordinary TLS public protocols must be added to the same protocol attribute before exposure.

`vless-reality` does not require a user-controlled certificate. `shadowsocks-2022` does not require TLS. Compatibility transports that do not use the domain certificate gate must not silently emit insecure client links.

## Certificate sources

For domain-certificate protocols, the script accepts only:

1. Explicit certificate paths: `--tls-mode acme --acme-cert-path <fullchain> --acme-key-path <key> --tls-sni <domain>`.
2. Existing local certificates detected at conservative known paths, currently Let's Encrypt and acme.sh locations.
3. Automatic issue via `acme.sh --webroot` through the managed OpenResty/nginx archive-gateway web front: `--tls-mode acme-auto --tls-sni <domain> --acme-email <email>`.
4. Manual retry by providing certificate paths after a failed automatic attempt.

The script must not use standalone ACME that competes for TCP 80. It may create/update its own OpenResty/nginx server block for HTTP-01 webroot validation and then replace it with the final HTTPS archive-gateway server block after certificate validation.

## TCP web front

Domain-certificate presets generate one archive-gateway static site and expose it on two surfaces:

1. TCP 80/443 web front for ordinary browser and active-probe access.
2. Hysteria2 `masquerade` fallback for HTTP/3 authentication-failure behavior.

Web front selection is conservative:

- if OpenResty is already installed, use OpenResty;
- else if nginx is already installed, use nginx;
- else ask whether to install nginx from the official nginx.org package repository;
- `--web-front off` disables TCP web-front management and leaves only Hysteria2 masquerade.

The script does not install OpenResty automatically. It may create a managed server block for the detected web front and reload/restart that service after a successful syntax test.

## Certificate validation

Before generating configs for domain-certificate protocols, the script validates:

- domain is syntactically valid and not an IP literal;
- certificate and key files exist;
- certificate is not expired or within the immediate expiry window;
- certificate SAN matches the selected TLS server name;
- certificate and private key match.

If validation fails, installation/config rebuild must fail fast instead of generating insecure or half-working nodes.

## Client links

Client links for domain-certificate protocols must not include insecure skip-verification parameters such as `insecure=1` or `allow_insecure=1`. They should carry `sni=<domain>` and rely on normal certificate verification.

Self-signed certificates are only allowed for protocols that do not require the domain-certificate gate, or for explicit future advanced certificate pinning modes. They are not the default share-link path.

## Archive gateway camouflage

When domain-certificate protocols are enabled, the script creates a small static archive gateway site. Its purpose is baseline active-probe surface only; it does not claim to explain every byte of protocol traffic.

Requirements:

- no Develata personal information;
- randomized 6–7 character site owner identifier;
- generic computer-materials archive wording;
- no fake login page;
- no large local assets;
- no third-party copyrighted media;
- pages: index, archive, status, 404, robots, sitemap, style, small manifest/checksum files.

The site narrative is a lightweight personal computer-materials archive gateway: public metadata is small, large artifacts are off-site or private synchronization and not publicly listed.

## Hysteria2 obfuscation

Hysteria2 obfuscation is optional and disabled by default. The exposed mode is `salamander`:

```bash
--hy2-obfs salamander [--hy2-obfs-password PASSWORD]
```

If enabled without a password, the script generates and persists a strong random password. Client links include `obfs=salamander&obfs-password=...` according to the official Hysteria2 URI scheme.

Obfuscation is not the default because Hysteria2 documents that obfs makes the server incompatible with standard QUIC/HTTP3 behavior. The TCP web front remains responsible for normal browser access to the domain.
