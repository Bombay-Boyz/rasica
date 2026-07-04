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
