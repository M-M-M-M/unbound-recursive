FROM debian:trixie-slim
LABEL org.opencontainers.image.source="https://github.com/M-M-M-M/unbound-recursive" \
      org.opencontainers.image.description="Private recursive DNS resolver with DNSSEC" \
      org.opencontainers.image.licenses="MIT"
RUN apt-get update && apt-get install -y --no-install-recommends \
      unbound dns-root-data bind9-dnsutils ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -m 0750 -o 10001 -g 10001 /state /run/resolver \
    && test -s /usr/share/dns/root.key && test -s /usr/share/dns/root.hints
COPY config/unbound.conf /etc/unbound/recursive.conf
COPY --chmod=0755 scripts/entrypoint.sh scripts/healthcheck.sh /usr/local/bin/
USER 10001:10001
EXPOSE 5353/udp 5353/tcp
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]
