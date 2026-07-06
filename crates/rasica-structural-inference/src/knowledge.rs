//! `StructuralKnowledge` (Architecture Spec §6.7) and `infer`, this
//! crate's single entry point (§15.8).

use std::collections::HashSet;

use rasica_core::prelude::Immutable;
use rasica_dataset::{dataset::Dataset, value::Value};

use crate::{
    category::CategorySummary,
    dataset_view::{column_type, row_values, InferenceView},
    distribution::DistributionSummary,
    error::InferenceError,
    relationship::{detect_value_subset_evidence, RelationshipEvidence},
    role::{classify, VariableRole},
    value_key::ValueKey,
};

/// The Structural Knowledge Core Architectural Object (§6.7): everything
/// the Core Engine can determine about a Dataset without consulting
/// Domain Modules.
///
/// `StructuralKnowledge` is Tier 1 (Immutable, §6.2A): constructed
/// exclusively by [`infer`], never mutated afterward. There is no
/// currently-planned later phase that would revise an existing
/// `StructuralKnowledge` in place — Structural Inference is the terminal
/// producer of this object per §8.3 — so a future phase that learns more
/// about a Dataset's structure would construct a new value entirely,
/// mirroring `rasica-validation`'s own `ValidationReport` precedent
/// (Phase 4).
#[derive(Debug, Clone, PartialEq)]
pub struct StructuralKnowledge {
    origin: String,
    columns: Vec<ColumnKnowledge>,
    relationships: Vec<RelationshipEvidence>,
}

impl Immutable for StructuralKnowledge {}

impl StructuralKnowledge {
    /// The origin (e.g. source path or in-memory tag) of the Dataset this
    /// knowledge was inferred from, supplied by the caller of [`infer`]
    /// (mirroring `rasica-validation::ValidationReport::origin`, Phase 4).
    #[must_use]
    pub fn origin(&self) -> &str {
        &self.origin
    }

    /// Per-column knowledge, in the Dataset's own column order.
    #[must_use]
    pub fn columns(&self) -> &[ColumnKnowledge] {
        &self.columns
    }

    /// Per-column knowledge for the column at `index`, if any.
    #[must_use]
    pub fn column(&self, index: usize) -> Option<&ColumnKnowledge> {
        self.columns.get(index)
    }

    /// Every piece of pairwise relationship evidence found (§5.7), in
    /// deterministic order.
    #[must_use]
    pub fn relationships(&self) -> &[RelationshipEvidence] {
        &self.relationships
    }
}

/// The per-column portion of [`StructuralKnowledge`].
#[derive(Debug, Clone, PartialEq)]
pub struct ColumnKnowledge {
    role: VariableRole,
    distribution: Option<DistributionSummary>,
    categories: Option<CategorySummary>,
}

impl ColumnKnowledge {
    /// The single entry point for constructing a `ColumnKnowledge`,
    /// enforcing the invariant that `distribution` is `Some` if and only
    /// if `role` is [`VariableRole::Continuous`], and `categories` is
    /// `Some` if and only if `role` is [`VariableRole::Categorical`] —
    /// the same "one door in" convention `rasica_dataset::dataset::Dataset`
    /// uses via `DatasetBuilder` (Document 00E §4.5).
    fn new(
        role: VariableRole,
        distribution: Option<DistributionSummary>,
        categories: Option<CategorySummary>,
    ) -> Self {
        debug_assert_eq!(
            distribution.is_some(),
            role == VariableRole::Continuous,
            "distribution must be Some if and only if role is Continuous"
        );
        debug_assert_eq!(
            categories.is_some(),
            role == VariableRole::Categorical,
            "categories must be Some if and only if role is Categorical"
        );
        Self { role, distribution, categories }
    }

    /// This column's structural role.
    #[must_use]
    pub fn role(&self) -> VariableRole {
        self.role
    }

    /// `Some` if and only if [`Self::role`] is [`VariableRole::Continuous`].
    #[must_use]
    pub fn distribution(&self) -> Option<&DistributionSummary> {
        self.distribution.as_ref()
    }

    /// `Some` if and only if [`Self::role`] is [`VariableRole::Categorical`].
    #[must_use]
    pub fn categories(&self) -> Option<&CategorySummary> {
        self.categories.as_ref()
    }
}

#[allow(clippy::cast_precision_loss)] // Integer values here are far below f64's exact-integer ceiling.
fn as_f64(value: &Value) -> Option<f64> {
    match value {
        Value::Integer(i) => Some(*i as f64),
        Value::Float(f) => Some(*f),
        _ => None,
    }
}

/// Constructs [`StructuralKnowledge`] for `dataset`, by inspection alone
/// (§6.7: "without consulting Domain Modules").
///
/// `origin` is recorded on the result for traceability, supplied by the
/// caller rather than read off the Dataset, for the same reason
/// `rasica-validation::validate` takes an explicit `origin` parameter
/// (Phase 4): this crate depends on `rasica-dataset` alone and must not
/// assume any particular provenance-recording convention beyond it.
///
/// This performs one pass per column to resolve its [`VariableRole`]
/// (§5), immediately deriving that role's associated summary
/// ([`DistributionSummary`]/[`CategorySummary`]) in the same pass, plus
/// one pairwise comparison per `(Identifier, Identifier)` column pair
/// (§5.7).
///
/// # Errors
///
/// Returns [`InferenceError::EmptyDataset`] if `dataset` has zero rows —
/// see that variant's documentation for why this is rejected rather than
/// producing a `StructuralKnowledge` of all-`Unclassified` columns.
pub fn infer(
    dataset: &Dataset,
    origin: impl Into<String>,
) -> Result<StructuralKnowledge, InferenceError> {
    let row_count = dataset.row_count();
    if row_count == 0 {
        return Err(InferenceError::EmptyDataset);
    }

    let schema = dataset.schema();
    let arity = schema.arity();

    // Single pass: gather every column's non-null values, in row order,
    // as borrows into the Dataset's own storage (no cloning of cell data).
    let mut per_column_values: Vec<Vec<&Value>> = (0..arity).map(|_| Vec::new()).collect();
    for row in dataset.inference_rows() {
        for (index, value) in row_values(row).iter().enumerate() {
            if !matches!(value, Value::Null) {
                per_column_values[index].push(value);
            }
        }
    }

    let mut columns = Vec::with_capacity(arity);
    let mut identifier_columns: Vec<(usize, HashSet<ValueKey>)> = Vec::new();

    for (index, column) in schema.columns().iter().enumerate() {
        let this_column_type = column_type(column);
        let non_null_values = &per_column_values[index];
        let distinct: HashSet<ValueKey> =
            non_null_values.iter().map(|value| ValueKey::from(*value)).collect();
        let distinct_count = distinct.len();

        let role = classify(this_column_type, row_count, non_null_values, distinct_count);

        let distribution = (role == VariableRole::Continuous).then(|| {
            let numeric: Vec<f64> =
                non_null_values.iter().filter_map(|value| as_f64(value)).collect();
            DistributionSummary::derive(&numeric)
        });

        let categories =
            (role == VariableRole::Categorical).then(|| CategorySummary::derive(non_null_values));

        if role == VariableRole::Identifier {
            identifier_columns.push((index, distinct));
        }

        columns.push(ColumnKnowledge::new(role, distribution, categories));
    }

    let relationships = detect_value_subset_evidence(&identifier_columns);

    Ok(StructuralKnowledge { origin: origin.into(), columns, relationships })
}

#[cfg(test)]
mod tests {
    use super::*;
    use rasica_dataset::{
        dataset::DatasetBuilder,
        row::Row,
        schema::{Column, ColumnType, Schema},
        source::{SourceFormat, SourceMetadata},
    };

    #[allow(clippy::expect_used)]
    fn dataset_with_rows(col_type: ColumnType, values: Vec<Value>) -> Dataset {
        let schema =
            Schema::new(vec![Column::new("col", col_type)]).expect("schema is well-formed");
        let mut builder = DatasetBuilder::new(schema);
        for value in values {
            builder.push_row(Row::new(vec![value])).expect("row matches schema");
        }
        builder.build(SourceMetadata::new(SourceFormat::InMemory, "test"))
    }

    #[test]
    fn empty_dataset_is_rejected() {
        let dataset = dataset_with_rows(ColumnType::Integer, vec![]);
        assert_eq!(infer(&dataset, "test"), Err(InferenceError::EmptyDataset));
    }

    #[test]
    #[allow(clippy::expect_used)]
    fn continuous_column_carries_a_distribution_and_no_categories() {
        let values = (0..30).map(|i| Value::Float(f64::from(i))).collect();
        let dataset = dataset_with_rows(ColumnType::Float, values);
        let knowledge = infer(&dataset, "test").expect("non-empty dataset infers successfully");
        let column = knowledge.column(0).expect("column 0 exists");
        assert_eq!(column.role(), VariableRole::Continuous);
        assert!(column.distribution().is_some());
        assert!(column.categories().is_none());
    }

    #[test]
    #[allow(clippy::expect_used)]
    fn categorical_column_carries_categories_and_no_distribution() {
        let values =
            vec![Value::Text("a".into()), Value::Text("b".into()), Value::Text("a".into())];
        let dataset = dataset_with_rows(ColumnType::Text, values);
        let knowledge = infer(&dataset, "test").expect("non-empty dataset infers successfully");
        let column = knowledge.column(0).expect("column 0 exists");
        assert_eq!(column.role(), VariableRole::Categorical);
        assert!(column.categories().is_some());
        assert!(column.distribution().is_none());
    }

    #[test]
    #[allow(clippy::expect_used)]
    fn is_immutable_tier_1() {
        fn assert_immutable<T: Immutable>(_: &T) {}
        let dataset = dataset_with_rows(ColumnType::Integer, vec![Value::Integer(1)]);
        let knowledge = infer(&dataset, "test").expect("non-empty dataset infers successfully");
        assert_immutable(&knowledge);
    }

    #[test]
    #[allow(clippy::expect_used)]
    fn repeated_inference_over_the_same_dataset_is_deterministic() {
        let values = (0..25).map(Value::Integer).collect();
        let dataset = dataset_with_rows(ColumnType::Integer, values);
        let first = infer(&dataset, "test").expect("non-empty dataset infers successfully");
        for _ in 0..5 {
            let repeat = infer(&dataset, "test").expect("non-empty dataset infers successfully");
            assert_eq!(first, repeat);
        }
    }
}
