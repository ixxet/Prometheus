# Talos User Volumes

These files are not Kubernetes manifests.

They are Talos `UserVolumeConfig` documents and must be applied through the
Talos API after the target disks are manually confirmed to be safe.

Suggested workflow:

1. Re-run disk discovery on the live node.
2. Confirm the target model, serial, WWID, and intended use.
3. Apply the chosen `UserVolumeConfig` documents with Talos tooling.
4. Verify mount status on the node.
5. Only then unsuspend `infra-storage` in Flux.
