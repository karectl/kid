# Cheat sheet

## kubectl

```bash
k get pods -A                                   # everything, everywhere
k get pods -n project-alpha -o wide --show-labels
k describe pod <pod> -n <ns>                    # events at the bottom are gold
k logs deploy/hub -n jupyterhub -f              # follow logs
k logs <pod> -n <ns> --previous                 # logs of the last crashed container
k exec -it <pod> -n <ns> -- bash                # shell inside a container
k get events -n <ns> --sort-by=.lastTimestamp
k get <kind> <name> -n <ns> -o yaml
k explain <kind>.spec --recursive | less
k top node ; k top pod -A --sort-by=memory
k auth can-i <verb> <resource> -n <ns> --as system:serviceaccount:<ns>:<sa>
k api-resources | grep -i <word>
```

## TRE-specific selectors

```bash
k get ns -l k8tre.io/type=project                       # projects
k get pods -A -l component=singleuser-server            # workspaces
k get cnp -A                                            # Cilium policies
k get cpol ; k get polr -A                              # Kyverno policies / reports
k -n argocd get applications                            # Argo CD apps
```

## Cilium / Hubble

```bash
cilium status
tre hubble                                              # port-forward relay (once)
hubble observe --namespace <ns> --follow
hubble observe --namespace <ns> --verdict DROPPED
hubble observe --namespace <ns> --protocol dns
hubble observe --from-pod <ns>/<pod> --to-namespace <ns2>
k -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg endpoint list
k -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg fqdn cache list
```

## Argo CD

```bash
tre status ; tre sync
argocd login --core && k config set-context --current --namespace=argocd
argocd app list ; argocd app get <app> ; argocd app diff <app>
k config set-context --current --namespace=default
```

## Helm

```bash
helm template root gitops/apps                          # render the app of apps
helm template p gitops/projects/chart --set name=test   # render a project
helm lint gitops/apps gitops/projects/chart
```

## Kubescape

```bash
kubescape scan framework nsa --include-namespaces project-alpha,project-beta
kubescape scan gitops/
```

## Docker (inside the dev container)

```bash
docker ps                                               # devcontainer + k3s-server
docker exec -it $(docker ps -qf name=k3s-server) sh     # a shell on the "node"
docker stats --no-stream                                # memory of the two containers
```
