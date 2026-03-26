# Add Worker Runbook

Last updated: 2026-03-26 (America/Toronto)

## Purpose

This runbook describes the intended future path for adding another node without
improvising the cluster shape under pressure.

## Current stance

- MIMIR stays Debian first
- adding a worker is a later deliberate move
- HA control-plane work is explicitly later than the first worker decision

## Preconditions

- the single-node tower platform is stable
- observability exists or at least core health checks are reliable
- the role of the new node is clear:
  - CPU-side apps
  - storage helper
  - additional control-plane work later

## Preferred sequence

1. Decide whether the new node should stay external first.
2. If it joins Kubernetes, join it as a worker before considering control-plane duties.
3. Validate networking, routing, and service exposure.
4. Validate workload placement and taints explicitly.
5. Only revisit HA control-plane work after the worker role is proven worthwhile.

## Things not to do

- do not turn MIMIR into a Talos control-plane node opportunistically
- do not add a worker just because hardware exists without a placement plan
- do not assume mixed storage or GPU roles are free
