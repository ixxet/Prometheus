# Tailscale Remote Access

Last updated: 2026-03-25 (America/Toronto)

## Goal

Reach the home Talos cluster remotely without exposing Talos API, Kubernetes
API, or application services directly to the public internet.

## Recommended path

Do **not** start by installing Tailscale directly on the Talos control-plane
node.

Recommended first step:

- keep the Talos node unchanged
- install Tailscale on an always-on home Linux box, preferably the Debian NUC
- make that box a **subnet router** for `192.168.2.0/24`

This gives remote access to:

- Talos API on `192.168.2.49:50000`
- Kubernetes API VIP on `192.168.2.46:6443`
- LAN `LoadBalancer` services such as:
  - `192.168.2.200` AdGuard Home
  - `192.168.2.201` Open WebUI
  - `192.168.2.205:8000` vLLM

## Why this is the safer choice

Installing Tailscale directly on Talos is possible, but it is not the lowest-risk
move on a single-node control plane.

Reasons:

- Talos system extensions are activated only during install or upgrade
- the official Talos extension catalog includes a `tailscale` extension, but
  using it would require a maintenance change to the Talos node image path and
  a reboot/upgrade cycle
- the tower is currently the only control-plane node and the only GPU node

So the direct-Talos path is a **maintenance-window task**, not a "leaving the
house soon" task.

## What the NUC subnet-router approach changes

It does **not** change:

- Talos internal networking
- Cilium
- Kubernetes service exposure
- LAN IP assignments
- the current app manifests

It **does** add:

- a secure remote path into the home LAN through the tailnet

## Debian NUC subnet-router steps

On the Debian NUC:

Current observed state on `MIMIR`:

- Tailscale is already installed and connected
- no subnet routes are currently advertised
- changing advertised routes requires `sudo`

To finish the subnet-router setup:

1. Enable IP forwarding.
2. Persist the forwarding settings.
3. Advertise the LAN route.
4. Set an operator so future route changes do not require full root access.

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv6.conf.all.forwarding=1
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding=1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo tailscale up --advertise-routes=192.168.2.0/24
sudo tailscale set --operator=boi
```

This does two useful things:

- enables the subnet router immediately
- lets later `tailscale set ...` changes be made by `boi` without another root-only
  Tailscale preference write

If the Tailscale admin console asks for approval:

5. Approve the advertised route.
6. From the remote Mac, confirm the route is available.

The daemon also warned that UDP GRO forwarding on `eno1` is not optimal. That is
not a blocker for admin access. It is a performance tuning item, not a setup
stopper.

On macOS, subnet routes are accepted by default, so the Mac should pick up the
advertised route automatically once it is approved.

## What remote testing would look like

Once the subnet router is working, the same commands from the normal runbook
should work remotely from the Mac:

```bash
talosctl --talosconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig -n 192.168.2.49 health

kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get nodes -o wide

curl -I http://192.168.2.201/
curl http://192.168.2.205:8000/v1/models
```

## DNS and Tailscale

Right now, the reliable remote path is **IP-based**.

Why:

- router DNS is not yet cut over to AdGuard
- `home.arpa` names are not yet being resolved remotely through Tailscale

Later options:

- use Tailscale split DNS for `home.arpa`
- point that split DNS at AdGuard once AdGuard is stable and reachable over the
  subnet route

Until then, use the fixed LAN service IPs.

## Break-glass note

If a router-side DNS handoff goes badly, remote recovery should still use raw
IP access through MIMIR, not `home.arpa`:

- MIMIR Tailscale: `100.109.171.72`
- Talos API: `192.168.2.49:50000`
- Kubernetes VIP: `192.168.2.46:6443`
- AdGuard: `192.168.2.200`
- Open WebUI: `192.168.2.201`
- vLLM: `192.168.2.205:8000`

That is why DNS cutover does not remove the remote backdoor as long as MIMIR
and the Tailscale subnet route stay healthy.

## Direct Talos path later

If we later want the Talos node itself to be a Tailscale node, the shape is:

1. include the official `tailscale` Talos system extension in the installer image
2. upgrade the Talos node to that installer image
3. configure the Tailscale service intentionally
4. validate that Talos API, Kubernetes VIP, and LAN service routing still behave
   correctly

That path is valid, but it is not the right first remote-access move for this
single-node cluster.
