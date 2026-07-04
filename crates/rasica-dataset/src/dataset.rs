//! The Dataset Core Architectural Object (Architecture Spec §6.4): the
//! immutable internal representation of ingested data.

use rasica_common::Id;
use rasica_core::prelude::{DeterministicFingerprint, Identifiable, Immutable};

use crate::{error::DatasetError, row::Row, schema::Schema, source::SourceMetadata};

/// Marker type for [`Id<DatasetMarker>`], per Document 00A §4.3.1's phantom-typed
/// identifier pattern.
pub struct DatasetMarker;

/// The immutable internal representation of ingested data (Architecture
/// Spec §6.4).
///
/// A `Dataset` is constructed exclusively via [`DatasetBuilder`]; once
/// built, it exposes no method capable of mutating its rows or schema,
/// satisfying its Tier 1 (Immutable, §6.2A) classification.
#[derive(Debug, Clone)]
pub struct Dataset {
    id: Id<DatasetMarker>,
    schema: Schema,
    rows: Vec<Row>,
    source: SourceMetadata,
}

impl Immutable for Dataset {}

impl Identifiable for Dataset {
    type Marker = DatasetMarker;

    fn id(&self) -> Id<Self::Marker> {
        self.id
    }
}

impl DeterministicFingerprint for Dataset {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        // Excludes `id` (identity, not content — see Document 00A §5.4's
        // `ExampleImmutableObject`) and `source` (provenance, not content
        // — see §4.5 of this document). Two datasets with identical schema
        // and rows fingerprint identically regardless of identity or
        // origin, so a Tier 3 cache keyed on this fingerprint (§6.2A) is
        // correctly shared between them.
        let mut bytes = self.schema.fingerprint_bytes();
        bytes.extend(self.rows.iter().flat_map(DeterministicFingerprint::fingerprint_bytes));
        bytes
    }
}

impl Dataset {
    /// Returns the dataset's schema.
    #[must_use]
    pub const fn schema(&self) -> &Schema {
        &self.schema
    }

    /// Returns the dataset's rows, in insertion order.
    #[must_use]
    pub fn rows(&self) -> &[Row] {
        &self.rows
    }

    /// Returns the dataset's source provenance.
    #[must_use]
    pub const fn source(&self) -> &SourceMetadata {
        &self.source
    }

    /// Returns the number of rows in the dataset.
    #[must_use]
    pub fn row_count(&self) -> usize {
        self.rows.len()
    }
}

/// Constructs a [`Dataset`] one row at a time, enforcing structural
/// well-formedness (row arity and per-value type agreement with the
/// [`Schema`]) as each row is added.
///
/// This is a structural check, not validation in the Architecture Spec
/// §6.4/§9.1 sense: it enforces that a `Dataset` can only ever represent
/// rows that are *well-formed with respect to its own declared schema* —
/// the same kind of invariant [`Schema::new`] enforces on column names.
/// It makes no judgement about whether the *content* of a well-formed row
/// is meaningful, permitted, or expected; that judgement belongs to the
/// Validation Engine (Phase 4, Architecture Spec §9.2).
///
/// `DatasetBuilder` itself implements none of `rasica-core`'s Tier
/// traits: it is not a Core Architectural Object, only the mutable scratch
/// space used to construct one. Architecture Spec §6.2A's tiers apply to
/// `Dataset` from the moment [`DatasetBuilder::build`] returns it, not
/// before.
#[derive(Debug)]
pub struct DatasetBuilder {
    schema: Schema,
    rows: Vec<Row>,
}

impl DatasetBuilder {
    /// Starts building a dataset conforming to `schema`.
    #[must_use]
    pub fn new(schema: Schema) -> Self {
        Self { schema, rows: Vec::new() }
    }

    /// Appends `row`, after checking its arity and per-value types agree
    /// with the schema.
    ///
    /// # Errors
    ///
    /// Returns [`DatasetError::RowArityMismatch`] if `row`'s length does
    /// not equal [`Schema::arity`], or [`DatasetError::RowTypeMismatch`]
    /// if any non-null value's type disagrees with its column's declared
    /// [`crate::schema::ColumnType`].
    ///
    /// # Panics
    ///
    /// Never panics under normal use: the internal `.expect()` on
    /// `row.get(position)` is unreachable because `position` only ever
    /// ranges over indices already checked to be within `row`'s length
    /// by the arity check earlier in this function.
    #[allow(clippy::expect_used)]
    pub fn push_row(&mut self, row: Row) -> Result<&mut Self, DatasetError> {
        if row.arity() != self.schema.arity() {
            return Err(DatasetError::RowArityMismatch {
                expected: self.schema.arity(),
                actual: row.arity(),
            });
        }

        for (position, column) in self.schema.columns().iter().enumerate() {
            let value =
                row.get(position).expect("arity was checked equal to schema.columns().len() above");
            if !crate::value_matches_type(value, column.column_type()) {
                return Err(DatasetError::RowTypeMismatch {
                    column: column.name().to_owned(),
                    position,
                });
            }
        }

        self.rows.push(row);
        Ok(self)
    }

    /// Freezes the builder into an immutable [`Dataset`], attaching
    /// `source` as its provenance.
    #[must_use]
    pub fn build(self, source: SourceMetadata) -> Dataset {
        Dataset { id: Id::new(), schema: self.schema, rows: self.rows, source }
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        schema::{Column, ColumnType, Schema},
        source::{SourceFormat, SourceMetadata},
        value::Value,
    };

    use super::{DatasetBuilder, Row};

    proptest::proptest! {
        #[test]
        #[allow(clippy::unwrap_used)]
        fn datasets_with_equal_content_fingerprint_equally_regardless_of_identity(
            a in 0i64..1000, b in 0i64..1000
        ) {
            use rasica_core::prelude::DeterministicFingerprint;

            let build = |v: i64| {
                let schema = Schema::new(vec![Column::new("n", ColumnType::Integer)]).unwrap();
                let mut builder = DatasetBuilder::new(schema);
                builder.push_row(Row::new(vec![Value::Integer(v)])).unwrap();
                builder.build(SourceMetadata::new(SourceFormat::InMemory, "prop-test"))
            };

            if a == b {
                proptest::prop_assert_eq!(build(a).fingerprint(), build(b).fingerprint());
            } else {
                proptest::prop_assert_ne!(build(a).fingerprint(), build(b).fingerprint());
            }
        }
    }
}
