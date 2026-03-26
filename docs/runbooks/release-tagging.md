# Release And Tagging Runbook

Last updated: 2026-03-26 (America/Toronto)

## Purpose

This file defines the project tagging standard so tags stay meaningful instead
of becoming random snapshots.

## Tagging rule

Tag only when the repo and the live platform agree on the milestone.

That means:

- docs reflect reality
- manifests reflect reality
- the live cluster has passed the intended acceptance gates
- known gaps are recorded explicitly

## Release cadence

- `v0.2.1` captured stable AI serving plus remote ops
- `v0.3.0` captures LangGraph live with Postgres-backed execution state
- `v0.4.0` should capture Mem0 plus Obsidian summary/export flow
- `v0.5.0` should capture AdGuard cutover and the first real workflow

## Before tagging

1. `git status` is clean.
2. README and `docs/growing-pains.md` reflect the current milestone.
3. Runtime checks and runbooks reflect the current milestone.
4. Acceptance criteria for that version have actually been verified.

## Annotation style

Use short, factual annotations:

- what changed
- why the checkpoint matters
- what was intentionally left for the next version
