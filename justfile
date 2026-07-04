# Run everything CI runs, locally.
default: fmt-check clippy test doc audit

fmt:
    cargo fmt --all

fmt-check:
    cargo fmt --all -- --check

clippy:
    cargo clippy --workspace --all-targets -- -D warnings

test:
    cargo nextest run --workspace

doc:
    RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --document-private-items

audit:
    cargo deny check
