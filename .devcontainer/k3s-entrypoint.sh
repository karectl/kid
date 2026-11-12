#!/bin/sh
# Entrypoint for the k3s-server container (mounted by docker-compose.yml).
#
# 1. Prepare the mounts Cilium needs (shared mount propagation + BPF filesystem).
# 2. Choose the upstream DNS server the cluster forwards external lookups to.
# 3. Start k3s without its own CNI (Flannel) or network policy controller:
#    Cilium, installed by bootstrap.sh, does both.
set -eu

mount --make-rshared /
mount bpffs -t bpf /sys/fs/bpf 2>/dev/null || true
mount --make-shared /sys/fs/bpf

# ---------------------------------------------------------------------------
# Upstream DNS
#
# Docker gives this container "nameserver 127.0.0.11" (Docker's built-in DNS).
# That address only works inside this container's own network namespace, so
# k3s refuses it for pods and falls back to Google DNS (8.8.8.8). Many
# corporate, university, NHS and VPN networks block DNS to public resolvers,
# so CoreDNS times out and nothing in the cluster can resolve github.com
# (Argo CD shows "lookup github.com on 10.43.0.10:53: server misbehaving").
#
# Docker records the real upstream servers in a comment in the same file, e.g.
#   # ExtServers: [host(192.168.65.7)]
# We hand those to k3s instead. Loopback addresses (127.x, e.g. systemd-resolved
# on a Linux host) are skipped because pods cannot reach them.
#
# Override with KID_UPSTREAM_DNS (space-separated IPv4 addresses), for example
# KID_UPSTREAM_DNS=8.8.8.8 to restore the old behaviour. If nothing usable is
# found, k3s keeps its default (8.8.8.8).
upstream="${KID_UPSTREAM_DNS:-}"
if [ -z "${upstream}" ]; then
  upstream="$(
    sed -n 's/^# ExtServers: \[\(.*\)\]$/\1/p' /etc/resolv.conf \
      | tr ' ' '\n' \
      | sed -e 's/^host(//' -e 's/)$//' \
      | grep -E '^[0-9]+(\.[0-9]+){3}$' \
      | grep -v '^127\.' \
      | tr '\n' ' ' || true
  )"
fi

set --
if [ -n "${upstream}" ]; then
  : > /etc/k3s-resolv.conf
  for ns in ${upstream}; do
    echo "nameserver ${ns}" >> /etc/k3s-resolv.conf
  done
  echo "kid: cluster upstream DNS -> ${upstream}"
  set -- --resolv-conf=/etc/k3s-resolv.conf
else
  echo "kid: no usable upstream DNS found; using the k3s default"
fi

exec /bin/k3s server --flannel-backend=none --disable-network-policy "$@"
