# Tailscale Remote Access

Last updated: 2026-04-13 (America/Toronto)

## Goal

Reach the home Talos cluster remotely without exposing Talos API, Kubernetes
API, or application services directly to the public internet.

## Recommended path

Do **not** start by installing Tailscale directly on the Talos control-plane
node.

Recommended first step:

- keep the Talos node unchanged
- install Tailscale on an always-on home Linux box, preferably the Debian NUC
- make that box a **subnet router** for the current home-base LAN

This gives remote access to:

- Talos API on the current node IP
- Kubernetes API on the current active endpoint
- LAN `LoadBalancer` services that still make sense on the current site

Current observed home-base LAN on 2026-04-13:

- `MIMIR`: `192.168.50.171`
- `Prometheus`: `192.168.50.197`
- current advertised MIMIR route: `192.168.50.0/24`

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
- `boi` is already the configured Tailscale operator
- the currently advertised route is `192.168.50.0/24`

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
sudo tailscale up --advertise-routes=<current-home-subnet>
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
talosctl --talosconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/talosconfig -n <current-node-ip> health

kubectl --kubeconfig /Users/zizo/Personal-Projects/Computers/Talos/tower-bootstrap/kubeconfig get nodes -o wide

curl -I http://<current-openwebui-ip>/
curl http://<current-vllm-ip>:8000/v1/models
```

## If the home-base subnet changes

When MIMIR and Prometheus move together and still share a LAN:

- keep using MIMIR as the tailnet subnet router
- update the advertised route to match the new LAN
- verify remote access again from the Mac

When Prometheus moves without MIMIR:

- MIMIR can no longer route to it
- treat that as a relocation event, not a normal remote-ops event
- use the relocation runbook until Prometheus returns to the MIMIR LAN

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
- current home-base LAN: `192.168.50.0/24`
- MIMIR LAN IP: `192.168.50.171`
- Prometheus node IP: `192.168.50.197`

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
