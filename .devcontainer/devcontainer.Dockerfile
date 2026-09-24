FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# TARGETARCH is populated automatically by BuildKit (amd64 on Codespaces and
# most PCs, arm64 on Apple Silicon Macs).
ARG TARGETARCH
ARG KUBECTL_VERSION=v1.31.5
ARG HELM_VERSION=v3.16.3
ARG CILIUM_CLI_VERSION=v0.16.22
ARG HUBBLE_VERSION=v1.16.5
ARG ARGOCD_CLI_VERSION=v3.0.0
ARG KUBESCAPE_VERSION=v4.0.14

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl ca-certificates jq gettext-base bash-completion dnsutils \
 && rm -rf /var/lib/apt/lists/*

RUN cd /tmp \
 && curl -sfLo kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
 && curl -sfLo kubectl.sha256 \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256" \
 && echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - \
 && install -m 0755 kubectl /usr/local/bin/kubectl \
 && cd / && rm -rf /tmp/*

RUN cd /tmp \
 && curl -sfLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" \
 && curl -sfLO "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz.sha256sum" \
 && sha256sum -c "helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz.sha256sum" \
 && tar -xzf "helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" \
 && install -m 0755 "linux-${TARGETARCH}/helm" /usr/local/bin/helm \
 && cd / && rm -rf /tmp/*

RUN cd /tmp \
 && curl -sfLO "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${TARGETARCH}.tar.gz" \
 && curl -sfLO "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${TARGETARCH}.tar.gz.sha256sum" \
 && sha256sum -c "cilium-linux-${TARGETARCH}.tar.gz.sha256sum" \
 && tar -xzf "cilium-linux-${TARGETARCH}.tar.gz" -C /usr/local/bin cilium \
 && chmod +x /usr/local/bin/cilium \
 && cd / && rm -rf /tmp/*

RUN cd /tmp \
 && curl -sfLO "https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-linux-${TARGETARCH}.tar.gz" \
 && curl -sfLO "https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-linux-${TARGETARCH}.tar.gz.sha256sum" \
 && sha256sum -c "hubble-linux-${TARGETARCH}.tar.gz.sha256sum" \
 && tar -xzf "hubble-linux-${TARGETARCH}.tar.gz" -C /usr/local/bin hubble \
 && chmod +x /usr/local/bin/hubble \
 && cd / && rm -rf /tmp/*

RUN cd /tmp \
 && curl -sfLo "argocd-linux-${TARGETARCH}" \
      "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_CLI_VERSION}/argocd-linux-${TARGETARCH}" \
 && curl -sfLo cli_checksums.txt \
      "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_CLI_VERSION}/cli_checksums.txt" \
 && grep "  argocd-linux-${TARGETARCH}$" cli_checksums.txt | sha256sum -c - \
 && install -m 0755 "argocd-linux-${TARGETARCH}" /usr/local/bin/argocd \
 && cd / && rm -rf /tmp/*

RUN cd /tmp \
 && KS_ASSET="kubescape_${KUBESCAPE_VERSION#v}_linux_${TARGETARCH}" \
 && curl -sfLo "${KS_ASSET}" \
      "https://github.com/kubescape/kubescape/releases/download/${KUBESCAPE_VERSION}/${KS_ASSET}" \
 && curl -sfLo checksums.sha256 \
      "https://github.com/kubescape/kubescape/releases/download/${KUBESCAPE_VERSION}/checksums.sha256" \
 && awk -v a="${KS_ASSET}" '$2 == a' checksums.sha256 | sha256sum -c - \
 && install -m 0755 "${KS_ASSET}" /usr/local/bin/kubescape \
 && cd / && rm -rf /tmp/*

RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
 && chmod a+r /etc/apt/keyrings/docker.asc \
 && . /etc/os-release \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends docker-ce-cli \
 && rm -rf /var/lib/apt/lists/*

# Shell completion for the CLIs used in the labs, plus the conventional `k` alias.
RUN kubectl completion bash > /etc/bash_completion.d/kubectl \
 && helm completion bash > /etc/bash_completion.d/helm \
 && cilium completion bash > /etc/bash_completion.d/cilium \
 && hubble completion bash > /etc/bash_completion.d/hubble \
 && argocd completion bash > /etc/bash_completion.d/argocd \
 && echo 'alias k=kubectl' >> /etc/bash.bashrc \
 && echo 'complete -o default -F __start_kubectl k' >> /etc/bash.bashrc \
 && echo 'export PATH="/workspace/scripts:${PATH}"' >> /etc/bash.bashrc

USER vscode
