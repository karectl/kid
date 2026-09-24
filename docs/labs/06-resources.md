# Lab 6: CPU and memory

**Objectives**: see requests and limits applied to workspaces, feel CPU throttling and the OOM
killer, and hit LimitRange and ResourceQuota on purpose.

## 1. What did the workspace get?

```bash
kubectl -n project-alpha get pod jupyter-researcher1 \
  -o jsonpath='{.spec.containers[0].resources}{"\n"}'
kubectl -n project-alpha describe limitrange project-limits
kubectl -n project-alpha describe resourcequota project-quota
```

Where do `0.5` CPU and `1Gi` memory come from? Follow the trail:

`gitops/apps/values.yaml` (`sizes: [small]`) → `gitops/projects/chart/values.yaml`
(`sizeCatalogue.small`) → namespace annotation `k8tre.io/sizes` → `tre_config.py` → the pod.

!!! info "Units"
    KubeSpawner reads `1G` as 1 GiB (1024³ bytes), so pods show `1Gi`. CPU `0.5` is `500m`
    (millicores).

## 2. CPU: throttled, not killed

As researcher1, in a notebook:

```python
import multiprocessing, os

def burn():
    while True:
        pass

procs = [multiprocessing.Process(target=burn, daemon=True) for _ in range(4)]
for p in procs:
    p.start()
print("burning on", len(procs), "processes; os.cpu_count() says", os.cpu_count())
```

In the dev container, after about 30 seconds:

```bash
kubectl top pod -n project-alpha
```

CPU sits at about **500m** however many processes you start: the container is throttled to its
limit. `os.cpu_count()` still reports every core of the node, which confuses many data-science
libraries into starting too many threads. (Discuss: how would you tell researchers?)

Stop the burners with **Kernel → Restart Kernel**.

## 3. Memory: over the limit means killed

```python
chunks = []
for i in range(40):
    chunks.append(bytearray(100 * 1024 * 1024))   # 100 MiB at a time
    print(f"{(i + 1) * 100} MiB allocated", flush=True)
```

Somewhere below 1000 MiB the kernel dies (**"The kernel appears to have died. It will restart
automatically."**). The Linux OOM killer, enforcing the container's memory limit, killed the biggest
process in the container: the Python kernel. The Jupyter server survived, so the pod keeps running:

```bash
kubectl -n project-alpha get pod jupyter-researcher1   # RESTARTS is still 0
```

If the server process itself had been killed, the container would restart and `RESTARTS` would go
up, with `Last State: Terminated, Reason: OOMKilled` in `kubectl describe`.

## 4. The LimitRange ceiling

No container can ask for more than the project LimitRange's `max`:

```bash
kubectl -n project-alpha run toobig --restart=Never \
  --image=quay.io/jupyter/minimal-notebook:2026-08-10 --labels=k8tre.io/project=alpha \
  --overrides='{"spec":{"containers":[{"name":"toobig","image":"quay.io/jupyter/minimal-notebook:2026-08-10","command":["sleep","3600"],"resources":{"limits":{"cpu":"4","memory":"8Gi"}}}]}}'
```

```text
Error from server (Forbidden): pods "toobig" is forbidden: [maximum cpu usage per Container is 1,
but limit is 4, maximum memory usage per Container is 2Gi, but limit is 8Gi]
```

## 5. The project quota

Project **beta** has a quota of `4Gi` of memory limits in total. First **stop any beta
workspaces** (researcher2, researcher3). Then fill the quota with two 2Gi "sleeper" pods:

```bash
for i in 1 2; do
  kubectl -n project-beta run hog$i --restart=Never \
    --image=quay.io/jupyter/minimal-notebook:2026-08-10 --labels=k8tre.io/project=beta \
    --overrides='{"spec":{"containers":[{"name":"hog","image":"quay.io/jupyter/minimal-notebook:2026-08-10","command":["sleep","3600"],"resources":{"requests":{"cpu":"50m","memory":"64Mi"},"limits":{"cpu":"500m","memory":"2Gi"}}}]}}'
done
kubectl -n project-beta describe resourcequota project-quota
```

Notice two things:

* Pod Security prints **warnings** (`would violate PodSecurity "restricted:latest"`). The namespace
  *enforces* `baseline` but only *warns* about `restricted`: a gentle way to roll out stricter rules.
* `limits.memory` used is now `4Gi` of `4Gi`.

Now log in as **researcher2** and start a workspace in beta. It fails with something like:

```text
Spawn failed: ... pods "jupyter-researcher2" is forbidden: exceeded quota: project-quota,
requested: limits.memory=1Gi, used: limits.memory=4Gi, limited: limits.memory=4Gi
```

The quota protects everyone else on the cluster from one project's appetite. Researchers see it
as a failed launch, so a real TRE needs a clear message and a process for asking for more.

Clean up:

```bash
kubectl -n project-beta delete pod hog1 hog2
```

## Check your understanding

1. What is the difference between a **request** and a **limit**? Which one does the scheduler use?
2. Why cap memory hard but only throttle CPU?
3. The quota counts **limits**, not actual usage. What are the pros and cons for a TRE?
4. How would you change project beta's quota properly? (Hint: lab 7.)
