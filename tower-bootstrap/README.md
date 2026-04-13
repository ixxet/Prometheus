# Tower Bootstrap Artifacts

Last updated: 2026-04-08 (America/Toronto)

## Scope

This directory contains the files used to install and bootstrap the Talos tower.
It records what was actually applied, what was generated, and which artifacts are
sensitive. This is not a generic template directory; some values are tightly bound
to the current hardware.

This directory is now historical bootstrap context, not the live day-to-day
operator credential location. The current Talos admin artifacts used by the
runbooks live under `/Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/`.

## Current outcome

- Talos is installed on the confirmed `LITEONIT LCS-256L9S-11` internal SSD only.
- The tower is booted from that SSD.
- The cluster is healthy on a single control-plane node.
- API VIP `192.168.2.46` is active.
- The node currently holds DHCP address `192.168.2.49`.
- Cilium, `LoadBalancer` IPAM, L2 announcements, and NVIDIA GPU scheduling are all live.
- Flux now manages the live GitOps layer under `../homelab-gitops`; do not read this file as the current deployment-status ledger.
- Disposable bootstrap test workloads were removed after validation.

## File inventory

| File | What it accomplishes | Restrictions | What it does not do |
| --- | --- | --- | --- |
| `patch.yaml` | Supplies the install disk selector, installer image, NVIDIA kernel modules, kubePrism, VIP, Cilium-no-default-CNI choice, and single-node scheduling settings. | Hardware-specific. The `busPath` selector and NIC name fit this tower only. | It does not generate secrets, define app workloads, or create storage volumes. |
| `controlplane.yaml` | Generated Talos control-plane machine config targeting API endpoint `https://192.168.2.46:6443`. | Sensitive. Generated from `talosctl gen config`; do not commit publicly. | It does not include the local patch values until combined at apply time. |
| `worker.yaml` | Generated worker config for future non-control-plane nodes. | Generic template only; must be patched before use on a real node. | It does not safely join any specific future worker by itself. |
| `controlplane.patched.yaml` | Local inspection artifact showing the merged control-plane config after patching. | Review helper only. If `patch.yaml` changes, this file becomes stale unless regenerated. | It is not the authoritative source of truth used by Talos once the node is installed. |
| `talosconfig` | Talos admin credentials used by `talosctl`. | Secret. Machine-admin access. Keep off Git and backups must be protected. | It does not configure the cluster by itself; it only authenticates admin operations. |
| `kubeconfig` | Kubernetes admin config for `kubectl` access to the new cluster. | Secret. Cluster-admin access. Keep off Git. | It does not create or reconcile resources on its own. |
| `cilium-values.yaml` | Pinned Helm values used to render Cilium `1.18.0` with Talos-specific settings. | Assumes kubePrism on port `7445` and the Talos no-kube-proxy path. | It does not install anything until rendered and applied. |
| `cilium-1.18.0.yaml` | Rendered Cilium manifest snapshot that was actually applied to the cluster. | Regenerate if chart version or values change. Large rendered artifact, not hand-maintained. | It does not reflect later Helm changes automatically. |
| `cilium-lb-pool.yaml` | Creates the `LoadBalancer` IP pool `192.168.2.200-192.168.2.220`. | Safe only if that range is really unused on the LAN. | It does not create service DNS names or reserve router leases. |
| `cilium-l2-policy.yaml` | Tells Cilium to answer ARP for external and `LoadBalancer` IPs on `enp6s0`. | NIC-specific. If the physical NIC name changes, this must change too. | It does not expose any service until a `LoadBalancer` service exists. |
| `nvidia-runtimeclass.yaml` | Defines `RuntimeClass` `nvidia` so pods can select the NVIDIA container runtime. | Depends on the NVIDIA extensions and runtime existing on the node. | It does not advertise GPU capacity by itself. |
| `nvidia-device-plugin-0.17.0.yaml` | Pinned NVIDIA device plugin daemonset, modified to use `runtimeClassName: nvidia`. | Tag-pinned, not digest-pinned. Pulls from `nvcr.io`, which can be slower than public registries. | It does not install drivers or create `/dev/nvidia*`; Talos extensions already did that. |

## Sensitive files

Treat these as secrets and keep them out of Git:

- `controlplane.yaml`
- `worker.yaml`
- `talosconfig`
- `kubeconfig`
- `controlplane.patched.yaml`

`patch.yaml`, the Cilium files, and the NVIDIA manifest are operationally useful
but still environment-specific. They are safer to version than the generated
credentials, but they should still be reviewed before reuse.

## Problems already resolved

- Install safety: the first disk selector failed validation before any write happened.
- Boot path: BIOS preferred Windows until the Talos SSD boot entry was moved up.
- Secure Boot: Talos plus NVIDIA would not boot until Secure Boot was disabled.
- Node addressing: the node booted on `.49` because the `.45` reservation was not active.
- Network bootstrap: the node stayed `NotReady` until Cilium came up, which was expected.
- GPU scheduling: the device plugin image pull took time, but completed and exposed `nvidia.com/gpu=1`.

## Historical bootstrap gaps at handoff

- Convert the current DHCP state into the intended `.45` reservation.
- Add Talos `UserVolumeConfig` resources for the non-system disks.
- Flux bootstrapping against `homelab-gitops` was completed later and is now live.
- AdGuard Home and the first staged infrastructure layer were deployed later and are now live.

## Validation notes

- `talosctl health` passes.
- `kubectl get nodes` reports the node `Ready`.
- A disposable `LoadBalancer` service answered successfully on `192.168.2.220`.
- A disposable GPU pod ran `nvidia-smi` and reported the RTX 3090.
- The GPU test log ended with `ERROR: init 250 result=11` after `nvidia-smi` output, but the pod still reached `Succeeded`. Treat that as a teardown quirk unless it starts affecting real workloads.
