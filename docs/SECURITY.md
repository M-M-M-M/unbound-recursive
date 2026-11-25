# Threat model and encrypted DNS design

## Implemented defaults

Unbound performs iterative recursion using root hints and the DNSSEC trust
anchor from Debian. No forward-zone exists in the supplied configuration.
DNSSEC validates signed data, not confidentiality or safety of domains. QNAME
minimization helps limit disclosure to authoritative servers. External recursion
usually uses plaintext DNS. Unlike a filtering provider, this is not a malware
blocklist service.

Default listeners are host loopback only. Container process is non-root with
all capabilities dropped, read-only root, private writable state/tmpfs, bounded
resources and no Docker socket. The control socket is an administrative interface.
Default IPv4-only is intentional; AAAA lookup support is independent. Review
Docker version and actual network exposure, including IPv6, before production.
Neither rate limits nor minimal responses make an open UDP resolver safe.
Reflection/amplification can cause third-party harm, bandwidth saturation and
provider abuse reports. TCP mitigates spoofed reflection but not application
DoS, unauthorized use or network saturation. No automated attacker blocking is
implemented yet. Docker logging caps are not network quotas.

## Encrypted client access (design only)

Apply the [hardening gates](HARDENING.md) to every new frontend.

| Transport | Port | Client authentication | Notes |
| --- | --- | --- | --- |
| Classic UDP/TCP | 53 | Network ACL | Private networks only |
| DoT | TCP 853 | mTLS where supported | Ordinary DoT usually authenticates server only |
| DoH | TCP 443 | mTLS, HTTP header/token, or secret URL where supported | HTTPS alone does not authenticate clients |
| DoQ / HTTP/3 | UDP 853 / 443 | Implementation-dependent | Deferred; assess QUIC amplification and resource controls |
| WireGuard | Configurable UDP | Peer keys | Optional; not mandatory for all clients |

Use existing HAProxy/Dehydrated where relevant; the candidate optional DNS-aware
frontend is [dnsdist](https://www.dnsdist.org/), developed by PowerDNS. It
would handle DoH/DoT, traffic analysis, rate limits and dynamic blocking;
no PowerDNS recursive resolver is needed. This frontend is not implemented. Backend listens only
on isolated network or loopback, never exposed directly. HTTPS backend port
must be selected after checking all live HAProxy includes, Compose and sockets
in the approved 8000–8099 range; no port reserved here. Check TLS renewal, cert
permissions, IPv4/IPv6, and validate complete HAProxy config before authorized
reload. Use the local central service for signed `/.well-known/security.txt`,
`/humans.txt`, `/pgp-key.asc`, canonical HTTPS per FQDN, verified contact and
expiration/monitoring before HTTP publication.

### Authentication options to qualify

- A DoH client that supports Authorization headers can send a unique revocable
  credential over HTTPS. Do not assume OS-native resolvers support this.
- A high-entropy per-client URL token may be accepted by URL-configurable DoH
  clients, but can leak through access logs, diagnostics, history or profiles.
  Reject missing/invalid tokens before forwarding, avoid URL logging entirely,
  rotate and revoke individually, never send tokens in public examples.
- mTLS authenticates the client cryptographically; confirm client certificate
  selection and enrollment support, revocation, and certificate lifecycle.
- Standard Android Private DNS/DoT and many appliances have no convenient
  client authentication support. For them prefer private LAN resolver or a
  router/local relay. macOS/iOS encrypted DNS profiles, browsers and Linux
  resolvers need a concrete tested client/version matrix; no compatibility
  assertion yet. RFC 8484 does not require arbitrary auth support by clients.

Secrets must use the existing approved 1Password -> SOPS/age framework; inspect
its actual interface before implementation. Reuse the existing trust-domain age
identity only when readers are appropriate; dedicated identity when justified.
Protect runtime files, decrypt administratively at last moment, exclude secrets
from Git, logs, arguments and backups in plaintext. No secrets in core v0.1.

## Acceptance gates for future public encrypted service

Valid client allowed, missing/invalid/revoked credentials denied without backend
query, no direct backend access, certificate validation and renewal, no secret
leak in logs, bounded concurrency/rates/queues, safe error responses and
monitoring. Verify source IP attribution at the trusted proxy boundary. Test
both address families and separate prod/test credentials. Prefer staged blocking
and explicit recovery to broad automated IP bans. Obtain approval before exposing
any service.

References: https://www.rfc-editor.org/rfc/rfc5358,
https://www.rfc-editor.org/rfc/rfc8484,
https://unbound.docs.nlnetlabs.nl/en/latest/manpages/unbound.conf.html.
