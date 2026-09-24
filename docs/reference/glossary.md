# Glossary

Admission controller
:   Code in the API server path that can modify or reject objects before they are stored
    (LimitRanger, Pod Security, Kyverno).

Airlock
:   The controlled, reviewed process for moving data into or out of a TRE. Not implemented in KID.

Argo CD
:   GitOps controller that syncs the cluster to a Git repository.

CNI
:   Container Network Interface: the plugin that gives pods network connectivity (Cilium).

CRD
:   CustomResourceDefinition: extends the Kubernetes API with new object kinds.

eBPF
:   Linux kernel technology for running sandboxed programs in the kernel; Cilium uses it for
    networking and policy.

FQDN policy
:   A network rule written with DNS names instead of IP addresses (`toFQDNs`).

GitOps
:   Operating a system by changing declarative configuration in Git and letting automation apply it.

Hubble
:   Cilium's network observability layer (flow logs, CLI, UI).

K8TRE
:   A specification and reference implementation of a TRE on Kubernetes, from the UK TRE
    community. <https://docs.k8tre.org>

KubeSpawner
:   The JupyterHub spawner that runs each user's server as a Kubernetes pod.

LimitRange
:   Namespace object setting default and maximum resources per container or PVC.

Namespace
:   A partition of a Kubernetes cluster; in KID and K8TRE, one per research project.

OIDC
:   OpenID Connect: the login protocol between JupyterHub and Keycloak.

OOM kill
:   The kernel terminating a process that exceeded its memory limit.

Pod Security Admission (PSA)
:   Built-in admission controller enforcing the `privileged`, `baseline` or `restricted` profiles
    per namespace.

PVC / PV
:   PersistentVolumeClaim (a request for storage) and PersistentVolume (the storage itself).

RBAC
:   Role-Based Access Control: Roles/ClusterRoles bound to users or ServiceAccounts.

ResourceQuota
:   Namespace-wide totals for CPU, memory, storage, object counts.

SATRE
:   Standard Architecture for Trusted Research Environments.

Security identity (Cilium)
:   Numeric identity derived from a pod's labels; policies match identities, not IPs.

StorageClass
:   Describes a type of storage and how volumes of that type are provisioned.

TRE / SDE
:   Trusted Research Environment / Secure Data Environment.
