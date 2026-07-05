//! Convenience re-export of the types most consumers of
//! `rasica-validation` need, following the same convention as
//! `rasica_ingestion::prelude` (Phase 3).

pub use crate::{
    constraint::ValidationConstraint,
    error::ValidationError,
    finding::{FindingKind, Location, ValidationCategory, ValidationFinding},
    report::ValidationReport,
    validate::{validate, ValidationOptions},
    NullAnalysisOptions,
};
