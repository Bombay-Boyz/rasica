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
