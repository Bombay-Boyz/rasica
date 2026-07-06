//! `rasica-structural-inference`: the Structural Inference Engine
//! (Architecture Spec §9.3, §15.8) — deterministic identification of
//! identifiers, continuous/categorical/temporal variables, distributions,
//! and relationship evidence, over an already-constructed
//! `rasica_dataset::Dataset`, producing immutable Structural Knowledge
//! (§6.7).
//!
//! Depends only on `rasica-common`, `rasica-core`, and `rasica-dataset` —
//! never on `rasica-validation` (§6.7 defines Structural Knowledge as
//! derived from the Dataset alone) and never on any Domain Module (§6.7:
//! "without consulting Domain Modules"). See Document 00E §0 for the
//! dependency-graph rationale.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod category;
mod dataset_view;
pub mod distribution;
pub mod error;
pub mod knowledge;
pub mod prelude;
pub mod relationship;
pub mod role;
mod temporal_format;
mod value_key;

pub use knowledge::{infer, ColumnKnowledge, StructuralKnowledge};
pub use role::VariableRole;
