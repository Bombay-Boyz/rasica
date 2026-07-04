# RASICA

Phase 1 (Core Foundation) workspace, per `specifications/00A-Phase1-Core-Foundation-Implementation-Spec.md`.

## Crates

- `crates/rasica-common` — shared primitives, error/config/logging frameworks.
- `crates/rasica-core` — Mutability Tier traits, identity, deterministic fingerprinting.
- `tests/workspace_smoke` — cross-crate smoke tests.

## Local dev

Run everything CI runs:

```sh
just
```

Requires: `cargo-nextest`, `cargo-deny`, and `just` (`cargo install cargo-nextest cargo-deny just`).
