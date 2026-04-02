# Growing Pains

Last updated: 2026-03-31 (America/Toronto)

## Why this file exists

This repo is meant to show real platform work, not just the final polished
shape. The failures here matter because they explain why the current design
looks the way it does.

## Current lessons learned

### 1. `vLLM_PORT` was broken by Kubernetes service-link env injection

What happened:

- Kubernetes created legacy service environment variables for the `vllm`
  `Service`
- one of those variables was `VLLM_PORT=tcp://10.x.x.x:8000`
- `vLLM` also reads `VLLM_PORT`, but expects an integer port value

Effect:

- `vLLM` crashed immediately during startup

Fix:

- disabled Kubernetes service-link env injection for the `vllm` pod with
  `enableServiceLinks: false`

Lesson:

- old Kubernetes service env injection is still capable of colliding with
  application-specific environment variables
- modern DNS-based service discovery is safer and cleaner here

### 2. Single-GPU rollout behavior caused a deadlock

What happened:

- the old broken `vllm` pod still held the only GPU
- the new fixed `vllm` pod could not schedule because the node has one RTX 3090

Effect:

- rollout stalled even though the manifest fix itself was correct

Fix:

- changed the deployment strategy to `Recreate`
- explicitly recycled the deployment so the old pod terminated before the new
  one requested the GPU

Lesson:

- single-GPU workloads are not normal rolling-update workloads
- rollout strategy must match the hardware reality

### 3. `vLLM` readiness was lying

What happened:

- Kubernetes considered the pod ready as soon as the container process stayed up
- but `vLLM` was still downloading and loading model weights

Effect:

- the pod looked healthy before the API was actually serving

Fix:

- added a readiness probe against `/v1/models`

Lesson:

- for inference systems, process-alive is not the same thing as service-ready

### 4. Slow internet changed the failure mode from image pull to model load

What happened:

- container images eventually pulled successfully
- model weights from Hugging Face then became the real bottleneck
- the accelerated Hugging Face transfer path timed out repeatedly on the current
  WAN link

Effect:

- `vLLM` moved from image delay to repeated model-download failure

Fix:

- disabled accelerated transfer/Xet path
- accepted slower but simpler downloads
- added better runtime visibility in docs and runbooks

Lesson:

- image-pull success does not mean AI stack success
- model distribution strategy matters as much as container delivery

### 5. `vLLM` fit on the 3090, but the default context window did not

What happened:

- the Mistral 7B weights finished downloading into the cache PVC
- `vLLM` then loaded the model successfully on the RTX 3090
- startup still crashed because the default model max sequence length was
  `32768`, while the available KV cache on the current `gpu_memory_utilization`
  setting could only hold about `25248` tokens

Effect:

- the pod restart loop looked like a download problem at first glance
- the real failure was engine initialization after the model was already on disk

Fix:

- capped `vLLM` with `--max-model-len 24576`
- kept the more conservative GPU memory setting instead of pushing the card
  harder immediately

Lesson:

- model download completion and model startup are separate checkpoints
- VRAM budgeting has to account for both weights and KV cache, not just one or
  the other

### 6. Flux health and live-state recovery can drift briefly

What happened:

- repo fixes were committed correctly
- the cluster sometimes remained on an older applied revision while health checks
  and dependency state caught up

Effect:

- the repo and the runtime could disagree for a short time during recovery

Fix:

- reconciled the affected layer explicitly
- in one case, applied the exact repo-rendered `vllm` manifests directly to
  converge the live deployment with the committed state

Lesson:

- GitOps is the source of truth, but operational recovery still requires reading
  the live object state carefully

### 7. Talos storage discipline forced the right decision

What happened:

- the easy-looking non-system disks were already in use elsewhere
- the cluster could have claimed them, but that would have been destructive

Effect:

- storage planning had to pause

Fix:

- kept first-wave persistent state on the Talos SSD only
- moved to a directory-backed `UserVolumeConfig` for local-path

Lesson:

- "available to Linux" is not the same thing as "safe to take"

### 8. AdGuard warned about the wrong address during first-run setup

What happened:

- AdGuard's setup wizard surfaced the pod IP such as `10.244.x.x`
- the live entrypoint users actually care about is the fixed `LoadBalancer` IP
  `192.168.2.200`

Effect:

- the static-IP warning looked more alarming than it really was
- it was easy to confuse pod networking with the stable service address

Fix:

- completed setup with the standard ports on all interfaces
- treated the Cilium `LoadBalancer` IP as the stable operator-facing address
- updated docs so the runbook points at `192.168.2.200`, not the pod IP

Lesson:

- Kubernetes apps often describe their pod view of the world, not the stable
  service address operators should use

### 9. Tailscale route approval was invisible until the route was truly advertised

What happened:

- the Tailscale admin UI showed MIMIR as connected
- the subnet route approval controls were missing
- the NUC had not actually advertised `192.168.2.0/24` yet

Effect:

- the route looked like a control-plane problem
- the real issue was local node configuration on the subnet router

Fix:

- enabled forwarding on the Debian NUC
- ran `tailscale up --advertise-routes=192.168.2.0/24`
- approved the route only after Tailscale reported it correctly

Lesson:

- Tailscale only exposes the approval controls after the subnet router is truly
  advertising the route

### 10. Postgres credentials were safer as components than as a naive URI

What happened:

- the Postgres password included a `/`
- embedding it directly in a `DATABASE_URI` made the first LangGraph runtime
  startup resolve the wrong host

Effect:

- the app looked like it had a networking problem
- the real problem was URI encoding of the password inside the connection string

Fix:

- switched the runtime to accept `DATABASE_USER`, `DATABASE_PASSWORD`,
  `DATABASE_HOST`, `DATABASE_PORT`, and `DATABASE_NAME`
- build the URI inside the app with proper password escaping
- reused the existing `postgres-auth` secret instead of inventing a second
  fragile secret format

Lesson:

- explicit secret fields are often safer than stuffing credentials into one
  opaque URI string

### 11. Local git access did not imply local container publish access

What happened:

- the local GitHub CLI token could push commits to the repo
- the same token did not have the package scopes needed to push to `ghcr.io`

Effect:

- local Docker build succeeded
- local image publication failed at the final push step

Fix:

- moved container publication to GitHub Actions with explicit `packages: write`
  permissions
- kept the manifest on a deliberate dev image tag instead of pretending local
  package push was dependable

Lesson:

- git write access and container registry write access are separate permissions
- delivery automation belongs in CI once the image matters to the cluster

### 12. A healthy LangGraph pod was not enough; persistence had to survive a restart

What happened:

- LangGraph reached `1/1 Running`
- `/healthz` returned cleanly
- thread creation and approval/resume flow worked through the live service
- that still did not prove the checkpoint store was wired correctly

Effect:

- without a restart test, the milestone would have looked finished before the
  durability claim was actually earned

Fix:

- created a live smoke thread against the cluster service
- deleted the LangGraph pod
- waited for the replacement pod to come up
- fetched the same thread again and confirmed the run history and all four
  checkpoints were still present

Lesson:

- for orchestration systems, "works once" and "persists across restart" are two
  different milestones
- restart testing is part of the feature definition, not a nice-to-have

### 13. AdGuard's first upstream choice was too fancy for this network

What happened:

- AdGuard came up using Quad9 over DNS-over-HTTPS
- local rewrites were fine, but public lookups and filter updates kept failing
- logs showed repeated connection resets and IPv6 reachability errors during
  upstream resolution

Effect:

- AdGuard looked healthy from the UI, but it was a weak test resolver for real
  queries

Fix:

- switched AdGuard to plain upstream resolvers:
  - `9.9.9.9`
  - `149.112.112.112`
  - `1.1.1.1`
  - `1.0.0.1`
- added the first four `home.arpa` rewrites directly in the live runtime config
- restarted the pod and validated both local rewrite resolution and public DNS
  resolution with direct queries to `192.168.2.200`

Lesson:

- a DNS service can be up and still be a bad fit for the network path it sits on
- direct query validation matters more than trusting the admin UI alone

### 14. Mutable dev image tags were too weak for LangGraph rollout verification

What happened:

- GitHub Actions built the LangGraph image for commit `e97edbf`
- the deployment still referenced the mutable tag `v0.3.0-dev`
- restarting the deployment came back on the old runtime code even though the
  new image had already been published

Effect:

- the repo said the seam work existed
- the cluster still served the old health payload
- rollout confidence was false until the live container filesystem was checked

Fix:

- pinned the deployment to the immutable image tag
  `sha-e97edbfc189b5c0b2424be39b1e53abe678890c0`
- verified the live container really contained `post_run.py` and the new
  health payload fields

Lesson:

- mutable tags are weak evidence in GitOps
- if the runtime matters, pin an immutable image reference until image
  automation exists

### 15. Planned config values should not pretend a provider exists

What happened:

- the LangGraph ConfigMap still said `SEMANTIC_MEMORY_PROVIDER=mem0-planned`
- the new seam code only supported real provider names or `none`

Effect:

- the new pod crashed at startup
- the old pod stayed up, which masked the broken replacement for a moment

Fix:

- changed the live config to:
  - `SEMANTIC_MEMORY_PROVIDER=none`
  - `ARCHIVE_SINK=none`
- rerolled LangGraph and revalidated the live service

Lesson:

- planned values are not the same thing as disabled values
- feature staging needs explicit no-op configuration until the backing system is real

### 16. The obvious semantic-memory service split was not the cleanest fit

What happened:

- the first instinct for `v0.4.0` was to hang LangGraph off a separate Mem0 API
  service immediately
- the upstream Mem0 options split into two awkward shapes for this stack:
  - the plain REST server assumes a different default backend shape
  - the OpenMemory API is a larger app surface than Prometheus needs for first
    semantic-memory integration

Effect:

- a seemingly clean "just call another service" plan would have added more app
  surface area than value
- the real boundary needed to stay around LangGraph as the orchestrator, not
  around a second agent-adjacent API

Fix:

- kept the semantic-memory seam inside LangGraph
- implemented the real Mem0-backed provider in-process
- staged `Qdrant + TEI` as support services behind a suspended GitOps layer

Lesson:

- a cleaner architecture is not always the one with the most services
- when one service already owns execution state, adding the memory boundary
  inside that service can be the more honest design

### 17. Immutable pinning was right, but the first rollout still had a real image-pull cost

What happened:

- the new Mem0-capable LangGraph image was built and published correctly
- the deployment was pinned to the immutable SHA tag and Flux applied the new spec
- the old LangGraph pod kept serving while the replacement pod sat in
  `ContainerCreating`
- the Talos node still had to pull about `2.98 GB` from `ghcr.io`, which took
  about `15m37s`

Effect:

- the pin looked "done" in Git before the runtime actually moved
- rollout verification had to wait on node-side image delivery, not just GitOps
  convergence

Fix:

- kept the immutable image pin
- waited for the new pod to finish pulling and become ready before declaring the
  rollout complete
- rechecked `/healthz` after the replacement was live

Lesson:

- immutable pinning fixes traceability, not download time
- on this link, first-pull cost is part of rollout planning even when the
  control-plane change itself is trivial

### 18. ConfigMap-driven runtime changes did not restart LangGraph

What happened:

- `SEMANTIC_MEMORY_PROVIDER` was changed from `none` to `mem0` in the LangGraph
  ConfigMap
- the deployment consumed that ConfigMap through `envFrom`
- the existing LangGraph pod kept running unchanged

Effect:

- the repo said semantic memory was enabled
- the live pod still reported `semantic_memory_provider: none`

Fix:

- added an explicit pod-template revision annotation to the LangGraph
  deployment
- treated each config-driven behavior change as a rollout event that must be
  visible in Git history

Lesson:

- `envFrom` config changes are not rollout events by themselves
- if runtime behavior depends on ConfigMap values, the pod replacement path must
  be explicit

### 19. Flux got pinned behind a failing intermediate revision

What happened:

- the first `mem0` flip crashed LangGraph because the embedder path still wanted
  `OPENAI_API_KEY` to exist in the environment
- the fix for that was committed in Git
- Flux was still stuck reconciling the older failing revision

Effect:

- newer repo fixes existed
- the live cluster remained trapped on the older bad state until that
  reconciliation cleared

Fix:

- added the explicit `OPENAI_API_KEY: local-not-required` config
- converged the live ConfigMap and Deployment to the already-committed repo
  state so the rollout could recover

Lesson:

- a later good revision does not help immediately if the controller is still
  blocked by an older failing one
- sometimes the fastest honest recovery is applying the repo-authored fix live
  so GitOps can catch back up

### 20. Mem0's Hugging Face embedder path still wanted an API key for local TEI

What happened:

- TEI was running locally and healthy
- Mem0's Hugging Face embedder wrapper still constructed an OpenAI client for
  the TEI-compatible base URL
- that client refused to start without `OPENAI_API_KEY` in the environment

Effect:

- LangGraph crashed during application startup before the first semantic-memory
  run could execute

Fix:

- set `OPENAI_API_KEY=local-not-required` explicitly in the LangGraph ConfigMap
- rerolled LangGraph after the config change

Lesson:

- "local" does not always mean "no API key path exists" in wrapper libraries
- explicit environment is safer than relying on code-level defaults when nested
  dependencies create their own clients

### 21. The off-tower archive sink stalled twice before it actually mounted

What happened:

- MIMIR had NFS installed and exported, but UFW still denied the traffic
- the first direct NFS mount attempt from the cluster hung without a useful pod
  event because the client could not reach the server ports cleanly
- after opening the network path, the first NFSv4 export layout was still wrong
  for the client path and the mount failed with `No such file or directory`

Effect:

- LangGraph could be configured for a filesystem archive sink before the actual
  off-tower path was trustworthy
- that would have turned `v0.4.0` into a paper milestone instead of a real one

Fix:

- kept the vault content off-repo and used MIMIR as the external sink host
- enabled `nfs-kernel-server` on MIMIR
- allowed LAN access to TCP `2049` through UFW instead of opening the whole box
- switched the export layout to an NFSv4 pseudo-root at `/srv/obsidian`
- mounted the cluster PV against `/prometheus-vault` with `nfsvers=4.1`
- proved the path with a write test before flipping LangGraph itself

Lesson:

- off-cluster state needs the same rigor as in-cluster state
- prove the storage path first, then change the runtime
- if the cluster only says `ContainerCreating`, go verify the network and mount
  semantics directly instead of guessing at the app layer

### 22. Tailscale DNS management masked the first "real client" AdGuard test

What happened:

- MIMIR was the right real client for validating `home.arpa`
- but its resolver was still managed by Tailscale with `CorpDNS=true`
- the first attempt to point MIMIR at AdGuard looked wrong because Tailscale
  immediately reasserted the stub resolver in `/etc/resolv.conf`

Effect:

- name resolution worked, but the resolver path was ambiguous
- that was not good enough for a clean `v0.5.0` acceptance claim

Fix:

- temporarily disabled Tailscale DNS acceptance on MIMIR
- pointed `/etc/resolv.conf` directly at `192.168.2.200`
- ran the `home.arpa` resolution and HTTP checks
- restored both the original resolver file and Tailscale DNS management after
  the test

Lesson:

- "real client validation" needs to be explicit about who owns the resolver
- Tailscale's DNS stub is useful operationally, but it can blur direct DNS
  tests if you do not account for it

### 23. A "real workflow" had to be narrower than the platform ambition

What happened:

- by `v0.4.0`, the stack already had:
  - LangGraph
  - Postgres
  - Mem0
  - off-tower archive export
- that still did not mean there was a credible first workflow
- the easy mistake would have been to describe a broad future agent instead of
  proving a narrow live path

Effect:

- the platform would have looked more complete on paper than it really was
- `v0.5.0` needed a workflow with an honest boundary and a repeatable runbook

Fix:

- defined the first real workflow as an approval-gated operator brief
- kept it read-only and human-supervised
- validated the full live path:
  - approval interrupt
  - Postgres-backed run state
  - `vLLM` response
  - Mem0-backed recall in a later thread
  - Markdown export to MIMIR

Lesson:

- the first credible workflow is usually smaller than the platform vision
- a narrow live workflow is better evidence than a broad future promise

### 24. Dual-boot convenience changes the operations bar

What happened:

- the tower is still expected to boot Windows sometimes
- that means the single-node Talos cluster is not a continuously available host
- manual post-return checks would become repetitive and easy to skip

Effect:

- safe shutdown and clean return had to become part of the documented operator
  path
- future observability work cannot pretend the node will be up 24/7 yet

Fix:

- documented the Windows/Talos dual-boot runbook
- added a post-return verification script that checks:
  - Talos health
  - Kubernetes and Flux
  - core pods
  - LAN endpoints
  - LangGraph health
- validated that script once against the live cluster

Lesson:

- if a platform sometimes becomes a workstation, operator recovery has to be
  scripted
- observability is still worth adding, but expected gaps must be treated as
  normal until the hardware role stabilizes

### 25. Observability health checks can stall behind a broken support target

What happened:

- the first observability rollout added `postgres-exporter` under the same
  Flux kustomization as the Prometheus/Grafana stack
- the exporter DSN secret used a raw password containing `/`
- that broke the exporter, which then held `infra-observability` in health-check
  progress
- a later repo fix existed, but Flux was still pinned behind the failing earlier
  revision

Effect:

- the base observability pods were healthy, but the kustomization stayed
  mid-reconcile
- repo truth and the live secret diverged until the broken target was cleared

Fix:

- percent-encoded the Postgres password in the exporter DSN
- applied the already-committed fixed secret directly to the cluster to unstick
  the health gate
- restarted only `postgres-exporter`

Lesson:

- support exporters are part of the health contract once they live in the same
  Flux slice
- a small secret bug can stall an otherwise healthy platform expansion

### 26. Repo-side automation and host-side automation are different completion points

What happened:

- the return-check script was refactored to be host-neutral
- the MIMIR systemd service, timer, and env template were committed in-repo
- the remote link to MIMIR degraded badly enough that the actual host install
  could not be trusted in the same session

Effect:

- the repo now contains the correct automation assets
- but the NUC is not yet the active source of automatic post-return checks

Fix:

- committed the automation assets separately from the script refactor
- kept the repo truthful: assets done, host install still pending

Lesson:

- external automation needs both repo truth and reachable host execution to be
  considered complete
- do not mark the operator path done just because the files exist in Git

### 27. Helper hosts do not always behave like the primary operator machine

What happened:

- the first MIMIR install attempt copied the Mac `talosctl` binary by mistake
- the second attempt put a Linux `talosctl` binary on MIMIR, but the helper
  host still rejected it with `Exec format error`
- that left the new systemd service unable to complete even though the repo
  assets and the rest of the host install were correct

Effect:

- the MIMIR service was installed but not yet trustworthy
- the timer could not be treated as real until the verification path had a
  working Talos-side check

Fix:

- changed the return-check script so it prefers `talosctl health` when it
  works, but falls back to a direct TCP probe of the Talos API on `:50000`
  when the helper host cannot execute `talosctl`
- reapplied the script and env file on MIMIR
- reran the service successfully and then enabled the timer

Lesson:

- helper-host automation should degrade gracefully when one binary path is
  unavailable
- for this operator check, proving Talos API reachability is better than having
  the whole timer path fail on a helper-host edge case

### 28. Grafana can fail on restart even when the PVC is healthy

What happened:

- after a Talos reboot, the post-return script caught Grafana in
  `Init:CrashLoopBackOff`
- the failing init container was `init-chown-data`
- the Grafana PVC itself was healthy and still contained the expected data
- the actual failure was `chown: /var/lib/grafana/png: Permission denied`
  for the restart-created `png`, `csv`, and `pdf` directories

Effect:

- the post-return verification could not pass cleanly
- Grafana stayed down even though the rest of the observability stack was fine

Fix:

- disabled `grafana.initChownData` in the HelmRelease
- reconciled `infra-observability`
- deleted the old Grafana pod once the new StatefulSet revision existed so it
  could be recreated without the failing init container

Lesson:

- a restart-safe stateful workload is not the same thing as a first-boot-safe
  workload
- if a chart keeps trying to re-own data it already owns, the right fix is
  often to remove that init step instead of fighting the volume permissions

### 29. The first summarizer image was built like a development workstation

What happened:

- the first deployable summarizer image installed the full project dependency set
- that pulled in dataset and evaluation libraries the API runtime does not use
- the resulting image was about `3.09 GB` compressed

Effect:

- the first cluster rollout was bottlenecked on image pull time, not Kubernetes
- the proof-of-concept app looked broken when it was really just impractical to deliver

Fix:

- split the API runtime dependencies into `requirements.runtime.txt` in the app repo
- added a `.dockerignore` so the build context stopped carrying development debris
- republished the image and rolled Prometheus to the slimmer commit-derived tag

Lesson:

- a proof-of-concept app still needs a production-shaped runtime image if it is going to live on the platform
- development and grading dependencies should not silently become cluster delivery cost

### 30. Single-replica app upgrades were still punished by rolling-update defaults

What happened:

- the summarizer deployment used the default rolling update strategy
- on a slow link, the cluster tried to pull the old `3.09 GB` image and the new slimmer image during the same replacement window

Effect:

- the rollout wasted bandwidth on an image we already wanted to replace
- the live deployment got healthier before Flux itself was happy about the new strategy

Fix:

- changed the summarizer deployment strategy to `Recreate`
- explicitly cleared the old `rollingUpdate` state so Flux could dry-run the committed shape successfully

Lesson:

- on single-replica workloads with slow delivery paths, the default rolling strategy can be actively wasteful
- API dry-run behavior against live objects can force one-time cleanup of old strategy fields

### 31. Auth-protected proxies need auth-safe probes

What happened:

- the summarizer proxy was meant to protect the app with basic auth
- its original readiness and liveness probes hit `/` over HTTP
- the proxy correctly answered `401 Unauthorized`, which Kubernetes treated as a failure

Effect:

- the auth layer looked unhealthy even though the proxy itself was serving exactly as configured

Fix:

- changed the proxy probes to `tcpSocket` checks on the listening port
- validated the authenticated quick-tunnel path separately from the probe path

Lesson:

- health probes must validate process and listener health, not user-facing authorization behavior
- protected surfaces often need different operator checks than open services

### 32. GitOps inventory can drift even when immutable pinning is still honest

Symptom:

- the ATHENA app manifest in `homelab-gitops/apps/athena/` still pinned
  `ghcr.io/ixxet/athena:0.1.0`
- the app inventory docs did not mention the ATHENA slice at all
- the service repos had already moved on to the Tracer 2-era `0.2.1` runtime

Cause:

- the initial ATHENA GitOps slice was activated early and then largely left
  alone while later tracer work stayed local-first
- immutable pinning prevented silent image drift, but it did not prevent stale
  repo intent or stale inventory docs

Fix:

- advanced the ATHENA manifest pin to the tested `0.2.1` immutable digest
- documented `apps/athena/` in the GitOps inventory as a narrow read-path
  deployment with the publish worker still intentionally disabled by config

Rule:

- immutable pinning proves what image is selected, not whether the selected
  image still matches the platform milestone truth
- if an app remains in the GitOps repo, its inventory docs and pinned checkpoint
  must be reviewed during hardening even when live rollout verification is still
  deferred

### 33. Application secrets should carry fully encoded connection strings

Symptom:

- the first live APOLLO rollout failed even though Postgres itself was healthy
- the APOLLO pod exited with `cannot parse postgres://... invalid port` during
  startup

Cause:

- the initial manifest tried to reconstruct `APOLLO_DATABASE_URL` from separate
  env parts
- the live Postgres password contains reserved URL characters, so string
  interpolation produced an invalid DSN

Fix:

- moved the live APOLLO database connection to a secret-backed full URL
- URL-encoded the password once in the secret material instead of rebuilding it
  inside the pod

Rule:

- connection strings with reserved characters should be stored as complete
  operator-owned secrets, not rebuilt from partial env pieces in manifests

### 34. Flux wait can keep a fixed app revision stuck behind stale dependency health

Symptom:

- a corrected `apps` revision existed in Git, but the live cluster stayed on
  the earlier broken APOLLO rollout for several minutes
- later fixes did not land immediately even after the source revision advanced

Cause:

- the top-level `apps` `Kustomization` uses `wait: true`
- while the earlier revision was still timing out on app health, Flux kept
  reconciling that stale failure state before it would apply the newer fixed
  revision

Fix:

- reconciled the dependency chain explicitly, then reconciled `apps` again
  against the new source revision
- recorded the behavior in the GitOps runbook instead of treating it as an
  unexplained lag

Rule:

- when a waited app rollout fails, do not assume a newer Git commit is already
  live just because the source fetched it
- inspect the `Kustomization` status and dependency readiness before claiming a
  fix has landed

## Current open pain points

- AdGuard rewrites are in place, but router DNS cutover is still pending
- `home.arpa` names are proven only when querying AdGuard directly; clients are
  not using it by default yet
- remote access works now through MIMIR advertising `192.168.2.0/24` into
  Tailscale, but it remains an external dependency rather than an in-cluster feature
- the node is still on DHCP `.49`, not the planned reserved `.45`
- the runbooks are authored now, but they still need live rehearsal as new
  milestones land
- router DNS cutover is still the bigger operational boundary than the memory stack now
- recurring Windows sessions on the tower still mean planned downtime and
  expected observability gaps
- the quick tunnel is intentionally temporary and can change URL whenever the tunnel pod is replaced

## Why keep this visible

Because this is where the engineering judgment lives:

- what failed
- why it failed
- what assumption was wrong
- how the fix changed the design

That matters more than pretending the build was linear.

## Hurdles We've Cleared

These are the wins worth keeping visible because they show what the platform can
already do on modest, real-world home hardware.

- Installed Talos only to the intended `256 GB` SSD without touching the other
  in-use tower disks.
- Brought up a single-node Talos control plane on bare metal with Cilium,
  `LoadBalancer` IPs, and L2 announcements on a normal home LAN.
- Loaded NVIDIA support into Talos, exposed the RTX 3090 through the device
  plugin, and validated GPU scheduling on the live node.
- Kept first-wave persistent state on the Talos system SSD when every non-system
  disk had to remain off-limits.
- Recovered `vLLM` from multiple real startup issues: service-link env
  collisions, single-GPU rollout deadlock, slow-link model distribution, and
  KV-cache sizing on a 24 GB consumer GPU.
- Got `Open WebUI`, `vLLM`, and Postgres running together on the same cluster
  with the model served locally as an OpenAI-compatible API.
- Reached a stable `v0.2.1` checkpoint with AI serving, GitOps, and remote ops
  all working at the same time.
- Established remote operations safely through Tailscale by using MIMIR as a
  subnet router instead of modifying the Talos node itself.
- Reached a stable `v0.3.0` checkpoint with LangGraph running live, backed only
  by Postgres, and validated through approval/resume plus pod-restart persistence.
- Brought AdGuard past the "UI works but DNS path is weak" stage by switching to
  plain upstream resolvers and validating the first four `home.arpa` rewrites.
- Brought the first `v0.4.0` seam work live without changing runtime behavior by
  keeping semantic memory and archive export on explicit no-op providers.
- Turned the semantic-memory seam into a real Mem0-backed code path without
  flipping the live runtime over prematurely.
- Rolled the live LangGraph deployment forward to the Mem0-capable immutable
  image without changing runtime behavior, then verified that the service still
  reported `semantic_memory_provider: none`.
- Brought `Qdrant + TEI` up on the live cluster and validated them before
  changing LangGraph behavior.
- Turned live semantic memory on and validated a real cross-thread write and
  recall against the running cluster.
- Wired the first off-tower archive sink onto MIMIR, validated the NFSv4.1
  mount from Talos, and proved that a completed LangGraph run writes Markdown
  artifacts outside the cluster and outside the repo.
- Proved that a real client on MIMIR can resolve and reach the first-wave
  `home.arpa` names when pointed directly at AdGuard, without doing the full
  router DNS cutover yet.
- Rehearsed the first real agent workflow end to end: approval gate, Postgres
  execution state, Mem0 recall, and Markdown export to the MIMIR vault.
- Brought up a real observability stack with Prometheus, Grafana, metrics-server,
  DCGM exporter, Flux/Cilium/`vLLM`/Postgres scrape surfaces, and Git-provisioned
  dashboards on the live cluster.
- Turned the summarizer capstone app into a real platform proof-of-concept by
  keeping the app repo responsible for GHCR image publishing while Prometheus
  only owned the deployment, monitoring, and external exposure path.
- Cut the summarizer runtime image from roughly `3.09 GB` compressed to about
  `238 MB` compressed by separating runtime dependencies from grading and evaluation dependencies.
- Exposed the summarizer to external reviewers without exposing raw `vLLM` by
  putting a basic-auth proxy and a temporary Cloudflare quick tunnel in front of the app.

## Success Stories

- This cluster now serves a local model from owned hardware through `vLLM`,
  exposes it on the LAN with Cilium `LoadBalancer` IPs, and does it on an
  immutable Talos node rather than a hand-tuned snowflake server.
- The first-wave storage path stayed disciplined even when it was tempting to
  steal other disks. The platform moved forward without destructive shortcuts.
- Remote operations are working without punching public holes into Talos or the
  Kubernetes API. Tailscale plus MIMIR gave the project a practical operator path.
- The repo shows the learning curve instead of airbrushing it away. The failures
  around GPU rollout, model sizing, and service networking are now part of the
  platform knowledge, not repeated future mistakes.
- The first agent runtime now exists as a real in-cluster service, not a design
  document. LangGraph can create a thread, pause for approval, resume, and keep
  its execution history after the pod is replaced.
- The naming layer is now real enough to test. AdGuard answers the first-wave
  `home.arpa` names directly without taking over router DNS yet.
- The LangGraph runtime now exposes the next integration seam cleanly: semantic
  memory and archive hooks are live, visible in health checks, and still safe
  because they default to no-op providers.
- The semantic-memory stage now has a credible shape: LangGraph owns the seam,
  Mem0 owns durable facts, and `Qdrant + TEI` are staged as support services
  instead of being improvised later.
- The archive layer is now real instead of theoretical. Completed runs can
  leave the cluster as Markdown artifacts on MIMIR without turning Git into the
  vault itself.
- The first real workflow is now more than a smoke test. The platform can take
  an approval-gated operator request, persist it, recall durable facts in a new
  thread, and leave behind a human-readable artifact off-tower.
- The tower can now be treated honestly as both a cluster node and a temporary
  workstation. Shutdown and return checks are documented and scriptable instead
  of being left to memory.
- Observability is now real enough to be useful during that dual-boot reality.
  Grafana, Prometheus, and the provisioned dashboards make regressions visible
  without pretending the tower is a 24/7 server yet.
