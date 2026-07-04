//! The Metadata Core Architectural Object (Architecture Spec §6.5): the
//! structural description of a Dataset, derived solely from it.

use rasica_core::prelude::Immutable;

use crate::dataset::Dataset;

/// The per-column portion of [`Metadata`].
///
/// `distribution`, `scale`, and `temporal_properties` are `None` in every
/// `Metadata` produced by Phase 2 (see this document's §1.4 Note 1); they
/// exist on this type now so Phase 5 (Structural Inference) populates them
/// without changing `ColumnMetadata`'s public shape.
#[derive(Debug, Clone, PartialEq)]
pub struct ColumnMetadata {
    nullable: bool,
    unique: bool,
    distinct_count: u64,
    /// Populated by Phase 5. Always `None` in Phase 2.
    distribution: Option<()>,
    /// Populated by a future phase (not yet assigned a phase number in the
    /// roadmap). Always `None` in Phase 2.
    scale: Option<()>,
    /// Populated by a future phase (not yet assigned a phase number in the
    /// roadmap). Always `None` in Phase 2.
    temporal_properties: Option<()>,
}

impl ColumnMetadata {
    /// Returns whether the column contains at least one [`crate::value::Value::Null`].
    #[must_use]
    pub const fn nullable(&self) -> bool {
        self.nullable
    }

    /// Returns whether every non-null value in the column is distinct.
    #[must_use]
    pub const fn unique(&self) -> bool {
        self.unique
    }

    /// Returns the number of distinct non-null values in the column.
    #[must_use]
    pub const fn distinct_count(&self) -> u64 {
        self.distinct_count
    }
}

/// The structural description of a [`Dataset`] (Architecture Spec §6.5).
///
/// `Metadata` is Tier 1 (Immutable, §6.2A): once derived, it is never
/// updated in place. A later phase that learns more about a Dataset's
/// structure (e.g. Phase 5 filling in `ColumnMetadata::distribution`)
/// constructs a new `Metadata` value; it does not mutate this one, per
/// §6.2A's "any change requires constructing a new object with a new
/// identity."
#[derive(Debug, Clone, PartialEq)]
pub struct Metadata {
    columns: Vec<ColumnMetadata>,
}

impl Immutable for Metadata {}

impl Metadata {
    /// Derives `Metadata` from `dataset` by inspection alone (§6.5:
    /// "derived solely from the Dataset").
    ///
    /// This performs a single pass over every row for every column;
    /// callers processing very wide or very tall datasets against
    /// Appendix H's baseline should treat this as an O(rows × columns)
    /// operation with no shortcut in Phase 2 (Phase 5's inference logic is
    /// the appropriate place to introduce sampling or incremental
    /// strategies, should that become necessary).
    #[must_use]
    pub fn derive(dataset: &Dataset) -> Self {
        let columns = (0..dataset.schema().arity())
            .map(|position| {
                let mut seen = std::collections::HashSet::new();
                let mut nullable = false;

                for row in dataset.rows() {
                    match row.get(position) {
                        Some(crate::value::Value::Null) | None => nullable = true,
                        Some(other) => {
                            // `Value` is not `Eq`/`Hash` (it wraps `f64`),
                            // so distinctness is tracked via each value's
                            // deterministic fingerprint bytes rather than
                            // via `HashSet<Value>` directly. This reuses
                            // the same fingerprinting contract Document 00A
                            // §5.4 established, rather than inventing a
                            // second notion of "distinct."
                            use rasica_core::prelude::DeterministicFingerprint;
                            seen.insert(other.fingerprint());
                        }
                    }
                }

                let distinct_count = seen.len() as u64;
                let non_null_count = dataset
                    .rows()
                    .iter()
                    .filter(|r| !matches!(r.get(position), Some(crate::value::Value::Null) | None))
                    .count() as u64;

                ColumnMetadata {
                    nullable,
                    unique: distinct_count == non_null_count,
                    distinct_count,
                    distribution: None,
                    scale: None,
                    temporal_properties: None,
                }
            })
            .collect();

        Self { columns }
    }

    /// Returns per-column metadata, in schema column order.
    #[must_use]
    pub fn columns(&self) -> &[ColumnMetadata] {
        &self.columns
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        dataset::DatasetBuilder,
        row::Row,
        schema::{Column, ColumnType, Schema},
        source::{SourceFormat, SourceMetadata},
        value::Value,
    };

    use super::Metadata;

    #[test]
    #[allow(clippy::unwrap_used)]
    fn distinct_count_matches_actual_distinct_non_null_values() {
        let schema = Schema::new(vec![Column::new("n", ColumnType::Integer)]).unwrap();
        let mut builder = DatasetBuilder::new(schema);
        for v in [Value::Integer(1), Value::Integer(1), Value::Null, Value::Integer(2)] {
            builder.push_row(Row::new(vec![v])).unwrap();
        }
        let dataset = builder.build(SourceMetadata::new(SourceFormat::InMemory, "test"));

        let metadata = Metadata::derive(&dataset);
        let column = &metadata.columns()[0];
        assert!(column.nullable());
        assert_eq!(column.distinct_count(), 2);
        assert!(!column.unique()); // "1" appears twice
    }
}
