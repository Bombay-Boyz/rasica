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
    #[allow(clippy::result_large_err)]
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
#[allow(clippy::expect_used)]
pub fn schema_engine_version() -> EngineVersion {
    EngineVersion::new(
        crate::version::SemVer::parse(env!("CARGO_PKG_VERSION"))
            .expect("CARGO_PKG_VERSION is set by Cargo and is always a valid semver string"),
    )
}
