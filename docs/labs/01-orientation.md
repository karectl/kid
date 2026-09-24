# Lab 1: Orientation

**Objectives**: talk to the cluster, see how the TRE is laid out, and get used to reading
Kubernetes objects.

## 1. The cluster and its nodes

```bash
kubectl cluster-info
kubectl get nodes -o wide
```

One node, `k3s-server`. That is the Docker container next to your dev container. Its
`INTERNAL-IP` is on the Docker network.

## 2. Namespaces are the map

```bash
kubectl get namespaces --show-labels
```

Find the two project namespaces. Which labels mark them as projects? Filter on them:

```bash
kubectl get ns -l k8tre.io/type=project
kubectl get ns project-alpha -o yaml
```

Look at the **annotations**. JupyterHub builds its launch menu from them (lab 2).

## 3. What is running?

```bash
kubectl get pods -A
kubectl get pods -A -o wide --sort-by=.metadata.namespace
tre usage
```

Pick three pods and say which TRE component each belongs to. Use the
[architecture page](../concepts/architecture.md) if you're unsure.

## 4. How traffic gets in

```bash
kubectl get ingress -A
kubectl -n jupyterhub get svc
```

Match each Ingress path to a line in the [URL map](../concepts/architecture.md#url-map).

## 5. Where it all came from

```bash
tre status
kubectl -n argocd get application root -o yaml | grep -A3 "source:"
```

`repoURL` should be **your** fork (or the upstream repository if you cloned). Open Argo CD in the
browser (`/argocd/`, password from `tre info`) and click into **project-alpha**. You'll see the
Namespace, ResourceQuota, LimitRange, PVC, RoleBinding and CiliumNetworkPolicy it created.

## 6. Ask the API what things are

```bash
kubectl explain resourcequota.spec
kubectl explain ciliumnetworkpolicy.spec.egress --recursive | head -40
kubectl api-resources | grep -Ei "cilium|kyverno|argoproj"
```

The last command lists the **CRDs** that Cilium, Kyverno and Argo CD added to the API.

## Check your understanding

1. Why does `kubectl` in the dev container work at all? (Hint: `cat ~/.kube/config`.)
2. Which namespaces does Argo CD manage, and which were created by the bootstrap script?
3. What would happen if you deleted the `portal` Deployment? Try it:
   `kubectl -n portal delete deploy portal`, then `kubectl -n portal get deploy -w`.
