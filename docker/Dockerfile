FROM headscale/headscale:latest

COPY config/config.yaml /etc/headscale/config.yaml
COPY config/acl_policy.hujson /etc/headscale/acl_policy.hujson
COPY scripts/init.sh /init.sh
RUN chmod +x /init.sh

EXPOSE 8080 9090 50443

ENTRYPOINT ["/init.sh"]
