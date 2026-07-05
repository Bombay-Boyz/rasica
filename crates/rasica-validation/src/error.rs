//! Errors produced while configuring a validation run (Architecture Spec
//! §14.9; Document 00A §4.4).
//!
//! Running `validate` itself is infallible by design — a Dataset always
//! yields a Validation Report, recording whatever it found (§6.6);
//! failure here means a caller misconfigured the run itself, before any
//! check touched a Dataset.

use thiserror::Error;

use rasica_common::error::{ErrorCode, ErrorSeverity, RasicaError};

/// Errors from configuring a validation run.
#[derive(Debug, Error, Clone, Copy, PartialEq)]
pub enum ValidationError {
    /// A threshold parameter was outside its required `[0.0, 1.0]` range.
    #[error("threshold {value} is not within [0.0, 1.0]")]
    InvalidThreshold {
        /// The rejected value.
        value: f64,
    },
}

impl RasicaError for ValidationError {
    fn error_code(&self) -> ErrorCode {
        match self {
            Self::InvalidThreshold { .. } => ErrorCode("validation::invalid_threshold"),
        }
    }

    fn severity(&self) -> ErrorSeverity {
        // Caught before any check runs against a Dataset, i.e. before any
        // Validation Report exists — the same rationale `rasica-ingestion`
        // gives for its own `IngestionError::severity` (Phase 3).
        ErrorSeverity::Recoverable
    }
}
