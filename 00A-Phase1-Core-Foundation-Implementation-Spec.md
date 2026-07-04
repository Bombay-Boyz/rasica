# RASICA Implementation Specification

## Document 00A — Phase 1: Core Foundation

**Version:** 1.0
**Status:** Draft — for implementation
**Conforms to:** RASICA Architecture Specification v2.1 ("the Architecture Spec")
**Position in documentation hierarchy:** Precedes Appendix E item *03 Core Object Model Specification*. This document is infrastructural and has no Appendix E item number of its own; it exists to make item 03 (and every later module specification) implementable on a common, already-tested foundation.

---

## Document Control

| Item | Value |
|---|---|
| Project | RASICA |
| Document | Phase 1 Implementation Specification — Core Foundation |
| Roadmap Source | Architecture Spec §15.4 ("Phase 1 — Core Foundation") |
| Depends On | Architecture Spec §4.1 (Determinism), §6.2/§6.2A (Mutability Tiers), §14 (Engineering Principles), Appendix D (Repository Structure), Appendix G (Canonical Trait Signatures), Appendix H (NFR Baseline) |
| Produces Crates | `rasica-common`, `rasica-core` |
| Produces Infrastructure | Cargo workspace, CI pipeline, lint/format/deny configuration, testing harness, documentation harness |
| Consumed By | Every subsequent phase specification (02 Dataset Engine onward) |
| Intended Audience | Implementers (human or AI) building the first commits of the RASICA repository |
| Deviation Policy | Any deviation from a signature or invariant in this document that also appears in the Architecture Spec (§4.1, §6.2A, Appendix G) is an architectural change and requires an ADR per §16.5/§14.18, not a local decision. Deviations confined to this document only (e.g. an internal helper's name) may be made freely provided intent is preserved. |

---

## 1. Purpose and Scope

### 1.1 Purpose

This document is the authoritative, implementable specification for **Phase 1 — Core Foundation**, the first entry in the RASICA development roadmap (Architecture Spec §15.4). It translates that phase's four-line deliverable list into:

- an exact repository and crate layout,
- concrete Rust types, traits, and module structures,
- the error, configuration, logging, and testing frameworks every later crate will depend on,
- a working CI pipeline and lint configuration,
- a verifiable, checkable exit-criteria list.

Nothing in this document introduces new architecture. Every design decision below is a direct implementation of a rule already stated in the Architecture Spec; each subsection cites the section it implements.

### 1.2 Scope

**In scope for Phase 1:**

- The Cargo workspace itself (`Cargo.toml`, lint configuration, CI).
- `rasica-common`: primitive types, identifiers, versioning, the error framework, the configuration framework, the logging/tracing framework.
- `rasica-core`: the Mutability Tier marker traits, the deterministic fingerprinting contract, and the minimal `Identifiable` / prelude vocabulary that every Core Architectural Object (Architecture Spec §6) will implement from Phase 2 onward.
- The testing framework (unit, property-based, and benchmark harnesses) as reusable workspace infrastructure, not yet applied to any domain logic (there is none yet).
- The documentation and build pipeline.

**Explicitly out of scope for Phase 1** (deferred to their own phase specifications):

- `Dataset`, `Row`, `Column`, `Schema` (Phase 2 — Dataset Engine, Architecture Spec §15.5).
- Any Core Architectural Object body other than the marker traits/vocabulary above (Architecture Spec §6.4 onward).
- Domain SDK, Rule Engine, Execution Engine, and everything downstream (Architecture Spec §15.6–§15.23).

Per Architecture Spec §15.1: *"No module shall begin implementation until all prerequisite milestones have been successfully completed."* Phase 1 has no prerequisites; it is the prerequisite for everything else. Implementers shall not begin Phase 2 work inside these crates.

### 1.3 Relationship to the Architecture Spec

| Phase 1 deliverable (§15.4) | Implemented in this document as |
|---|---|
| Cargo Workspace | §3 (Repository & Workspace Layout) |
| Common crate | §4 (`rasica-common`) |
| Core traits | §5 (`rasica-core`) |
| Primitive types | §4.3 |
| Configuration framework | §4.5 |
| Error framework | §4.4 |
| Logging framework | §4.6 |
| Testing framework | §6 |
| Build pipeline | §7 (CI) |

Exit criteria in §15.4 ("builds successfully," "CI pipeline operational," "documentation framework established," "coding standards enforced") are made concrete and checkable in §9 of this document.

---

## 2. Engineering Baseline for This Phase

The following rules from Architecture Spec §14 apply directly to the code in this document and to everything built on top of it. They are restated here, not to duplicate §14 as authority, but so the code below can be checked against them without cross-referencing:

- **§14.5 Rust Engineering Principles:** ownership over shared mutability; traits over tight coupling; explicit error handling; exhaustive matching; strong typing; zero-cost abstractions; unsafe only with documented justification. **Decision:** `rasica-common` and `rasica-core` set `#![forbid(unsafe_code)]`. Neither crate has any justified need for `unsafe` in Phase 1; if a later phase needs it in a different crate, that crate opts out of the forbid explicitly with a comment citing the justification, per §14.5.
- **§14.8 Public APIs:** stable, consistent, documented, deterministic. **Decision:** both crates set `#![warn(missing_docs)]` promoted to `deny` in CI (§7), so no public item ships undocumented (§14.11).
- **§14.9 Error Handling:** errors are architectural artefacts; structured; deterministic; preserve context; machine- and human-readable; panics represent programming defects, not expected conditions. Implemented in §4.4.
- **§14.10 Configuration:** external to analytical logic; never alters mathematical correctness. Implemented in §4.5. (Phase 1 has no analytical logic to protect yet, but the framework's shape is fixed now so later phases cannot smuggle correctness-relevant switches into config.)
- **§14.16 Versioning:** Semantic Versioning; Domain Modules and Core Engine versioned independently. Implemented via the `SemVer` and `EngineVersion` newtypes in §4.3, which give later phases (notably the Domain SDK, Appendix G) a single shared version vocabulary instead of each crate rolling its own.
- **§4.1 Determinism:** logical determinism is unconditional; numeric determinism is scoped to a declared precision profile via deterministic reduction. Phase 1 does no numeric computation, but it does establish the one primitive determinism depends on structurally: a **deterministic fingerprint** (§5.3), which Architecture Spec §6.2A requires for keying Tier-3 caches ("cached values are always keyed by a deterministic fingerprint of their inputs") and which later phases (Rule Engine stratification, Analysis Graph construction) will reuse rather than reinvent.
- **§6.2A Mutability Tiers:** every Core Architectural Object belongs to exactly one of three tiers (Immutable / Append-Only / Scoped-Mutable) for its entire lifetime. Phase 1 defines the three marker traits; it does not yet define any object that implements them (that begins at Phase 2's `Dataset`, Tier 1).

---

## 3. Repository & Workspace Layout

### 3.1 Directory Structure (Phase 1 slice)

This is the Phase 1 subset of the full repository structure defined in Architecture Spec Appendix D. Directories for crates not yet implemented are **not** created in Phase 1; they are added by the phase specification that first populates them, to keep the workspace buildable at every commit.

```text
rasica/
├── .github/
│   └── workflows/
│       └── ci.yml
├── architecture/
│   └── rasica-v2.md                # this repository's copy of the Architecture Spec
├── specifications/
│   └── 00A-Phase1-Core-Foundation-Implementation-Spec.md   # this document
├── crates/
│   ├── rasica-common/
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── error.rs
│   │       ├── id.rs
│   │       ├── version.rs
│   │       ├── config/
│   │       │   ├── mod.rs
│   │       │   ├── layers.rs
│   │       │   └── error.rs
│   │       └── logging.rs
│   └── rasica-core/
│       ├── Cargo.toml
│       └── src/
│           ├── lib.rs
│           ├── mutability.rs
│           ├── fingerprint.rs
│           ├── identity.rs
│           └── prelude.rs
├── tests/
│   └── workspace_smoke/
│       ├── Cargo.toml
│       └── tests/
│           └── smoke.rs
├── Cargo.toml                       # workspace root
├── rustfmt.toml
├── clippy.toml
├── deny.toml
├── nextest.toml
├── .rust-version
└── README.md
```

All other Appendix D directories (`domains/`, `datasets/`, `benchmarks/`, `docs/`, and the remaining `crates/rasica-*`) are created by the phase specification that first needs them and are out of scope here.

### 3.2 Workspace Root `Cargo.toml`

Workspace-level lints (Rust 2021 `[workspace.lints]`, stabilized in Cargo 1.74) are used so every member crate inherits the same lint policy from one place, rather than repeating `#![...]` attributes crate-by-crate and risking drift — a direct application of §14.4 (Architectural Governance: consistency enforced structurally, not by convention).

```toml
[workspace]
resolver = "2"
members = [
    "crates/rasica-common",
    "crates/rasica-core",
    "tests/workspace_smoke",
]

[workspace.package]
version = "0.1.0"
edition = "2021"
rust-version = "1.78"
authors = ["RASICA Architecture Team"]
license = "Apache-2.0"
repository = "https://github.com/rasica-project/rasica"
publish = false

[workspace.dependencies]
# --- error handling (§14.9) ---
thiserror = "1.0"

# --- deterministic fingerprinting (§6.2A, §4.1) ---
blake3 = "1.5"

# --- versioning (§14.16) ---
semver = "1.0"

# --- configuration (§14.10) ---
figment = { version = "0.10", features = ["toml", "env"] }
serde = { version = "1.0", features = ["derive"] }

# --- logging (§14.6 Rust Engineering Principles context) ---
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }

# --- identifiers ---
uuid = { version = "1.8", features = ["v4", "serde"] }

# --- testing (§14.13) ---
proptest = "1.4"
rstest = "0.19"

[workspace.lints.rust]
missing_docs = "warn"                 # promoted to deny in CI, see §7
unsafe_code = "forbid"
unused_must_use = "deny"
rust_2018_idioms = { level = "warn", priority = -1 }

[workspace.lints.clippy]
all = { level = "warn", priority = -1 }
pedantic = { level = "warn", priority = -1 }
# Exceptions to pedantic, justified individually rather than blanket-suppressed:
module_name_repetitions = "allow"     # e.g. `error::Error` re-exported as `Error` is idiomatic and intended
must_use_candidate = "allow"          # noisy on internal builder methods; revisited per-crate if needed
unwrap_used = "deny"                  # §14.9: panics must be deliberate, never an unexamined default
expect_used = "warn"                  # allowed only with a message proving the invariant, see §4.4 below
```

**Rationale for `unwrap_used = "deny"` / `expect_used = "warn"`:** Architecture Spec §14.9 states panics "shall represent unrecoverable programming defects rather than expected execution conditions." Denying `.unwrap()` outright and requiring `.expect("<invariant that makes this unreachable>")` for the narrow cases where a panic *is* the correct response to a genuine defect makes every remaining panic self-documenting at the call site.

### 3.3 `rustfmt.toml`

```toml
edition = "2021"
max_width = 100
use_small_heuristics = "Max"
imports_granularity = "Crate"
group_imports = "StdExternalCrate"
wrap_comments = true
comment_width = 100
format_code_in_doc_comments = true
```

### 3.4 `clippy.toml`

```toml
# Complexity thresholds kept at defaults deliberately; Phase 1 introduces no
# complex control flow. Revisit only with a documented justification (§14.7).
too-many-arguments-threshold = 6
type-complexity-threshold = 250
```

### 3.5 `deny.toml` (cargo-deny — supply chain per §14.7, §14.17)

```toml
[graph]
targets = []

[advisories]
db-path = "~/.cargo/advisory-db"
db-urls = ["https://github.com/rustsec/advisory-db"]
yanked = "deny"
ignore = []

[licenses]
allow = [
    "Apache-2.0",
    "MIT",
    "BSD-3-Clause",
    "Unicode-DFS-2016",
]
confidence-threshold = 0.8

[bans]
multiple-versions = "warn"
wildcards = "deny"
deny = [
    # No crate in the dependency tree may itself pull in unreviewed unsafe-heavy
    # FFI crates in Phase 1; extend this list as new dependencies are justified (§14.7).
]

[sources]
unknown-registry = "deny"
unknown-git = "deny"
```

### 3.6 `nextest.toml`

```toml
[profile.default]
retries = 0
slow-timeout = { period = "30s", terminate-after = 2 }
failure-output = "immediate-final"

[profile.ci]
retries = 2
fail-fast = false
```

### 3.7 `.rust-version`

```text
1.78.0
```

---

## 4. Crate: `rasica-common`

### 4.1 Responsibilities

`rasica-common` is the single dependency every other RASICA crate is permitted to depend on unconditionally (Architecture Spec §14.6, §14.7: explicit dependencies, no hidden coupling). It owns:

- primitive newtypes shared platform-wide (`Id<T>`, `SemVer`, `EngineVersion`, `Timestamp`),
- the error framework contract (`RasicaError`, `ErrorCode`, `ErrorSeverity`),
- the configuration framework (`RasicaConfig`, layered loading),
- the logging/tracing initialisation.

`rasica-common` shall contain **no** analytical, statistical, or domain logic. It is infrastructure only. This boundary is what keeps §8's dependency rules (every crate may depend on `rasica-common`; `rasica-common` depends on nothing internal) acyclic from the first commit.

### 4.2 `Cargo.toml`

```toml
[package]
name = "rasica-common"
description = "Shared primitives, error, configuration, and logging framework for RASICA."
version.workspace = true
edition.workspace = true
rust-version.workspace = true
authors.workspace = true
license.workspace = true
repository.workspace = true
publish.workspace = true

[lints]
workspace = true

[dependencies]
thiserror = { workspace = true }
semver = { workspace = true }
figment = { workspace = true }
serde = { workspace = true }
tracing = { workspace = true }
tracing-subscriber = { workspace = true }
uuid = { workspace = true }

[dev-dependencies]
proptest = { workspace = true }
```

### 4.3 Primitive Types

#### 4.3.1 `src/id.rs` — Generic, phantom-typed identifiers

Every Core Architectural Object introduced from Phase 2 onward needs a stable, globally unique, strongly-typed identifier (e.g. `RuleId` in Appendix G is hand-rolled as a bare `String`; Phase 1 generalises that pattern once, here, so later phases do not each reinvent a string-wrapper with weaker guarantees). `Id<T>` is zero-cost: the phantom type parameter exists only at compile time.

```rust
//! Strongly-typed, globally unique identifiers.
//!
//! `Id<T>` prevents mixing up identifiers that belong to different
//! Core Architectural Objects (e.g. accidentally comparing a `DatasetId`
//! to a `RuleId`) at compile time, at zero runtime cost, by carrying a
//! phantom marker type. See Architecture Spec Appendix G, which defines
//! `RuleId` and `DomainModuleId` as the first two consumers of this pattern.

use std::{
    cmp::Ordering,
    fmt,
    hash::{Hash, Hasher},
    marker::PhantomData,
    str::FromStr,
};

use uuid::Uuid;

/// A globally unique identifier for a value of type `T`.
///
/// `T` is a marker type only; it need not (and typically does not) exist
/// as a runtime value. `Id<T>` is `Copy`, `Eq`, `Ord`, and `Hash` regardless
/// of whether `T` implements those traits, because the identifier's identity
/// is independent of `T`'s own properties.
pub struct Id<T> {
    value: Uuid,
    _marker: PhantomData<fn() -> T>,
}

impl<T> Id<T> {
    /// Generates a new, random `Id`.
    ///
    /// Uses UUIDv4. Random identifier generation is intentionally excluded
    /// from any code path that participates in Logical Determinism
    /// (Architecture Spec §4.1): identifiers name objects, they do not
    /// influence which analytical operations are selected or in what order
    /// rules apply. Any object whose *content* (not just its identity) must
    /// be reproducible across runs is fingerprinted separately — see
    /// `rasica-core::fingerprint`.
    #[must_use]
    pub fn new() -> Self {
        Self {
            value: Uuid::new_v4(),
            _marker: PhantomData,
        }
    }

    /// Constructs an `Id` from an existing, already-unique raw value.
    ///
    /// Used for deserialising identifiers that were generated in a previous
    /// process (e.g. loaded from a persisted Audit Record, §6.15).
    #[must_use]
    pub const fn from_uuid(value: Uuid) -> Self {
        Self {
            value,
            _marker: PhantomData,
        }
    }

    /// Returns the underlying UUID.
    #[must_use]
    pub const fn as_uuid(&self) -> Uuid {
        self.value
    }
}

impl<T> Default for Id<T> {
    fn default() -> Self {
        Self::new()
    }
}

// Manual trait implementations below: `#[derive(..)]` would require `T: Clone`,
// `T: Eq`, etc., which is incorrect for a phantom marker (see the classic
// "phantom type parameter" derive pitfall). Implementing by hand keeps `Id<T>`
// usable for any marker `T`, matching its stated contract above.

impl<T> Clone for Id<T> {
    fn clone(&self) -> Self {
        *self
    }
}
impl<T> Copy for Id<T> {}

impl<T> PartialEq for Id<T> {
    fn eq(&self, other: &Self) -> bool {
        self.value == other.value
    }
}
impl<T> Eq for Id<T> {}

impl<T> PartialOrd for Id<T> {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}
impl<T> Ord for Id<T> {
    fn cmp(&self, other: &Self) -> Ordering {
        self.value.cmp(&other.value)
    }
}

impl<T> Hash for Id<T> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.value.hash(state);
    }
}

impl<T> fmt::Debug for Id<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_tuple("Id").field(&self.value).finish()
    }
}

impl<T> fmt::Display for Id<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Display::fmt(&self.value, f)
    }
}

impl<T> FromStr for Id<T> {
    type Err = uuid::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Uuid::from_str(s).map(Self::from_uuid)
    }
}

impl<T> serde::Serialize for Id<T> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.value.serialize(serializer)
    }
}

impl<'de, T> serde::Deserialize<'de> for Id<T> {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Uuid::deserialize(deserializer).map(Self::from_uuid)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct DatasetMarker;
    struct RuleMarker;

    #[test]
    fn distinct_ids_are_not_equal() {
        let a: Id<DatasetMarker> = Id::new();
        let b: Id<DatasetMarker> = Id::new();
        assert_ne!(a, b);
    }

    #[test]
    fn round_trips_through_string() {
        let original: Id<RuleMarker> = Id::new();
        let parsed: Id<RuleMarker> = original.to_string().parse().expect(
            "an Id's Display output is always a valid UUID string, so parsing it back can never fail",
        );
        assert_eq!(original, parsed);
    }

    #[test]
    fn is_copy() {
        let a: Id<DatasetMarker> = Id::new();
        let b = a; // would fail to compile if `Id` were not `Copy`
        assert_eq!(a, b);
    }
}
```

#### 4.3.2 `src/version.rs` — Engine and module versioning

Implements Architecture Spec §14.16 ("Domain Modules and the Core Engine shall be versioned independently") and provides the `SemVer` / `EngineVersionRange` vocabulary that Appendix G's `DomainModule::version()` and `engine_compatibility()` reference.

```rust
//! Semantic versioning primitives shared by the Core Engine and every
//! Domain Module (Architecture Spec §14.16, Appendix G).

use std::fmt;

pub use semver::Version as SemVer;
use semver::VersionReq;

/// The version of the RASICA Core Engine itself, as distinct from any
/// individual Domain Module's version (§14.16: versioned independently).
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct EngineVersion(SemVer);

impl EngineVersion {
    /// Wraps an existing [`SemVer`] as the current engine version.
    #[must_use]
    pub const fn new(version: SemVer) -> Self {
        Self(version)
    }

    /// Returns the underlying [`SemVer`].
    #[must_use]
    pub const fn as_semver(&self) -> &SemVer {
        &self.0
    }
}

impl fmt::Display for EngineVersion {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Display::fmt(&self.0, f)
    }
}

/// A range of Core Engine versions a Domain Module declares itself
/// compatible with (Appendix G: `DomainModule::engine_compatibility`).
///
/// Compatibility checking, not construction, is the operation that matters:
/// a malformed or overly broad range is a Domain Module authoring defect to
/// be caught at Domain Manager registration time (Architecture Spec §11.7),
/// not something this type attempts to prevent structurally.
#[derive(Debug, Clone)]
pub struct EngineVersionRange(VersionReq);

impl EngineVersionRange {
    /// Parses a Cargo-style version requirement string (e.g. `">=0.3, <0.5"`).
    ///
    /// # Errors
    ///
    /// Returns [`semver::Error`] if `requirement` is not a valid version
    /// requirement expression.
    pub fn parse(requirement: &str) -> Result<Self, semver::Error> {
        VersionReq::parse(requirement).map(Self)
    }

    /// Returns whether `version` satisfies this range.
    #[must_use]
    pub fn matches(&self, version: &EngineVersion) -> bool {
        self.0.matches(version.as_semver())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn range_matches_within_bounds() {
        let range = EngineVersionRange::parse(">=1.0.0, <2.0.0")
            .expect("literal in test is a valid semver requirement");
        let compatible = EngineVersion::new(SemVer::new(1, 5, 0));
        let incompatible = EngineVersion::new(SemVer::new(2, 0, 0));

        assert!(range.matches(&compatible));
        assert!(!range.matches(&incompatible));
    }
}
```

#### 4.3.3 `src/lib.rs` (partial — assembled fully in §4.7)

Primitive re-exports live at the crate root so downstream crates write `rasica_common::Id<T>` rather than reaching into submodules, per §14.8 (public API consistency).

### 4.4 Error Framework

#### 4.4.1 Design

Architecture Spec §14.9 requires errors to be: structured, deterministic, context-preserving, machine-readable, human-readable, and propagation-safe. A single crate-wide error *type* would violate crate independence (§14.6: "no crate shall contain unrelated responsibilities") by forcing every crate's failure modes into one enum. Instead, `rasica-common` defines a **contract** every crate's own error type implements, plus one concrete leaf type (`ConfigError`) for the framework code that lives in this crate itself.

```rust
//! The error framework contract every RASICA crate's error type implements.
//!
//! Architecture Spec §14.9 requires errors to be structured, deterministic,
//! context-preserving, and both machine- and human-readable. Rather than one
//! monolithic error enum (which would couple every crate to every other
//! crate's failure modes, contradicting §14.6), each crate defines its own
//! `thiserror`-derived error enum and implements [`RasicaError`] on it. This
//! gives every subsystem's errors a shared, queryable shape without shared
//! variants.

use std::fmt;

/// A stable, machine-readable identifier for one specific error condition.
///
/// `ErrorCode`s are namespaced by crate (e.g. `"config::missing_key"`,
/// `"dataset::schema_mismatch"`) and, once shipped, are never reassigned to
/// a different meaning — renaming the human-readable message is a patch
/// change; changing what a published code *means* is at minimum a minor
/// change under §14.16, since it can break automated tooling built against it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ErrorCode(pub &'static str);

impl fmt::Display for ErrorCode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.0)
    }
}

/// How severely an error condition should be treated by callers that only
/// have generic handling available (e.g. a top-level CLI error reporter).
///
/// This is orthogonal to whether the error is `Result::Err` — every variant
/// here is still a `Result::Err`, never a panic (§14.9: panics are reserved
/// for programming defects, not expected execution conditions).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum ErrorSeverity {
    /// The requested operation could not complete, but the process and any
    /// already-constructed Tier 1 objects (§6.2A) remain valid and usable.
    Recoverable,
    /// The current operation cannot safely continue, but the failure is
    /// confined to it; sibling operations (e.g. a different Analysis Graph
    /// node) are unaffected.
    Isolated,
    /// The failure indicates the process's invariants can no longer be
    /// trusted (e.g. a Tier 1 object was observed in an inconsistent state).
    /// Callers should treat this as fatal to the current execution.
    Fatal,
}

/// Implemented by every crate-specific error enum in RASICA.
///
/// Implementations are expected to be `thiserror`-derived enums; this trait
/// adds the machine-readable metadata `thiserror`/`std::error::Error` do not
/// provide on their own.
pub trait RasicaError: std::error::Error + Send + Sync + 'static {
    /// The stable, machine-readable code identifying this error condition.
    fn error_code(&self) -> ErrorCode;

    /// The severity to apply when no more specific handling is available.
    fn severity(&self) -> ErrorSeverity;
}
```

#### 4.4.2 Worked example: `config/error.rs`

This is the first real consumer of the contract above, and the pattern every later crate's error type follows.

```rust
//! Errors produced by the configuration framework (§4.5 of the Phase 1
//! specification; Architecture Spec §14.10).

use thiserror::Error;

use crate::error::{ErrorCode, ErrorSeverity, RasicaError};

/// Errors that can occur while loading or validating [`crate::config::RasicaConfig`].
#[derive(Debug, Error)]
pub enum ConfigError {
    /// A configuration source (file or environment) could not be read.
    #[error("failed to read configuration source '{source_name}': {cause}")]
    SourceUnreadable {
        /// Identifies which layer failed (e.g. a file path or "environment").
        source_name: String,
        /// The underlying I/O or parse failure, preserved for diagnosis.
        #[source]
        cause: figment::Error,
    },

    /// A required configuration key was absent after merging all layers.
    #[error("required configuration key '{key}' was not provided by any layer")]
    MissingKey {
        /// The dotted key path that was missing (e.g. `"logging.level"`).
        key: String,
    },

    /// A configuration value was present but failed validation.
    #[error("configuration key '{key}' failed validation: {reason}")]
    InvalidValue {
        /// The dotted key path that failed validation.
        key: String,
        /// A human-readable explanation of why the value was rejected.
        reason: String,
    },
}

impl RasicaError for ConfigError {
    fn error_code(&self) -> ErrorCode {
        match self {
            Self::SourceUnreadable { .. } => ErrorCode("config::source_unreadable"),
            Self::MissingKey { .. } => ErrorCode("config::missing_key"),
            Self::InvalidValue { .. } => ErrorCode("config::invalid_value"),
        }
    }

    fn severity(&self) -> ErrorSeverity {
        // All three conditions are Recoverable: they occur before any Tier 1
        // object (§6.2A) has been constructed, so the process can report the
        // problem and exit cleanly without having left inconsistent state.
        ErrorSeverity::Recoverable
    }
}
```

### 4.5 Configuration Framework

#### 4.5.1 Design

Architecture Spec §14.10: configuration is external to analytical logic and "shall never alter mathematical correctness." Phase 1 has no analytical logic yet, but the *shape* of `RasicaConfig` is a load-bearing decision for every later phase: once a switch exists in this struct, every later phase reads it through the same immutable, validated snapshot rather than each crate parsing environment variables independently (which would violate §14.7's prohibition on hidden dependencies).

Design decisions:

- **Layered loading** via `figment`: compiled-in defaults → optional TOML file → environment variables (`RASICA_*`), each layer overriding the last. This is a standard, auditable precedence order rather than ad hoc merging logic.
- **Immutable after load** (Tier 1 discipline, §6.2A, applied even though `RasicaConfig` is not itself a Core Architectural Object): `RasicaConfig::load` returns a fully validated, `Arc`-friendly value with no public mutation API. Any change requires loading a new instance — exactly the Tier 1 contract, applied here for the same reason: a config that could be mutated in place after validation would let a single stale reference and a mutation race disagree about what "the" configuration is.
- **No analytical fields in Phase 1**: the initial schema contains only `logging` and `engine` sections. Later phases add sections (e.g. execution concurrency limits, Appendix H's concurrency scaling target) but §14.10's prohibition means none of those additions may ever be able to change *which* rules fire or *what* an analytical conclusion is — only how it is computed or presented.

```rust
//! Layered, immutable configuration loading (Architecture Spec §14.10).

pub mod error;
mod layers;

use std::path::Path;

use serde::Deserialize;

pub use self::error::ConfigError;
use crate::version::EngineVersion;

/// The fully resolved, immutable RASICA configuration.
///
/// Constructed only via [`RasicaConfig::load`]. There is deliberately no
/// public constructor or mutator: every field is fixed once validation
/// succeeds, matching the Tier 1 discipline of Architecture Spec §6.2A even
/// though `RasicaConfig` predates the Core Architectural Object hierarchy.
#[derive(Debug, Clone, Deserialize)]
pub struct RasicaConfig {
    logging: LoggingConfig,
}

impl RasicaConfig {
    /// Loads configuration from, in increasing precedence:
    ///
    /// 1. compiled-in defaults,
    /// 2. the TOML file at `file_path`, if it exists,
    /// 3. environment variables prefixed `RASICA_` (double underscore as the
    ///    nested-key separator, e.g. `RASICA_LOGGING__LEVEL=debug`).
    ///
    /// # Errors
    ///
    /// Returns [`ConfigError`] if a present source is malformed, a required
    /// key is missing after merging, or a value fails validation.
    pub fn load(file_path: impl AsRef<Path>) -> Result<Self, ConfigError> {
        layers::load(file_path.as_ref())
    }

    /// Returns the logging configuration section.
    #[must_use]
    pub const fn logging(&self) -> &LoggingConfig {
        &self.logging
    }
}

/// Configuration governing the logging/tracing framework (§4.6).
#[derive(Debug, Clone, Deserialize)]
pub struct LoggingConfig {
    level: LogLevel,
    format: LogFormat,
}

impl LoggingConfig {
    /// The minimum severity level that should be emitted.
    #[must_use]
    pub const fn level(&self) -> LogLevel {
        self.level
    }

    /// The output encoding for log records.
    #[must_use]
    pub const fn format(&self) -> LogFormat {
        self.format
    }
}

/// Supported log severity levels, mapped onto `tracing`'s levels in §4.6.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogLevel {
    /// Fine-grained diagnostic detail; not enabled by default.
    Trace,
    /// Development-time detail.
    Debug,
    /// Normal operational messages. The default level.
    Info,
    /// Recoverable but noteworthy conditions.
    Warn,
    /// Failures, per the error framework in §4.4.
    Error,
}

/// Supported log output encodings.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum LogFormat {
    /// Human-readable, coloured output — suited to local development.
    Pretty,
    /// Newline-delimited JSON — suited to CI and production log aggregation
    /// (§14.9: errors, and by extension diagnostics, "remain machine-readable").
    Json,
}

/// Reports which [`EngineVersion`] built this configuration schema, so that
/// a persisted config (or an Audit Record referencing one, §6.15) can be
/// checked for compatibility with the engine reading it back.
#[must_use]
pub fn schema_engine_version() -> EngineVersion {
    EngineVersion::new(
        crate::version::SemVer::parse(env!("CARGO_PKG_VERSION"))
            .expect("CARGO_PKG_VERSION is set by Cargo and is always a valid semver string"),
    )
}
```

`src/config/layers.rs`:

```rust
//! Layer-merging implementation backing [`super::RasicaConfig::load`].

use std::path::Path;

use figment::{
    providers::{Env, Format, Serialized, Toml},
    Figment,
};
use serde::Serialize;

use super::{ConfigError, LogFormat, LogLevel, LoggingConfig, RasicaConfig};

/// Compiled-in defaults, expressed as a plain serialisable struct so they
/// participate in the same merge machinery as every other layer rather than
/// being special-cased.
#[derive(Serialize)]
struct Defaults {
    logging: DefaultsLogging,
}

#[derive(Serialize)]
struct DefaultsLogging {
    level: &'static str,
    format: &'static str,
}

impl Default for Defaults {
    fn default() -> Self {
        Self {
            logging: DefaultsLogging {
                level: "info",
                format: "pretty",
            },
        }
    }
}

pub(super) fn load(file_path: &Path) -> Result<RasicaConfig, ConfigError> {
    let mut figment = Figment::new().merge(Serialized::defaults(Defaults::default()));

    if file_path.exists() {
        figment = figment.merge(Toml::file(file_path));
    }

    figment = figment.merge(Env::prefixed("RASICA_").split("__"));

    figment
        .extract()
        .map_err(|cause| ConfigError::SourceUnreadable {
            source_name: file_path.display().to_string(),
            cause,
        })
}

// LogLevel / LogFormat need Deserialize (already derived on the public types
// in mod.rs); no additional glue is required here because Figment/serde
// deserialise directly into the public config structs.
```

### 4.6 Logging Framework

Architecture Spec §14.6 (Rust Engineering Principles context) and the observability groundwork for §13 (Diagnostics, Auditing and Observability — a later phase) both depend on structured logging being available from the first commit. `tracing` is used rather than the `log` facade because later phases need span-scoped, structured fields (e.g. tagging every log line within one Analysis Graph node's execution with that node's `Id`), which `tracing` supports natively and `log` does not.

```rust
//! Logging/tracing initialisation (Architecture Spec §14.6 context; consumed
//! by the Diagnostics framework in a later phase, §6.14/§13).

use tracing::level_filters::LevelFilter;
use tracing_subscriber::{fmt, EnvFilter};

use crate::config::{LogFormat, LogLevel, LoggingConfig};

/// Initialises the global `tracing` subscriber from `config`.
///
/// This shall be called exactly once, as early as possible in `main`, before
/// any other RASICA code runs. Calling it more than once will return an
/// error from the underlying `tracing` global-subscriber registration; that
/// error is treated as a programming defect per §14.9 and is therefore
/// intentionally surfaced as a panic rather than a `Result`, since a second
/// call can only be reached by an implementation mistake, not by any runtime
/// condition a caller could meaningfully recover from.
///
/// # Panics
///
/// Panics if a global subscriber has already been installed.
pub fn init(config: &LoggingConfig) {
    let filter = EnvFilter::builder()
        .with_default_directive(level_filter(config.level()).into())
        .from_env_lossy();

    let subscriber = fmt().with_env_filter(filter);

    match config.format() {
        LogFormat::Pretty => subscriber.pretty().init(),
        LogFormat::Json => subscriber.json().init(),
    }
}

const fn level_filter(level: LogLevel) -> LevelFilter {
    match level {
        LogLevel::Trace => LevelFilter::TRACE,
        LogLevel::Debug => LevelFilter::DEBUG,
        LogLevel::Info => LevelFilter::INFO,
        LogLevel::Warn => LevelFilter::WARN,
        LogLevel::Error => LevelFilter::ERROR,
    }
}
```

### 4.7 `src/lib.rs` — crate root

```rust
//! `rasica-common`: shared primitives, error framework, configuration
//! framework, and logging framework for every RASICA crate.
//!
//! This crate implements no analytical, statistical, or domain logic
//! (Architecture Spec §14.6: "no crate shall contain unrelated
//! responsibilities"). Every other RASICA crate may depend on it
//! unconditionally; it depends on nothing internal to RASICA itself.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod config;
pub mod error;
pub mod id;
pub mod logging;
pub mod version;

pub use error::{ErrorCode, ErrorSeverity, RasicaError};
pub use id::Id;
pub use version::{EngineVersion, EngineVersionRange, SemVer};
```

---

## 5. Crate: `rasica-core`

### 5.1 Responsibilities

`rasica-core` owns the vocabulary shared by every Core Architectural Object (Architecture Spec §6) before any specific object exists. Concretely, in Phase 1, that is:

- the three Mutability Tier marker traits from §6.2A, matching Appendix G's `Immutable`, `AppendOnly`, `ScopedMutable` verbatim (per the Appendix G Type Authority Policy: *"A module specification should begin by adopting the relevant signature from this appendix verbatim"*),
- a deterministic fingerprinting contract, required by §6.2A's rule that Tier 3 caches are "always keyed by a deterministic fingerprint of their inputs," and by §4.1's Numeric Determinism scoping,
- an `Identifiable` trait tying `rasica-common::Id<T>` to Core Architectural Objects generically.

`rasica-core` depends only on `rasica-common`. Every later crate that defines a Core Architectural Object (`rasica-dataset` for `Dataset`, `rasica-rules` for `Rule`, and so on) depends on `rasica-core` and implements these traits; `rasica-core` never depends forward on any of them, keeping Architecture Spec §8's dependency graph acyclic.

### 5.2 `Cargo.toml`

```toml
[package]
name = "rasica-core"
description = "Core Architectural Object vocabulary: mutability tiers, identity, and deterministic fingerprinting."
version.workspace = true
edition.workspace = true
rust-version.workspace = true
authors.workspace = true
license.workspace = true
repository.workspace = true
publish.workspace = true

[lints]
workspace = true

[dependencies]
rasica-common = { path = "../rasica-common" }
blake3 = { workspace = true }

[dev-dependencies]
proptest = { workspace = true }
```

### 5.3 Mutability Tiers — `src/mutability.rs`

This is the illustrative Appendix G signature made authoritative, per the Type Authority Policy ("Invariant properties — copy, do not relitigate... A module specification shall not narrow, loosen, or omit these"). No field types or bounds are changed; documentation is expanded to make the tier rules enforceable in review rather than only in prose.

```rust
//! The three Mutability Tiers every Core Architectural Object belongs to
//! for its entire lifetime (Architecture Spec §6.2A).
//!
//! These traits are markers: they carry no methods of their own beyond what
//! each tier's contract requires (`AppendOnly::append`). Their purpose is to
//! make an object's tier a checkable part of its public type, not a comment.

/// Tier 1 — Immutable (§6.2A).
///
/// The object is fully constructed once and never modified afterward for the
/// remainder of the process. Any change requires constructing a new object
/// with a new identity.
///
/// Implementors provide no public API capable of mutating `self` after
/// construction. This is a documentation contract this trait cannot enforce
/// mechanically for arbitrary interior mutability (e.g. `Cell`); reviewers
/// checking §14.12 compliance for a new `Immutable` implementor shall verify
/// by inspection that no such backdoor exists.
///
/// Applies, per §6.2A, to: Dataset, Metadata, Validation Report, Structural
/// Knowledge, Knowledge Graph, Domain Facts, Capability Registry, Rules,
/// Analysis Graph, Audit Record. None of these types exist yet in Phase 1;
/// this trait is defined now so their specifications (Appendix E items
/// 03–13) have it available from their first line of code.
pub trait Immutable: Send + Sync {}

/// Tier 2 — Append-Only (§6.2A).
///
/// The object may receive additional entries over the course of an
/// execution, but existing entries are never altered or removed once
/// written. Every consumer that reads a snapshot of it treats it as
/// immutable at the point of reading.
///
/// The only mutating operation permitted is [`AppendOnly::append`].
/// Applies, per §6.2A, to: Diagnostics.
pub trait AppendOnly: Send + Sync {
    /// The type of a single entry appended to this object.
    type Entry;

    /// Appends `entry`. Implementors shall never remove, reorder, or modify
    /// any previously appended entry as a side effect of this call.
    fn append(&mut self, entry: Self::Entry);
}

/// Tier 3 — Scoped-Mutable (§6.2A).
///
/// The object is mutable only within the bounded lifetime of a single
/// execution, is owned exclusively by one subsystem during that lifetime,
/// is never shared as a mutable reference across subsystem boundaries, and
/// is discarded — never persisted as authoritative state — at the end of
/// the execution.
///
/// Three rules govern every `ScopedMutable` implementor (§6.2A) and are not
/// mechanically enforced by this trait; they are checked in review (§14.12)
/// and, where practical, by the integration tests of the crate that owns the
/// implementor:
///
/// 1. A `ScopedMutable` object shall never be the source of truth for an
///    analytical conclusion; conclusions are always derived from `Immutable`
///    (Tier 1) objects.
/// 2. Caching intermediate results is a Tier 3 concern: cached values are a
///    performance optimisation over already-deterministic Tier 1
///    computations, are always keyed by a value implementing
///    [`crate::fingerprint::DeterministicFingerprint`] over their inputs, and
///    their presence or absence shall never change the analytical result,
///    only the time taken to produce it.
/// 3. No object may be promoted from Tier 3 to Tier 1 by aliasing; an
///    `Immutable` object referencing Tier 3-derived data must copy the data
///    at the point of construction.
///
/// Applies, per §6.2A, to: Execution Context, and internal Execution Engine
/// caches of intermediate results.
pub trait ScopedMutable: Send {}
```

### 5.4 Deterministic Fingerprinting — `src/fingerprint.rs`

This is new relative to Appendix G's illustrative sketch, but is required by an invariant Appendix G's sketch references without defining: §6.2A's "always keyed by a deterministic fingerprint of their inputs." Per the Type Authority Policy, an omission of a mechanism an invariant depends on is exactly the gap a phase specification is expected to fill; the invariant itself (that a fingerprint must be deterministic and input-derived) is not being narrowed, loosened, or altered — only given a concrete, reusable type.

`blake3` is chosen over `std::hash::Hash`/`DefaultHasher` deliberately: `DefaultHasher`'s algorithm is *not* guaranteed stable across Rust versions or compilations, which would silently break Numeric Determinism's "bit-identical... across executions" guarantee (§4.1) the moment the toolchain changed. BLAKE3 is a fixed, versioned, cryptographic-strength hash with stable output across platforms and Rust versions, and is fast enough not to become the bottleneck the caching it supports is meant to avoid.

```rust
//! Deterministic fingerprinting, required by Architecture Spec §6.2A for
//! keying Tier 3 caches, and supporting the Numeric Determinism guarantee of
//! §4.1 by giving later phases (e.g. the Rule Engine's fact-base lookups,
//! §10.14A) one stable, non-toolchain-dependent hash to build on.

use std::fmt;

/// The output of a deterministic fingerprint: a fixed-size, comparable,
/// hashable digest.
///
/// Two `Fingerprint`s are equal if and only if they were computed from
/// byte-identical [`DeterministicFingerprint::fingerprint_bytes`] output.
/// `Fingerprint` deliberately does not implement [`std::hash::Hash`] against
/// `std::collections::HashMap`'s default `RandomState` hasher; the digest
/// itself is already a strong, uniformly distributed 256-bit value, so
/// consumers needing a `HashMap` key should use the digest's bytes directly
/// (e.g. via a `BuildHasherDefault` over a non-randomising hasher) rather
/// than re-hashing it with a randomised hasher that would reintroduce the
/// very non-determinism this type exists to avoid.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Fingerprint([u8; 32]);

impl Fingerprint {
    /// Returns the raw 32-byte BLAKE3 digest.
    #[must_use]
    pub const fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }

    /// Renders the fingerprint as a lowercase hexadecimal string, suitable
    /// for inclusion in an Audit Record (§6.15) or a diagnostic message.
    #[must_use]
    pub fn to_hex(&self) -> String {
        blake3::Hash::from(self.0).to_hex().to_string()
    }
}

impl fmt::Debug for Fingerprint {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_tuple("Fingerprint").field(&self.to_hex()).finish()
    }
}

impl fmt::Display for Fingerprint {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.to_hex())
    }
}

/// Implemented by any value that can be turned into a stable byte sequence
/// for fingerprinting.
///
/// # Contract
///
/// Implementations shall be:
///
/// - **Deterministic:** the same logical value always produces the same
///   bytes, regardless of process, platform, or execution order. In
///   particular, implementations shall not depend on: pointer addresses,
///   `HashMap`/`HashSet` iteration order (use a sorted representation
///   instead), the current time, or any other source of non-determinism —
///   this is the same requirement §4.1 places on Logical Determinism, applied
///   at the byte-representation level.
/// - **Injective with respect to logical equality:** two values that are not
///   logically equal shall not (outside of the negligible probability of a
///   BLAKE3 collision) produce the same bytes.
pub trait DeterministicFingerprint {
    /// Returns the deterministic byte representation of `self` used as
    /// fingerprint input.
    fn fingerprint_bytes(&self) -> Vec<u8>;

    /// Computes this value's [`Fingerprint`].
    ///
    /// Provided in terms of [`DeterministicFingerprint::fingerprint_bytes`];
    /// implementors should not need to override this.
    fn fingerprint(&self) -> Fingerprint {
        Fingerprint(*blake3::hash(&self.fingerprint_bytes()).as_bytes())
    }
}

// Blanket impl for byte slices themselves, so composite fingerprints can be
// built by fingerprinting sub-parts and concatenating, e.g.:
//   [a.fingerprint().as_bytes(), b.fingerprint().as_bytes()].concat()
impl DeterministicFingerprint for [u8] {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        self.to_vec()
    }
}

impl DeterministicFingerprint for str {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        self.as_bytes().to_vec()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identical_input_produces_identical_fingerprint() {
        assert_eq!("rasica".fingerprint(), "rasica".fingerprint());
    }

    #[test]
    fn different_input_produces_different_fingerprint() {
        assert_ne!("rasica".fingerprint(), "RASICA".fingerprint());
    }

    #[test]
    fn composite_fingerprint_is_order_sensitive() {
        let ab: Vec<u8> = [
            "a".fingerprint().as_bytes().as_slice(),
            "b".fingerprint().as_bytes().as_slice(),
        ]
        .concat();
        let ba: Vec<u8> = [
            "b".fingerprint().as_bytes().as_slice(),
            "a".fingerprint().as_bytes().as_slice(),
        ]
        .concat();

        assert_ne!(ab.fingerprint(), ba.fingerprint());
    }

    proptest::proptest! {
        #[test]
        fn fingerprint_is_deterministic_across_calls(s in ".*") {
            let first = s.fingerprint();
            let second = s.fingerprint();
            proptest::prop_assert_eq!(first, second);
        }
    }
}
```

### 5.5 Identity — `src/identity.rs`

```rust
//! Ties [`rasica_common::Id`] to Core Architectural Objects generically.

use rasica_common::Id;

/// Implemented by every Core Architectural Object that has a stable identity
/// distinct from its content (Architecture Spec §6.2, "Single source of
/// truth").
///
/// Not every Core Architectural Object needs identity distinct from content —
/// two `Fingerprint`-equal values may be legitimately interchangeable — so
/// this trait is opt-in, not a supertrait of [`crate::mutability::Immutable`].
pub trait Identifiable {
    /// The marker type distinguishing this object's identifiers from every
    /// other object's, per [`Id`]'s own documentation.
    type Marker;

    /// Returns this object's stable identifier.
    fn id(&self) -> Id<Self::Marker>;
}
```

### 5.6 Prelude — `src/prelude.rs`

Per §14.8 (public API consistency), later crates that implement Core Architectural Objects import one prelude rather than five separate paths.

```rust
//! Convenience re-export of the vocabulary every Core Architectural Object
//! implementation needs. Later crates are expected to write
//! `use rasica_core::prelude::*;` rather than importing each item
//! individually.

pub use crate::{
    fingerprint::{DeterministicFingerprint, Fingerprint},
    identity::Identifiable,
    mutability::{AppendOnly, Immutable, ScopedMutable},
};
```

### 5.7 `src/lib.rs`

```rust
//! `rasica-core`: the Mutability Tier, identity, and deterministic
//! fingerprinting vocabulary shared by every Core Architectural Object
//! (Architecture Spec §6).
//!
//! This crate defines no Core Architectural Object itself — `Dataset`,
//! `Rule`, and the rest are introduced by the phase specifications that
//! implement Architecture Spec §6.4 onward. It defines only the vocabulary
//! those objects share.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod fingerprint;
pub mod identity;
pub mod mutability;
pub mod prelude;
```

---

## 6. Testing Framework

### 6.1 Policy

Architecture Spec §14.13 requires unit, integration, property-based, benchmark, regression, and end-to-end tests. Phase 1 establishes the *harness* for the first three (no analytical code exists yet to warrant benchmark/regression/end-to-end tests):

- **Unit tests:** inline `#[cfg(test)] mod tests` per module, as shown throughout §4 and §5. Run via `cargo nextest run` (configured in §3.6), not bare `cargo test`, for faster, more isolated parallel execution and clearer CI output.
- **Property-based tests:** `proptest`, demonstrated in `fingerprint.rs` (§5.4). Later phases use this same dependency (declared once at the workspace level, §3.2) for e.g. Rule Engine stratification invariants.
- **Workspace smoke test:** a top-level integration crate (`tests/workspace_smoke`) that depends on every published crate and asserts the workspace composes — catching version-mismatch or visibility mistakes that per-crate unit tests cannot.

### 6.2 `tests/workspace_smoke/Cargo.toml`

```toml
[package]
name = "workspace-smoke"
description = "Cross-crate smoke tests verifying the Phase 1 workspace composes correctly."
version.workspace = true
edition.workspace = true
rust-version.workspace = true
publish = false

[lints]
workspace = true

[dependencies]
rasica-common = { path = "../../crates/rasica-common" }
rasica-core = { path = "../../crates/rasica-core" }
```

### 6.3 `tests/workspace_smoke/tests/smoke.rs`

```rust
//! Verifies that `rasica-core` and `rasica-common` compose as intended:
//! the tier markers and fingerprinting contract are usable together to
//! define a minimal, hypothetical Tier 1 object, exactly as a real Core
//! Architectural Object will do starting in Phase 2.

use rasica_common::Id;
use rasica_core::prelude::*;

struct ExampleMarker;

/// A minimal stand-in for a future Tier 1 Core Architectural Object,
/// existing only to prove the Phase 1 vocabulary is sufficient to build one.
struct ExampleImmutableObject {
    id: Id<ExampleMarker>,
    payload: String,
}

impl Immutable for ExampleImmutableObject {}

impl Identifiable for ExampleImmutableObject {
    type Marker = ExampleMarker;

    fn id(&self) -> Id<Self::Marker> {
        self.id
    }
}

impl DeterministicFingerprint for ExampleImmutableObject {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        // Deliberately excludes `self.id`: identity is not content, and two
        // objects with different identities but identical payloads should
        // fingerprint identically (§6.2A's caching rule keys on *inputs*,
        // i.e. content, not on identity).
        self.payload.fingerprint_bytes()
    }
}

#[test]
fn tier_and_identity_traits_compose_on_a_real_type() {
    let object = ExampleImmutableObject {
        id: Id::new(),
        payload: "example".to_owned(),
    };

    let _ = object.id();
    let _ = object.fingerprint();
}

#[test]
fn objects_with_equal_content_fingerprint_equally_regardless_of_identity() {
    let a = ExampleImmutableObject {
        id: Id::new(),
        payload: "same".to_owned(),
    };
    let b = ExampleImmutableObject {
        id: Id::new(),
        payload: "same".to_owned(),
    };

    assert_ne!(a.id(), b.id());
    assert_eq!(a.fingerprint(), b.fingerprint());
}
```

### 6.4 Coverage

`cargo llvm-cov` is used for coverage reporting (added as a CI step in §7, not a workspace dependency, since it is a `cargo` subcommand installed on the CI runner). No numeric coverage gate is set in Phase 1: with no analytical logic yet, a percentage target would be meaningless. §16.2 (Acceptance Gate Requirements) is the place a future phase should introduce one, once there is behaviour worth gating on.

---

## 7. Build Pipeline (CI)

### 7.1 Policy

Architecture Spec §14.14 requires every change to automatically run: compilation, formatting, linting, documentation generation, unit tests, integration tests, benchmark regression checks, dependency audits, and security audits. Benchmark regression checks are stubbed as a no-op job (with a comment explaining why) rather than omitted, so the pipeline's *shape* matches §14.14 from commit one and later phases only need to fill in the job body, not restructure the workflow.

### 7.2 `.github/workflows/ci.yml`

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

env:
  CARGO_TERM_COLOR: always
  RUSTFLAGS: "-D warnings"
  RUSTDOCFLAGS: "-D warnings"

jobs:
  fmt:
    name: Formatting
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: rustfmt
      - run: cargo fmt --all -- --check

  clippy:
    name: Lint (clippy)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy
      - uses: Swatinem/rust-cache@v2
      # Missing docs are `warn` at the crate level (§3.2) so local
      # development isn't blocked mid-edit, and promoted to a hard failure
      # here via RUSTFLAGS/RUSTDOCFLAGS above, satisfying §15.4's exit
      # criterion "coding standards enforced".
      - run: cargo clippy --workspace --all-targets -- -D warnings

  test:
    name: Test (nextest)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: taiki-e/install-action@nextest
      - uses: Swatinem/rust-cache@v2
      - run: cargo nextest run --workspace --profile ci

  doc:
    name: Documentation
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
      - run: cargo doc --workspace --no-deps --document-private-items

  audit:
    name: Dependency & Security Audit
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: taiki-e/install-action@cargo-deny
      - run: cargo deny check

  benchmark-regression:
    name: Benchmark Regression Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # No benchmarks exist yet: Phase 1 introduces no analytical or
      # performance-sensitive code (Appendix H's targets apply from Phase 2
      # onward). This job is retained as a placeholder, per Architecture
      # Spec §14.14, so the pipeline's job list already matches the full
      # required set and no later phase needs to restructure `ci.yml` to
      # "add" this requirement — only to give it a real body (`cargo
      # bench` + a stored baseline comparison).
      - run: echo "No benchmarks defined in Phase 1; see Appendix H and §14.15."

  msrv:
    name: Minimum Supported Rust Version
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - id: msrv
        run: echo "version=$(cat .rust-version)" >> "$GITHUB_OUTPUT"
      - uses: dtolnay/rust-toolchain@master
        with:
          toolchain: ${{ steps.msrv.outputs.version }}
      - uses: Swatinem/rust-cache@v2
      - run: cargo check --workspace
```

### 7.3 Local Developer Convenience — `justfile`

Not a Phase 1 deliverable per §15.4, but included so implementers (human or AI) run exactly what CI runs before pushing, rather than a partial subset:

```just
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
```

---

## 8. Documentation Framework

Architecture Spec §14.11 requires every public component to document purpose, responsibilities, inputs, outputs, constraints, and examples where appropriate, and prohibits undocumented public interfaces. This is enforced two ways, both already wired above:

1. **Structurally:** `#![warn(missing_docs)]` at every crate root (§4.7, §5.7), promoted to a build-breaking `-D warnings` in CI (§7.2's `RUSTFLAGS`/`RUSTDOCFLAGS`). It is not possible to merge a public item without a doc comment.
2. **Qualitatively:** every doc comment in §4 and §5 states purpose (what the item is), and, where non-obvious, *why* it exists in the terms of the Architecture Spec section it implements — matching §14.11's "purpose, responsibilities... constraints" requirement rather than restating the type signature in prose.

`cargo doc --workspace --no-deps --document-private-items` (§7.2) is the canonical way to render the documentation set locally; no external documentation site is stood up in Phase 1.

---

## 9. Exit Criteria (Checkable)

Architecture Spec §15.4 states Phase 1's exit criteria in prose. This section makes each one a specific, automatable check.

| §15.4 Exit Criterion | Concrete Check |
|---|---|
| "Project builds successfully." | `cargo check --workspace` exits 0 on the MSRV toolchain (CI job `msrv`, §7.2) and on stable (implied by every other job). |
| "CI pipeline operational." | All jobs in `.github/workflows/ci.yml` (§7.2) pass on a clean clone of `main`: `fmt`, `clippy`, `test`, `doc`, `audit`, `benchmark-regression` (placeholder), `msrv`. |
| "Documentation framework established." | `cargo doc --workspace --no-deps --document-private-items` succeeds with `RUSTDOCFLAGS="-D warnings"` (i.e. zero missing-doc warnings) and `#![warn(missing_docs)]` is present in every crate root. |
| "Coding standards enforced." | `cargo fmt --all -- --check` and `cargo clippy --workspace --all-targets -- -D warnings` both exit 0; `rustfmt.toml`, `clippy.toml`, and `deny.toml` (§3.3–§3.5) are present and referenced by CI; `[workspace.lints]` (§3.2) is inherited by both crates via `[lints] workspace = true`. |

Additional Phase-1-specific verification, beyond the letter of §15.4 but implied by §6.2A and §4.1 being load-bearing for every later phase:

| Requirement | Concrete Check |
|---|---|
| Mutability Tier traits match Appendix G exactly | `rasica_core::mutability::{Immutable, AppendOnly, ScopedMutable}` compile with the signatures in §5.3; `workspace_smoke` (§6.3) demonstrates a real type implementing `Immutable` alongside `Identifiable` and `DeterministicFingerprint`. |
| Fingerprinting is deterministic | `fingerprint::tests::identical_input_produces_identical_fingerprint` and the `proptest` property test in §5.4 pass. |
| No crate depends on an unimplemented crate | `cargo metadata` shows only `rasica-common`, `rasica-core`, and `workspace-smoke` as workspace members (§3.2); no `path` dependency in either crate's `Cargo.toml` points outside these three. |
| `unsafe` is absent | `#![forbid(unsafe_code)]` present in both crate roots (§4.7, §5.7); `cargo geiger` (optional, not gated in CI) reports zero unsafe usages if run. |

Phase 1 is complete when every row above is true on a single commit of `main`.

---

## 10. Traceability Matrix

| This Document | Architecture Spec Source |
|---|---|
| §2 (Engineering Baseline) | §14.5, §14.8–§14.10, §14.16, §4.1, §6.2A |
| §3 (Repository & Workspace) | §15.4 ("Cargo Workspace"), §14.6, §14.7, Appendix D |
| §4.3 (Primitive Types) | §15.4 ("Primitive types"), §14.16, Appendix G |
| §4.4 (Error Framework) | §15.4 ("Error framework"), §14.9 |
| §4.5 (Configuration Framework) | §15.4 ("Configuration framework"), §14.10 |
| §4.6 (Logging Framework) | §15.4 ("Logging framework"), §14.6 |
| §5.3 (Mutability Tiers) | §6.2A, Appendix G, Appendix G Type Authority Policy |
| §5.4 (Deterministic Fingerprinting) | §6.2A (caching rule), §4.1 (Numeric Determinism) |
| §6 (Testing Framework) | §15.4 ("Testing framework"), §14.13 |
| §7 (CI) | §15.4 ("Build pipeline"), §14.14 |
| §8 (Documentation Framework) | §14.11 |
| §9 (Exit Criteria) | §15.4 (Exit Criteria) |

---

## 11. Non-Goals and Forward Pointers

- **`Dataset` and the remaining Core Architectural Objects** (§6.4 onward) are Phase 2's responsibility (Architecture Spec §15.5, Appendix E item 04). They will implement `rasica_core::mutability::Immutable` and, where useful, `Identifiable`/`DeterministicFingerprint`, defined here.
- **The canonical Rust signatures for `DomainModule`, `Rule`, and related types** (Appendix G) are not implemented in Phase 1; only their shared prerequisites (`Id`, `SemVer`, `EngineVersionRange`, the tier markers) are. Appendix G's types are owned by Appendix E items 09 (Rule Engine) and 10 (Domain SDK).
- **Appendix H's Non-Functional Requirements Baseline** is not measured against in Phase 1, since it targets dataset-processing latency, memory ceilings, and lookup complexity — none of which exist yet. Phase 1's `benchmark-regression` CI job is intentionally a placeholder for this reason (§7.2).
- **`ScopedMutable`'s Tier 3 rules** (no promotion to Tier 1 by aliasing; caching keyed by fingerprint) are stated in §5.3's documentation but have no code to apply them to until the Execution Engine (Architecture Spec §15.17, Appendix E item 13) exists. Phase 1 provides the trait and the fingerprinting mechanism those rules will be built on.

---

*End of Document 00A. The next document in sequence is the Phase 2 Implementation Specification — Dataset Engine, which is the first consumer of `rasica_core::mutability::Immutable` and `rasica_core::identity::Identifiable` for a real Core Architectural Object (`Dataset`, Architecture Spec §6.4).*
