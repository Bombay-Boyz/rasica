//! Errors from `infer` (Architecture Spec §14.9; Document 00E §6).
//!
//! `infer` is otherwise infallible: once a Dataset has at least one row,
//! every column receives *some* `VariableRole` (including the
//! `Unclassified` catch-all, §5.6) and no heuristic can fail. The only
//! precondition `infer` itself enforces is a non-empty Dataset.

use thiserror::Error;

use rasica_common::error::{ErrorCode, ErrorSeverity, RasicaError};

/// Errors from calling [`crate::knowledge::infer`].
#[derive(Debug, Error, Clone, Copy, PartialEq, Eq)]
pub enum InferenceError {
    /// The Dataset has zero rows. No heuristic in this crate (§5) is
    /// meaningful without at least one row to observe, so `infer` rejects
    /// this case explicitly rather than producing a `StructuralKnowledge`
    /// of all-`Unclassified` columns that would misrepresent "nothing
    /// observed" as "observed and found unclassifiable".
    #[error("dataset has zero rows; structural inference requires at least one row")]
    EmptyDataset,
}

impl RasicaError for InferenceError {
    fn error_code(&self) -> ErrorCode {
        match self {
            Self::EmptyDataset => ErrorCode("structural_inference::empty_dataset"),
        }
    }

    fn severity(&self) -> ErrorSeverity {
        // Caught before any heuristic runs, i.e. before any
        // StructuralKnowledge exists — the same rationale
        // rasica-validation gives for its own ValidationError::severity
        // (Phase 4) and rasica-ingestion for IngestionError (Phase 3).
        ErrorSeverity::Recoverable
    }
}
