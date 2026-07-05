//! `rasica-validation`: the Validation Engine (Architecture Spec §9.2,
//! §15.7) — schema, datatype, integrity, null-analysis, duplicate, and
//! domain-contributed-constraint checks against an already-constructed
//! `rasica_dataset::Dataset`, producing an immutable Validation Report
//! (§6.6).
//!
//! Depends only on `rasica-common`, `rasica-core`, and `rasica-dataset`
//! — never on any Domain Module (§8.9, "Validation → Domain: Validation
//! is structural, not semantic"). `constraint::ValidationConstraint` is
//! this crate's own type, authoritative for the identically-named
//! parameter of the future `DomainModule::contribute_validation`
//! (Appendix G) — see that module's docs for the Type Authority Policy
//! rationale.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod constraint;
mod dataset_view;
mod datatype_check;
mod duplicate_detection;
pub mod error;
pub mod finding;
mod integrity_check;
mod null_analysis;
pub mod prelude;
pub mod report;
mod schema_check;
mod validate;
mod value_key;

pub use null_analysis::NullAnalysisOptions;
pub use validate::{validate, ValidationOptions};
