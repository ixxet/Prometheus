# Storage Safety Gate

The Kubernetes part of storage is authored here and intentionally staged behind
`suspend: true` in `clusters/talos-tower/infrastructure.yaml`.

Important distinction:

- `local-path-provisioner` is Kubernetes state and can be reconciled by Flux.
- `UserVolumeConfig` is Talos machine config, not a Kubernetes resource.
- The Talos volume documents live under `talos/` and must be applied with
  Talos tooling, not Flux.

Reason: the `UserVolumeConfig` resources target non-system disks. Applying
them without confirming that the selected disks are safe to repartition can
wipe data.

Current intended targets:
- `local-path-provisioner`: 500 GB SATA SSD (`WDC WDS500G2B0A`, WWID `naa.5001b448b1e0d6af`)
- `fast-ai`: 2 TB NVMe (`Samsung SSD 970 EVO Plus 2TB`, serial `S6S2NS0TC17843N`)
- `media-bulk`: 1 TB HDD (`ST1000DM003-1CH162`, WWID `naa.5000c5006630f225`)

Do not unsuspend `infra-storage` until each disk has been manually confirmed as
safe for Talos-managed storage and the matching Talos `UserVolumeConfig`
documents under `talos/` have been intentionally applied.
