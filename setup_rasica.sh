#!/usr/bin/env bash
# Scaffolds the RASICA Phase 1 (Core Foundation) workspace exactly per
# 00A-Phase1-Core-Foundation-Implementation-Spec.md.
#
# Usage:
#   Run this from INSIDE the existing `rasica/` project folder you already
#   created with `cargo new`. It will remove the old single-crate `src/`
#   and `Cargo.toml` and replace them with the Phase 1 workspace layout.
#
#   chmod +x setup_rasica.sh
#   ./setup_rasica.sh

set -euo pipefail

if [ ! -d ".git" ] && [ ! -f "Cargo.toml" ]; then
  echo "Warning: this doesn't look like your rasica project root (no Cargo.toml/.git found)."
  echo "Run this script from inside the 'rasica' folder you created with 'cargo new'."
  read -rp "Continue anyway? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || exit 1
fi

echo "==> Removing old single-crate scaffold (if present)..."
rm -rf src
rm -f Cargo.toml Cargo.lock

echo "==> Creating directory structure..."
mkdir -p .github/workflows
mkdir -p architecture
mkdir -p specifications
mkdir -p crates/rasica-common/src/config
mkdir -p crates/rasica-core/src
mkdir -p tests/workspace_smoke/tests

# ---------------------------------------------------------------------------
# Workspace root
# ---------------------------------------------------------------------------

echo "==> Writing workspace root Cargo.toml..."
cat > Cargo.toml << 'EOF'
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
EOF

echo "==> Writing rustfmt.toml..."
cat > rustfmt.toml << 'EOF'
edition = "2021"
max_width = 100
use_small_heuristics = "Max"
imports_granularity = "Crate"
group_imports = "StdExternalCrate"
wrap_comments = true
comment_width = 100
format_code_in_doc_comments = true
EOF

echo "==> Writing clippy.toml..."
cat > clippy.toml << 'EOF'
# Complexity thresholds kept at defaults deliberately; Phase 1 introduces no
# complex control flow. Revisit only with a documented justification (§14.7).
too-many-arguments-threshold = 6
type-complexity-threshold = 250
EOF

echo "==> Writing deny.toml..."
cat > deny.toml << 'EOF'
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
EOF

echo "==> Writing nextest.toml..."
cat > nextest.toml << 'EOF'
[profile.default]
retries = 0
slow-timeout = { period = "30s", terminate-after = 2 }
failure-output = "immediate-final"

[profile.ci]
retries = 2
fail-fast = false
EOF

echo "==> Writing .rust-version..."
cat > .rust-version << 'EOF'
1.78.0
EOF

echo "==> Writing justfile..."
cat > justfile << 'EOF'
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
EOF

echo "==> Writing README.md..."
cat > README.md << 'EOF'
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
EOF

# ---------------------------------------------------------------------------
# rasica-common
# ---------------------------------------------------------------------------

echo "==> Writing crates/rasica-common/Cargo.toml..."
cat > crates/rasica-common/Cargo.toml << 'EOF'
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
EOF

echo "==> Writing crates/rasica-common/src/id.rs..."
cat > crates/rasica-common/src/id.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-common/src/version.rs..."
cat > crates/rasica-common/src/version.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-common/src/error.rs..."
cat > crates/rasica-common/src/error.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-common/src/config/error.rs..."
cat > crates/rasica-common/src/config/error.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-common/src/config/mod.rs..."
cat > crates/rasica-common/src/config/mod.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-common/src/config/layers.rs..."
cat > crates/rasica-common/src/config/layers.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-common/src/logging.rs..."
cat > crates/rasica-common/src/logging.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-common/src/lib.rs..."
cat > crates/rasica-common/src/lib.rs << 'EOF'
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
EOF

# ---------------------------------------------------------------------------
# rasica-core
# ---------------------------------------------------------------------------

echo "==> Writing crates/rasica-core/Cargo.toml..."
cat > crates/rasica-core/Cargo.toml << 'EOF'
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
EOF

echo "==> Writing crates/rasica-core/src/mutability.rs..."
cat > crates/rasica-core/src/mutability.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-core/src/fingerprint.rs..."
cat > crates/rasica-core/src/fingerprint.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-core/src/identity.rs..."
cat > crates/rasica-core/src/identity.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-core/src/prelude.rs..."
cat > crates/rasica-core/src/prelude.rs << 'EOF'
//! Convenience re-export of the vocabulary every Core Architectural Object
//! implementation needs. Later crates are expected to write
//! `use rasica_core::prelude::*;` rather than importing each item
//! individually.

pub use crate::{
    fingerprint::{DeterministicFingerprint, Fingerprint},
    identity::Identifiable,
    mutability::{AppendOnly, Immutable, ScopedMutable},
};
EOF

echo "==> Writing crates/rasica-core/src/lib.rs..."
cat > crates/rasica-core/src/lib.rs << 'EOF'
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
EOF

# ---------------------------------------------------------------------------
# tests/workspace_smoke
# ---------------------------------------------------------------------------

echo "==> Writing tests/workspace_smoke/Cargo.toml..."
cat > tests/workspace_smoke/Cargo.toml << 'EOF'
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
EOF

echo "==> Writing tests/workspace_smoke/tests/smoke.rs..."
cat > tests/workspace_smoke/tests/smoke.rs << 'EOF'
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
EOF

# ---------------------------------------------------------------------------
# CI
# ---------------------------------------------------------------------------

echo "==> Writing .github/workflows/ci.yml..."
cat > .github/workflows/ci.yml << 'CIEOF'
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
CIEOF

echo ""
echo "==> Done. Workspace scaffolded."
echo ""
echo "Next steps:"
echo "  1. Copy your architecture/spec docs into architecture/ and specifications/ (optional, referenced by README)."
echo "  2. cargo check --workspace"
echo "  3. cargo nextest run --workspace   (install with: cargo install cargo-nextest)"
echo "  4. cargo clippy --workspace --all-targets -- -D warnings"
echo "  5. cargo fmt --all"
