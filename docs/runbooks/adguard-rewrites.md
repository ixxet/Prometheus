# AdGuard Rewrites Runbook

Last updated: 2026-03-26 (America/Toronto)

## Purpose

This runbook captures the test-only naming layer currently configured in
AdGuard Home before router DNS cutover.

## Current stance

- AdGuard is not the sole DNS authority for the network
- router cutover is intentionally deferred
- the current goal is direct-query validation against `192.168.2.200`

## Configured rewrites

- `k8s.home.arpa -> 192.168.2.46`
- `adguard.home.arpa -> 192.168.2.200`
- `openwebui.home.arpa -> 192.168.2.201`
- `vllm.home.arpa -> 192.168.2.205`

## Upstream resolver choice

The initial Quad9 DNS-over-HTTPS upstream was noisy and unreliable on this
network. The current test configuration uses plain upstream resolvers:

- `9.9.9.9`
- `149.112.112.112`
- `1.1.1.1`
- `1.0.0.1`

## Validation

```bash
for name in k8s.home.arpa adguard.home.arpa openwebui.home.arpa vllm.home.arpa; do
  echo \"== $name ==\"
  dig +short @192.168.2.200 $name
  echo
done
```

Expected:

- `k8s.home.arpa -> 192.168.2.46`
- `adguard.home.arpa -> 192.168.2.200`
- `openwebui.home.arpa -> 192.168.2.201`
- `vllm.home.arpa -> 192.168.2.205`

Public resolution should also work:

```bash
dig +short @192.168.2.200 github.com
```

## What this does not mean yet

- clients are not using AdGuard by default
- router DNS has not been changed
- remote `home.arpa` resolution through Tailscale split DNS is not enabled yet
