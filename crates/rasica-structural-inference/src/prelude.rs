//! Convenience re-export of the types most consumers of
//! `rasica-structural-inference` need, following the same convention as
//! `rasica_validation::prelude` (Phase 4).

pub use crate::{
    category::{CategoryCount, CategorySummary},
    distribution::DistributionSummary,
    error::InferenceError,
    knowledge::{infer, ColumnKnowledge, StructuralKnowledge},
    relationship::{ColumnRef, RelationshipEvidence, RelationshipKind},
    role::VariableRole,
};
