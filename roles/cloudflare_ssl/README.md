# Ansible Role: ansible_ssl_cloudflare

Automated SSL certificate generation using Cloudflare DNS validation with Let's Encrypt.

## Description

This role automates the process of obtaining SSL/TLS certificates from Let's Encrypt using Cloudflare DNS-01 challenge validation. This method is ideal for obtaining wildcard certificates and doesn't require exposing ports 80/443 publicly.

## Requirements

- Ansible 2.15+
- Target OS: Ubuntu 20.04+, Debian 11+
- Cloudflare account with domain managed by Cloudflare
- Cloudflare API token with DNS edit permissions
- `certbot` installed (handled by role or `ansible_common`)

## Role Variables

### Required Variables

```yaml
# Cloudflare API token
cloudflare_api_token: "{{ vault_cloudflare_api_token }}"

# Email for Let's Encrypt notifications
cloudflare_email: "admin@example.com"

# Domain(s) to request certificates for
cloudflare_domains:
  - "example.com"
  - "*.example.com"
```

### Optional Variables

```yaml
# Certificate storage path
cloudflare_cert_path: "/etc/letsencrypt/live"

# Certbot configuration path
cloudflare_config_path: "/etc/letsencrypt"

# Let's Encrypt server (production or staging)
cloudflare_acme_server: "https://acme-v02.api.letsencrypt.org/directory"
```

## Dependencies

None.

## Example Playbook

```yaml
---
- name: Generate SSL certificates
  hosts: web_servers
  become: true
  roles:
    - role: ansible_ssl_cloudflare
```

### With Group Variables (Recommended)

```yaml
# inventories/production/group_vars/webservers/ssl.yml
cloudflare_email: "sysadmin@example.com"
cloudflare_api_token: "{{ vault_cloudflare_api_token }}"
cloudflare_domains:
  - "example.com"
  - "*.example.com"

# inventories/production/group_vars/webservers/vault.yml (encrypted)
vault_cloudflare_api_token: "your_cloudflare_api_token_here"
```

## What This Role Does

1. Installs certbot and Cloudflare DNS plugin
2. Creates Cloudflare credentials file
3. Requests certificate using DNS-01 challenge
4. Configures automatic certificate renewal
5. Sets appropriate file permissions

## DNS-01 Challenge Benefits

- **Wildcard Certificates**: Can issue `*.example.com` certificates
- **No Port Exposure**: Doesn't require opening ports 80/443
- **Behind Firewall**: Works for internal-only servers
- **Validation**: Proves domain ownership via DNS records

## Certificate Renewal

Certificates are automatically renewed by certbot's systemd timer. The role ensures:
- Renewal happens 30 days before expiration
- DNS credentials are available for renewal
- Certificates are validated after renewal

## File Locations

After successful deployment:
```
/etc/letsencrypt/
├── live/
│   └── example.com/
│       ├── fullchain.pem  # Certificate + chain
│       ├── privkey.pem    # Private key
│       ├── cert.pem       # Certificate only
│       └── chain.pem      # Intermediate chain
└── renewal/
    └── example.com.conf   # Renewal configuration
```

## Tags

- `ssl` - SSL-related tasks
- `cloudflare` - Cloudflare-specific tasks
- `certificates` - Certificate tasks

## Using Certificates

### With Nginx

```nginx
server {
    listen 443 ssl;
    server_name example.com;
    
    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
}
```

### With Apache

```apache
<VirtualHost *:443>
    ServerName example.com
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/example.com/cert.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/example.com/privkey.pem
    SSLCertificateChainFile /etc/letsencrypt/live/example.com/chain.pem
</VirtualHost>
```

## Troubleshooting

### Certificate Request Fails

1. Verify Cloudflare API token has DNS edit permissions
2. Check domain is in Cloudflare account
3. Ensure DNS is propagated
4. Review certbot logs: `/var/log/letsencrypt/letsencrypt.log`

### Renewal Fails

1. Check Cloudflare API token is still valid
2. Verify credentials file exists and is readable
3. Test renewal manually: `certbot renew --dry-run`

## Security Notes

- Store Cloudflare API token in Ansible Vault
- Use API tokens (not Global API Key)
- Restrict token permissions to DNS edit only
- Set appropriate file permissions (600 for private keys)
- Rotate API tokens periodically

## Let's Encrypt Rate Limits

Be aware of Let's Encrypt rate limits:
- 50 certificates per domain per week
- Use staging server for testing: `cloudflare_acme_server: "https://acme-staging-v02.api.letsencrypt.org/directory"`

## License

MIT

## Author

Dan Wallace
