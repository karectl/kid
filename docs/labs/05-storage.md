# Lab 5: Storage

**Objectives**: see how storage is requested, provisioned and scoped; share data within a project
and fail to share it across projects; find where the bytes actually live.

## 1. Classes, claims and volumes

```bash
kubectl get storageclass
kubectl get pvc -A
kubectl get pv -o custom-columns=PV:.metadata.name,NS:.spec.claimRef.namespace,CLAIM:.spec.claimRef.name,CLASS:.spec.storageClassName,RECLAIM:.spec.persistentVolumeReclaimPolicy
```

Match each PVC to its PV. Which reclaim policy does each class have, and why might they differ?

## 2. Share within a project

As **researcher1** (alpha), in a JupyterLab terminal:

```bash
echo "cohort v1 - curated by researcher1" > ~/shared/README.txt
echo "my private notes" > ~/notes.txt
ls -la ~ ~/shared
```

As **researcher3**, stop your server if it runs in beta (**File → Hub Control Panel → Stop My
Server**), then start **Project Alpha**:

```bash
cat ~/shared/README.txt      # visible: same project-shared PVC
ls ~/notes.txt               # not there: each user has their own home PVC
```

## 3. Fail to share across projects

As researcher3, stop again and start **Project Beta**:

```bash
ls ~/shared                  # a different, empty project-shared
```

In the dev container:

```bash
kubectl -n project-alpha get pvc
kubectl -n project-beta  get pvc
```

researcher3 has **two** home volumes, `home-researcher3` in each namespace. Nothing leaks between
projects through `$HOME`.

**Could project-beta mount alpha's PVC?** A pod can only reference PVCs in its own namespace, so
there is no way to even express it. The Kubernetes API has no field for "PVC from another
namespace".

## 4. Where do the bytes live?

```bash
PV=$(kubectl -n project-alpha get pvc project-shared -o jsonpath='{.spec.volumeName}')
HOSTPATH=$(kubectl get pv "$PV" -o jsonpath='{.spec.hostPath.path}{.spec.local.path}')
echo "$HOSTPATH"
K3S=$(docker ps -qf name=k3s-server)
docker exec "$K3S" ls -la /var/lib/rancher/k3s/storage/
docker exec "$K3S" cat "$HOSTPATH/README.txt"
```

You just read project data **from the node**, bypassing every Kubernetes control.

!!! note
    If `docker` says *permission denied*, open a new terminal: the bootstrap added you to the
    `docker` group, which only takes effect in new shells.

**Discuss**: what does this mean for who may have node or hypervisor access in a TRE? Which
controls would you add? (Encryption at rest with keys outside the node, restricted break-glass
access, audit of node logins, confidential computing...)

## 5. Storage controls

```bash
kubectl -n project-alpha describe resourcequota project-quota | grep -E "storage|persistentvolumeclaims"
kubectl -n project-alpha describe limitrange project-limits
```

Try to use the wrong class:

```bash
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: sneaky, namespace: project-alpha}
spec:
  storageClassName: local-path
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 1Gi}}
YAML
```

```text
Error from server (Forbidden): error when creating "STDIN": persistentvolumeclaims "sneaky" is
forbidden: exceeded quota: project-quota, requested: local-path.storageclass.storage.k8s.io/persistentvolumeclaims=1,
used: local-path.storageclass.storage.k8s.io/persistentvolumeclaims=0, limited: local-path.storageclass.storage.k8s.io/persistentvolumeclaims=0
```

And an oversized claim of the right class:

```bash
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: huge, namespace: project-alpha}
spec:
  storageClassName: tre-project-shared
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 50Gi}}
YAML
```

This one is rejected by the LimitRange (at most 5Gi per claim), and would also exceed the quota.

## 6. Persistence

Stop researcher1's server, start it again and check `~/notes.txt`. The pod was new; the
volume was not.

## Check your understanding

1. If project alpha were removed from Git, what would happen to `home-researcher1`? And to the
   data in `project-shared`? (Look at the reclaim policies.)
2. Why is `volumeBindingMode: WaitForFirstConsumer` a good default?
3. What should happen to project data at the **end** of a project in a real TRE, and who decides?
