//! Errors produced while constructing a `Dataset` (Architecture Spec
//! §14.9; Document 00A §4.4).

use thiserror::Error;

use rasica_common::error::{ErrorCode, ErrorSeverity, RasicaError};

/// Errors from [`crate::dataset::DatasetBuilder`].
#[derive(Debug, Error, PartialEq, Eq)]
pub enum DatasetError {
    /// A row was pushed whose length did not match the schema's arity.
    #[error("row has {actual} values but the schema declares {expected} columns")]
    RowArityMismatch {
        /// The schema's declared arity.
        expected: usize,
        /// The row's actual length.
        actual: usize,
    },

    /// A row was pushed with a value whose type disagreed with its
    /// column's declared type.
    #[error("value at column '{column}' (position {position}) does not match its declared type")]
    RowTypeMismatch {
        /// The offending column's name.
        column: String,
        /// The offending column's ordinal position.
        position: usize,
    },
}

impl RasicaError for DatasetError {
    fn error_code(&self) -> ErrorCode {
        match self {
            Self::RowArityMismatch { .. } => ErrorCode("dataset::row_arity_mismatch"),
            Self::RowTypeMismatch { .. } => ErrorCode("dataset::row_type_mismatch"),
        }
    }

    fn severity(&self) -> ErrorSeverity {
        // Both conditions are caught before `DatasetBuilder::build` is
        // called, i.e. before any Tier 1 `Dataset` exists — no
        // already-constructed Core Architectural Object is put at risk,
        // matching `ConfigError`'s rationale in Document 00A §4.4.2.
        ErrorSeverity::Recoverable
    }
}
