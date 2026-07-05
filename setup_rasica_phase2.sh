#!/usr/bin/env bash
# Adds Phase 2 (Dataset Engine) to an existing RASICA Phase 1 workspace, per
# 00B-Phase2-Dataset-Engine-Implementation-Spec.md.
#
# This script is ADDITIVE: it does not delete or overwrite any Phase 1 file.
# It creates the new `rasica-dataset` crate, and it PATCHES three existing
# files (root Cargo.toml, tests/workspace_smoke/Cargo.toml,
# tests/workspace_smoke/tests/smoke.rs, .github/workflows/ci.yml) by
# inserting the specific lines Phase 2 requires. Patches are idempotent —
# running the script twice will not duplicate insertions.
#
# Usage: run from the rasica/ project root (the folder containing the
# workspace root Cargo.toml).
#
#   chmod +x setup_rasica_phase2.sh
#   ./setup_rasica_phase2.sh

set -euo pipefail

if [ ! -f "Cargo.toml" ] || ! grep -q "\[workspace\]" Cargo.toml; then
  echo "Error: no workspace root Cargo.toml found here."
  echo "Run this from inside the 'rasica' folder that already has Phase 1 set up."
  exit 1
fi

if [ ! -d "crates/rasica-common" ] || [ ! -d "crates/rasica-core" ]; then
  echo "Error: crates/rasica-common and crates/rasica-core must already exist (Phase 1)."
  exit 1
fi

echo "==> Creating crates/rasica-dataset directory structure..."
mkdir -p crates/rasica-dataset/src
mkdir -p crates/rasica-dataset/benches

# ---------------------------------------------------------------------------
# Patch: workspace root Cargo.toml
# ---------------------------------------------------------------------------

echo "==> Patching root Cargo.toml (add rasica-dataset member + criterion dep)..."

if ! grep -q '"crates/rasica-dataset"' Cargo.toml; then
  python3 - << 'PYEOF'
import re

with open("Cargo.toml") as f:
    content = f.read()

content = content.replace(
    '    "crates/rasica-core",\n    "tests/workspace_smoke",',
    '    "crates/rasica-core",\n    "crates/rasica-dataset",\n    "tests/workspace_smoke",',
)

content = content.replace(
    'rstest = "0.19"',
    'rstest = "0.19"\n\n# --- benchmarking (§14.15; first real consumer: rasica-dataset benches) ---\ncriterion = { version = "0.5", features = ["html_reports"] }',
)

with open("Cargo.toml", "w") as f:
    f.write(content)
PYEOF
else
  echo "    (already patched, skipping)"
fi

# ---------------------------------------------------------------------------
# rasica-dataset crate
# ---------------------------------------------------------------------------

echo "==> Writing crates/rasica-dataset/Cargo.toml..."
cat > crates/rasica-dataset/Cargo.toml << 'EOF'
[package]
name = "rasica-dataset"
description = "The immutable internal Dataset representation and its supporting Schema, Row, and Metadata types."
version.workspace = true
edition.workspace = true
rust-version.workspace = true
authors.workspace = true
license.workspace = true
repository.workspace = true
publish.workspace = true

[lints]
workspace = true

[dependencies]
rasica-common = { path = "../rasica-common", version = "0.1.0" }
rasica-core = { path = "../rasica-core", version = "0.1.0" }
thiserror = { workspace = true }

[dev-dependencies]
proptest = { workspace = true }
rstest = { workspace = true }
criterion = { workspace = true }

[[bench]]
name = "dataset_construction"
harness = false
EOF

echo "==> Writing crates/rasica-dataset/src/schema.rs..."
cat > crates/rasica-dataset/src/schema.rs << 'EOF'
//! The closed, ordered column list a `Dataset` conforms to
//! (Architecture Spec §6.4, "columns").

use std::collections::HashSet;

use thiserror::Error;

/// The declared type of every value in a [`Column`].
///
/// This is a closed, structural vocabulary — the exact type a value is
/// *represented as* — and carries no semantic interpretation. Whether an
/// `Integer` column is actually a categorical code, or a `Text` column is
/// actually a date, is a Structural Inference concern (Architecture Spec
/// §6.7, Phase 5), not a Schema concern.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ColumnType {
    /// A 64-bit signed integer value.
    Integer,
    /// A 64-bit floating-point value.
    Float,
    /// A boolean value.
    Boolean,
    /// A UTF-8 text value.
    Text,
}

/// One column's name and declared type.
///
/// `Column` does not carry a value; it describes a position in every
/// [`crate::row::Row`] belonging to a [`Schema`] that includes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Column {
    name: String,
    column_type: ColumnType,
}

impl Column {
    /// Declares a new column with the given name and type.
    #[must_use]
    pub fn new(name: impl Into<String>, column_type: ColumnType) -> Self {
        Self {
            name: name.into(),
            column_type,
        }
    }

    /// Returns the column's name.
    #[must_use]
    pub fn name(&self) -> &str {
        &self.name
    }

    /// Returns the column's declared type.
    #[must_use]
    pub const fn column_type(&self) -> ColumnType {
        self.column_type
    }
}

/// Errors that can occur while constructing a [`Schema`].
#[derive(Debug, Error, PartialEq, Eq)]
pub enum SchemaError {
    /// Two or more columns were declared with the same name.
    #[error("duplicate column name '{name}'")]
    DuplicateColumnName {
        /// The name that appeared more than once.
        name: String,
    },
    /// A schema with zero columns was constructed.
    ///
    /// A `Dataset` "represents rows, columns, [and] values" (Architecture
    /// Spec §6.4); a schema with no columns can represent no values, so it
    /// is rejected as a structural malformation rather than as a valid
    /// zero-column dataset.
    #[error("a schema must declare at least one column")]
    Empty,
}

/// The closed, ordered list of [`Column`]s every [`crate::row::Row`] in a
/// [`Dataset`](crate::dataset::Dataset) conforms to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Schema {
    columns: Vec<Column>,
}

impl Schema {
    /// Constructs a `Schema` from an ordered list of columns.
    ///
    /// # Errors
    ///
    /// Returns [`SchemaError::Empty`] if `columns` is empty, or
    /// [`SchemaError::DuplicateColumnName`] if any two columns share a name.
    pub fn new(columns: Vec<Column>) -> Result<Self, SchemaError> {
        if columns.is_empty() {
            return Err(SchemaError::Empty);
        }

        let mut seen = HashSet::with_capacity(columns.len());
        for column in &columns {
            if !seen.insert(column.name()) {
                return Err(SchemaError::DuplicateColumnName {
                    name: column.name().to_owned(),
                });
            }
        }

        Ok(Self { columns })
    }

    /// Returns the number of columns in this schema.
    #[must_use]
    pub fn arity(&self) -> usize {
        self.columns.len()
    }

    /// Returns the columns in declaration order.
    #[must_use]
    pub fn columns(&self) -> &[Column] {
        &self.columns
    }

    /// Returns the ordinal position of the column named `name`, if present.
    #[must_use]
    pub fn position_of(&self, name: &str) -> Option<usize> {
        self.columns.iter().position(|c| c.name() == name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_empty_schema() {
        assert_eq!(Schema::new(vec![]), Err(SchemaError::Empty));
    }

    #[test]
    fn rejects_duplicate_column_names() {
        let result = Schema::new(vec![
            Column::new("a", ColumnType::Integer),
            Column::new("a", ColumnType::Text),
        ]);
        assert_eq!(
            result,
            Err(SchemaError::DuplicateColumnName { name: "a".into() })
        );
    }

    #[test]
    fn accepts_well_formed_schema() {
        let schema = Schema::new(vec![
            Column::new("id", ColumnType::Integer),
            Column::new("label", ColumnType::Text),
        ])
        .expect("two distinctly named columns is a well-formed schema");
        assert_eq!(schema.arity(), 2);
        assert_eq!(schema.position_of("label"), Some(1));
    }
}
EOF

echo "==> Writing crates/rasica-dataset/src/value.rs..."
cat > crates/rasica-dataset/src/value.rs << 'EOF'
//! A single cell value, typed according to `ColumnType` (§4.3 of this
//! document).

use rasica_core::prelude::DeterministicFingerprint;

/// One value in one cell of a [`crate::row::Row`].
///
/// `Value::Null` is a distinct variant, not the absence of a `Value`,
/// because nullability itself is a fact `Metadata` (§4.5) records per
/// column — a `Row` must therefore be able to represent "this cell is
/// null" explicitly rather than by omission.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    /// No value is present.
    Null,
    /// A 64-bit signed integer.
    Integer(i64),
    /// A 64-bit floating-point number.
    ///
    /// Equality on this variant follows `PartialEq` on `f64`, including
    /// `NaN != NaN`; no domain semantics (e.g. "treat NaN as missing") are
    /// applied here (Architecture Spec §6.4: the Dataset is not responsible
    /// for semantic interpretation).
    Float(f64),
    /// A boolean.
    Boolean(bool),
    /// UTF-8 text.
    Text(String),
}

impl DeterministicFingerprint for Value {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        // Each variant is prefixed with a distinct tag byte so that, e.g.,
        // `Integer(0)` and `Boolean(false)` — which could otherwise collide
        // on their payload bytes alone — fingerprint differently. This is
        // the same "injective with respect to logical equality" contract
        // Document 00A §5.4 places on every `DeterministicFingerprint`
        // implementation.
        match self {
            Self::Null => vec![0u8],
            Self::Integer(v) => [&[1u8][..], &v.to_le_bytes()].concat(),
            Self::Float(v) => [&[2u8][..], &v.to_le_bytes()].concat(),
            Self::Boolean(v) => vec![3u8, u8::from(*v)],
            Self::Text(v) => [&[4u8][..], v.as_bytes()].concat(),
        }
    }
}
EOF

echo "==> Writing crates/rasica-dataset/src/row.rs..."
cat > crates/rasica-dataset/src/row.rs << 'EOF'
//! A single row: one [`Value`] per column of the [`crate::schema::Schema`]
//! it was constructed against.

use rasica_core::prelude::DeterministicFingerprint;

use crate::value::Value;

/// One row of a [`Dataset`](crate::dataset::Dataset).
///
/// A `Row` does not carry its own copy of the [`crate::schema::Schema`] it
/// belongs to (that would duplicate the schema once per row, contradicting
/// Architecture Spec §6.4's "columns" being a Dataset-level, not row-level,
/// responsibility). Arity is checked once, at
/// [`DatasetBuilder::push_row`](crate::dataset::DatasetBuilder::push_row)
/// time, against the `Dataset`'s single `Schema`.
#[derive(Debug, Clone, PartialEq)]
pub struct Row(Vec<Value>);

impl Row {
    /// Constructs a row from an ordered list of values.
    ///
    /// This constructor performs no arity or type checking against any
    /// schema; that check is the responsibility of
    /// [`DatasetBuilder::push_row`](crate::dataset::DatasetBuilder::push_row),
    /// the single point at which a `Row` and a `Schema` are brought
    /// together.
    #[must_use]
    pub fn new(values: Vec<Value>) -> Self {
        Self(values)
    }

    /// Returns the number of values in this row.
    #[must_use]
    pub fn arity(&self) -> usize {
        self.0.len()
    }

    /// Returns the value at `position`, if present.
    #[must_use]
    pub fn get(&self, position: usize) -> Option<&Value> {
        self.0.get(position)
    }

    /// Returns the row's values in order.
    #[must_use]
    pub fn values(&self) -> &[Value] {
        &self.0
    }
}

impl DeterministicFingerprint for Row {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        self.0
            .iter()
            .flat_map(DeterministicFingerprint::fingerprint_bytes)
            .collect()
    }
}
EOF

echo "==> Writing crates/rasica-dataset/src/source.rs..."
cat > crates/rasica-dataset/src/source.rs << 'EOF'
//! Provenance information about where a Dataset's content came from
//! (Architecture Spec §6.4, "source metadata").

/// The external format a `Dataset`'s content was constructed from, or
/// [`SourceFormat::InMemory`] if it was constructed directly.
///
/// This is a closed enumeration matching Architecture Spec §6.4's example
/// list of supported external sources exactly. Phase 2 defines the
/// vocabulary; Phase 3 (Data Ingestion, §15.6) implements a reader for each
/// variant other than `InMemory`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SourceFormat {
    /// Comma-separated values.
    Csv,
    /// A Microsoft Excel workbook.
    Excel,
    /// JSON.
    Json,
    /// A SQL query result set.
    Sql,
    /// Apache Arrow.
    Arrow,
    /// Apache Parquet.
    Parquet,
    /// Constructed directly in-process, with no external source.
    InMemory,
}

/// Provenance information attached to a [`Dataset`](crate::dataset::Dataset).
///
/// `SourceMetadata` is deliberately excluded from `Dataset`'s
/// `DeterministicFingerprint` (§4.6): two datasets with byte-identical
/// schema and rows are the same *content* regardless of which format they
/// happened to be read from, and a Tier 3 cache keyed on that fingerprint
/// (Architecture Spec §6.2A) should treat them as the same cache key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceMetadata {
    format: SourceFormat,
    origin: String,
}

impl SourceMetadata {
    /// Records that a `Dataset` came from `format`, originating at
    /// `origin` (a file path, URI, connection descriptor, or `"in-memory"`
    /// — the exact convention is owned by whichever Phase 3 reader
    /// populates it; Phase 2 imposes no structure on the string itself).
    #[must_use]
    pub fn new(format: SourceFormat, origin: impl Into<String>) -> Self {
        Self {
            format,
            origin: origin.into(),
        }
    }

    /// Returns the source format.
    #[must_use]
    pub const fn format(&self) -> SourceFormat {
        self.format
    }

    /// Returns the origin descriptor.
    #[must_use]
    pub fn origin(&self) -> &str {
        &self.origin
    }
}
EOF

echo "==> Writing crates/rasica-dataset/src/metadata.rs..."
cat > crates/rasica-dataset/src/metadata.rs << 'EOF'
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
        dataset::DatasetBuilder, row::Row, schema::{Column, ColumnType, Schema},
        source::{SourceFormat, SourceMetadata}, value::Value,
    };

    use super::Metadata;

    #[test]
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
EOF

echo "==> Writing crates/rasica-dataset/src/dataset.rs..."
cat > crates/rasica-dataset/src/dataset.rs << 'EOF'
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
        bytes.extend(
            self.rows
                .iter()
                .flat_map(DeterministicFingerprint::fingerprint_bytes),
        );
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
        Self {
            schema,
            rows: Vec::new(),
        }
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
    pub fn push_row(&mut self, row: Row) -> Result<&mut Self, DatasetError> {
        if row.arity() != self.schema.arity() {
            return Err(DatasetError::RowArityMismatch {
                expected: self.schema.arity(),
                actual: row.arity(),
            });
        }

        for (position, column) in self.schema.columns().iter().enumerate() {
            let value = row
                .get(position)
                .expect("arity was checked equal to schema.columns().len() above");
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
        Dataset {
            id: Id::new(),
            schema: self.schema,
            rows: self.rows,
            source,
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::{
        schema::{Column, ColumnType, Schema}, source::{SourceFormat, SourceMetadata}, value::Value,
    };

    use super::{DatasetBuilder, Row};

    proptest::proptest! {
        #[test]
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
EOF

echo "==> Writing crates/rasica-dataset/src/error.rs..."
cat > crates/rasica-dataset/src/error.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-dataset/src/lib.rs..."
cat > crates/rasica-dataset/src/lib.rs << 'EOF'
//! `rasica-dataset`: the immutable internal Dataset representation
//! (Architecture Spec §6.4) and its supporting Schema, Row, Value, Source,
//! and Metadata types.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod dataset;
pub mod error;
pub mod metadata;
pub mod prelude;
pub mod row;
pub mod schema;
pub mod source;
pub mod value;

use crate::{schema::ColumnType, value::Value};

/// Returns whether `value` agrees with `column_type`, treating
/// [`Value::Null`] as agreeing with every type (nullability is a
/// per-column fact recorded by [`crate::metadata::Metadata`], not a
/// per-value type violation).
pub(crate) fn value_matches_type(value: &Value, column_type: ColumnType) -> bool {
    matches!(
        (value, column_type),
        (Value::Null, _)
            | (Value::Integer(_), ColumnType::Integer)
            | (Value::Float(_), ColumnType::Float)
            | (Value::Boolean(_), ColumnType::Boolean)
            | (Value::Text(_), ColumnType::Text)
    )
}
EOF

echo "==> Writing crates/rasica-dataset/src/prelude.rs..."
cat > crates/rasica-dataset/src/prelude.rs << 'EOF'
//! Convenience re-export of the types most consumers of `rasica-dataset`
//! need, following the same convention as `rasica_core::prelude`
//! (Document 00A §5.6).

pub use crate::{
    dataset::{Dataset, DatasetBuilder, DatasetMarker},
    error::DatasetError,
    metadata::{ColumnMetadata, Metadata},
    row::Row,
    schema::{Column, ColumnType, Schema, SchemaError},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};
EOF

echo "==> Writing crates/rasica-dataset/benches/dataset_construction.rs..."
cat > crates/rasica-dataset/benches/dataset_construction.rs << 'EOF'
//! Benchmarks `Dataset` construction and fingerprinting at a fixed,
//! documented shape (1,000 rows × 10 columns). This is a regression
//! baseline, not a validation of Appendix H's full target — see §5.4 of
//! the Phase 2 Implementation Specification.

use criterion::{black_box, criterion_group, criterion_main, Criterion};
use rasica_core::prelude::DeterministicFingerprint;
use rasica_dataset::prelude::*;

const ROWS: usize = 1_000;
const COLUMNS: usize = 10;

fn build_dataset() -> Dataset {
    let columns = (0..COLUMNS)
        .map(|i| Column::new(format!("c{i}"), ColumnType::Integer))
        .collect();
    let schema = Schema::new(columns).expect("fixed benchmark shape is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    for r in 0..ROWS {
        let row = Row::new((0..COLUMNS).map(|c| Value::Integer((r * c) as i64)).collect());
        builder.push_row(row).expect("fixed benchmark shape is well-formed");
    }
    builder.build(SourceMetadata::new(SourceFormat::InMemory, "benchmark"))
}

fn bench_construction(c: &mut Criterion) {
    c.bench_function("dataset_construction_1000x10", |b| {
        b.iter(|| black_box(build_dataset()));
    });
}

fn bench_fingerprint(c: &mut Criterion) {
    let dataset = build_dataset();
    c.bench_function("dataset_fingerprint_1000x10", |b| {
        b.iter(|| black_box(dataset.fingerprint()));
    });
}

criterion_group!(benches, bench_construction, bench_fingerprint);
criterion_main!(benches);
EOF

# ---------------------------------------------------------------------------
# Patch: tests/workspace_smoke/Cargo.toml
# ---------------------------------------------------------------------------

echo "==> Patching tests/workspace_smoke/Cargo.toml (add rasica-dataset dep)..."
if ! grep -q "rasica-dataset" tests/workspace_smoke/Cargo.toml; then
  cat >> tests/workspace_smoke/Cargo.toml << 'EOF'
rasica-dataset = { path = "../../crates/rasica-dataset", version = "0.1.0" }
EOF
else
  echo "    (already patched, skipping)"
fi

# ---------------------------------------------------------------------------
# Patch: tests/workspace_smoke/tests/smoke.rs
# ---------------------------------------------------------------------------

echo "==> Extending tests/workspace_smoke/tests/smoke.rs (Phase 2 module)..."
if ! grep -q "dataset_composes_with_core_vocabulary" tests/workspace_smoke/tests/smoke.rs; then
  cat >> tests/workspace_smoke/tests/smoke.rs << 'EOF'

mod dataset_composes_with_core_vocabulary {
    use rasica_core::prelude::*;
    use rasica_dataset::prelude::*;

    fn sample_dataset() -> Dataset {
        let schema = Schema::new(vec![
            Column::new("id", ColumnType::Integer),
            Column::new("label", ColumnType::Text),
        ])
        .expect("well-formed schema in test fixture");

        let mut builder = DatasetBuilder::new(schema);
        builder
            .push_row(Row::new(vec![Value::Integer(1), Value::Text("a".into())]))
            .expect("well-formed row in test fixture");

        builder.build(SourceMetadata::new(SourceFormat::InMemory, "test-fixture"))
    }

    #[test]
    fn dataset_is_identifiable_and_fingerprintable() {
        let dataset = sample_dataset();
        let _ = dataset.id();
        let _ = dataset.fingerprint();
    }

    #[test]
    fn metadata_derives_from_dataset_without_mutating_it() {
        let dataset = sample_dataset();
        let metadata = Metadata::derive(&dataset);
        assert_eq!(metadata.columns().len(), dataset.schema().arity());
        // Deriving Metadata does not require, and cannot obtain, `&mut
        // Dataset` — this is checked by the type signature of
        // `Metadata::derive(&Dataset)` compiling at all, not by an
        // assertion here.
    }
}
EOF
else
  echo "    (already patched, skipping)"
fi

# ---------------------------------------------------------------------------
# Patch: .github/workflows/ci.yml — benchmark-regression job
# ---------------------------------------------------------------------------

echo "==> Patching .github/workflows/ci.yml (real benchmark-regression body)..."
if [ -f .github/workflows/ci.yml ] && grep -q "No benchmarks defined in Phase 1" .github/workflows/ci.yml; then
  python3 - << 'PYEOF'
with open(".github/workflows/ci.yml") as f:
    content = f.read()

old_job = """  benchmark-regression:
    name: Benchmark Regression Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # No benchmarks exist yet: Phase 1 introduces no analytical or
      # performance-sensitive code (Appendix H's targets apply from Phase 2
      # onward). This job is retained as a placeholder, per Architecture
      # Spec §14.14, so the pipeline's job list already matches the full
      # required set and no later phase needs to restructure `ci.yml` to
      # "add" this requirement — only to give it a real body (`cargo
      # bench` + a stored baseline comparison).
      - run: echo "No benchmarks defined in Phase 1; see Appendix H and §14.15."
"""

new_job = """  benchmark-regression:
    name: Benchmark Regression Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
      # Phase 2 gives this job its first real body (Document 00A §7.2's
      # placeholder). It runs the fixed-shape benchmark defined in §5.4 of
      # the Phase 2 Implementation Specification and stores the result as
      # this job's artifact; comparing successive runs for regression
      # (rather than only recording them) is deferred to the Benchmarking
      # Specification (Appendix E item 24), which is expected to define the
      # reference machine and comparison policy this job will enforce.
      - run: cargo bench --workspace
      - uses: actions/upload-artifact@v4
        with:
          name: criterion-results
          path: target/criterion
"""

if old_job in content:
    content = content.replace(old_job, new_job)
    with open(".github/workflows/ci.yml", "w") as f:
        f.write(content)
    print("    patched.")
else:
    print("    WARNING: exact placeholder block not found — check ci.yml manually.")
PYEOF
else
  echo "    (already patched or ci.yml missing, skipping)"
fi

echo ""
echo "==> Done. Phase 2 (rasica-dataset) scaffolded."
echo ""
echo "Next steps:"
echo "  1. cargo check --workspace"
echo "  2. cargo nextest run --workspace"
echo "  3. cargo clippy --workspace --all-targets -- -D warnings"
echo "  4. cargo fmt --all"
echo "  5. cargo bench --workspace   (exercises the new benchmark-regression CI job locally)"
echo "  6. cargo deny check"
