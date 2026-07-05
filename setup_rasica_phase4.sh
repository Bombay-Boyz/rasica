#!/usr/bin/env bash
# Adds Phase 4 (Validation Engine) to an existing RASICA Phase 1+2+3
# workspace, per Architecture Spec §9.2 and §15.7, and §6.6 (Validation
# Report).
#
# ADDITIVE and idempotent, same conventions as setup_rasica_phase3.sh:
# creates the new `rasica-validation` crate in full, and patches root
# Cargo.toml + tests/workspace_smoke/{Cargo.toml,tests/smoke.rs}.
#
# Architectural notes this script encodes:
#   - §8.3 / §8.9: the Validation Engine depends only on `rasica-common`,
#     `rasica-core`, and `rasica-dataset` — never on any Domain Module
#     ("Validation is structural, not semantic"). `ValidationConstraint`
#     is therefore authored here, not in a later Domain SDK phase; §11.15
#     and Appendix G's `contribute_validation` are downstream consumers
#     of this crate's type, not the other way around (Appendix G's Type
#     Authority Policy).
#   - §6.6: the Validation Report never modifies the Dataset, never
#     contains analytical conclusions, and is Tier 1 — Immutable (§6.2A).
#   - §15.7 exit criteria (every fault detected, no false positives,
#     deterministic diagnostics) are exercised directly in
#     tests/fault_injection.rs via constructible faults: duplicate rows,
#     null-ratio breaches, and constraint violations are all reachable
#     through valid `Value`s and are asserted both to fire when present
#     and to stay silent when absent. Schema/Datatype/Integrity checks
#     are structural invariants already guaranteed by `DatasetBuilder`
#     for any Dataset built the normal way (Document 00B); they are kept
#     here anyway as an independent second check, because §6.6 declares
#     Validation "an independent architectural concern" and this crate
#     must not assume every Dataset it is handed necessarily came from
#     `rasica-ingestion`'s path (§6.4's logical-immutability note makes
#     the same point about alternative future Dataset backings).
#
# ADAPTATION NOTE: this crate's only assumption about `rasica-dataset`'s
# public surface beyond what `rasica-ingestion` (Phase 3) already
# exercises is that `Dataset` exposes `rows() -> &[Row]`, `Row` exposes
# `values() -> &[Value]`, and `Column` exposes `name() -> &str`. These
# four calls are isolated in one file, crates/rasica-validation/src/
# dataset_view.rs, specifically so that if your actual Phase 2 `Dataset`
# API names these differently, you only need to edit that one file.
#
# Usage: run from the rasica/ project root.
#
#   chmod +x setup_rasica_phase4.sh
#   ./setup_rasica_phase4.sh

set -euo pipefail

if [ ! -f "Cargo.toml" ] || ! grep -q "\[workspace\]" Cargo.toml; then
  echo "Error: no workspace root Cargo.toml found here."
  exit 1
fi

if [ ! -d "crates/rasica-dataset" ]; then
  echo "Error: crates/rasica-dataset must already exist (Phase 2)."
  exit 1
fi

if [ ! -d "crates/rasica-ingestion" ]; then
  echo "Error: crates/rasica-ingestion must already exist (Phase 3)."
  exit 1
fi

echo "==> Creating crates/rasica-validation directory structure..."
mkdir -p crates/rasica-validation/src
mkdir -p crates/rasica-validation/benches
mkdir -p crates/rasica-validation/tests

# ---------------------------------------------------------------------------
# Patch: workspace root Cargo.toml
# ---------------------------------------------------------------------------

echo "==> Patching root Cargo.toml (add rasica-validation member)..."
if ! grep -q '"crates/rasica-validation"' Cargo.toml; then
  python3 - << 'PYEOF'
with open("Cargo.toml") as f:
    content = f.read()

content = content.replace(
    '    "crates/rasica-ingestion",\n    "tests/workspace_smoke",',
    '    "crates/rasica-ingestion",\n    "crates/rasica-validation",\n    "tests/workspace_smoke",',
)

with open("Cargo.toml", "w") as f:
    f.write(content)
PYEOF
else
  echo "    (already patched, skipping)"
fi

# ---------------------------------------------------------------------------
# rasica-validation crate
# ---------------------------------------------------------------------------

echo "==> Writing crates/rasica-validation/Cargo.toml..."
cat > crates/rasica-validation/Cargo.toml << 'EOF'
[package]
name = "rasica-validation"
description = "Structural validation (schema, datatype, null, duplicate, integrity, constraint) producing an immutable Validation Report."
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
rasica-dataset = { path = "../rasica-dataset", version = "0.1.0" }
thiserror = { workspace = true }

[dev-dependencies]
proptest = { workspace = true }
rstest = { workspace = true }
criterion = { workspace = true }

[[bench]]
name = "validation"
harness = false
EOF

echo "==> Writing crates/rasica-validation/src/dataset_view.rs..."
cat > crates/rasica-validation/src/dataset_view.rs << 'EOF'
//! Isolates the exact read-only accessor names this crate assumes
//! `rasica-dataset` exposes on `Dataset`, `Row`, and `Column`, beyond the
//! `schema()`, `row_count()`, `Schema::arity()`, `Schema::columns()`, and
//! `Column::column_type()` already exercised by `rasica-ingestion`
//! (Phase 3).
//!
//! Every other module in this crate calls through here rather than
//! calling `rasica_dataset` directly for row/value/name access, so that
//! a future rename in `rasica-dataset`'s public surface requires editing
//! exactly one file.

use rasica_dataset::{row::Row, schema::Column, value::Value};

/// This crate's own Dataset accessors, isolated from every check module.
pub(crate) trait DatasetView {
    /// Every row currently held by the Dataset, in a stable, deterministic
    /// order (the order established at construction — §12.10's
    /// deterministic reduction strategy governs how *computation* over
    /// this order may be parallelised, not the order's existence).
    fn validation_rows(&self) -> &[Row];
}

impl DatasetView for rasica_dataset::dataset::Dataset {
    fn validation_rows(&self) -> &[Row] {
        self.rows()
    }
}

/// This crate's own Row accessor.
pub(crate) fn row_values(row: &Row) -> &[Value] {
    row.values()
}

/// This crate's own Column accessor.
pub(crate) fn column_name(column: &Column) -> &str {
    column.name()
}
EOF

echo "==> Writing crates/rasica-validation/src/value_key.rs..."
cat > crates/rasica-validation/src/value_key.rs << 'EOF'
//! A `Hash + Eq` view of `rasica_dataset::value::Value`, used wherever a
//! check needs set/map membership over cell values (duplicate row
//! detection, `Unique` constraint checking) at better than O(n^2).
//!
//! `Value::Float`'s `f64` is not itself `Hash + Eq` (NaN's reflexivity
//! failure); this module fixes that by hashing the bit pattern instead,
//! which is exactly as discriminating as the platform's own `f64`
//! equality for every non-NaN value, and treats all NaN payloads as one
//! equivalence class, which is an acceptable, documented narrowing here
//! since duplicate/uniqueness checking needs *an* equivalence relation,
//! not IEEE-754 comparison semantics.

use rasica_dataset::value::Value;

/// A hashable, totally-ordered-for-equality key for one cell value.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) enum ValueKey {
    Null,
    Boolean(bool),
    Integer(i64),
    /// Bit-pattern of the `f64`, not its numeric value — see module docs.
    Float(u64),
    Text(String),
}

impl From<&Value> for ValueKey {
    fn from(value: &Value) -> Self {
        match value {
            Value::Null => Self::Null,
            Value::Boolean(b) => Self::Boolean(*b),
            Value::Integer(i) => Self::Integer(*i),
            Value::Float(f) => Self::Float(f.to_bits()),
            Value::Text(s) => Self::Text(s.clone()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn equal_values_produce_equal_keys() {
        assert_eq!(ValueKey::from(&Value::Integer(3)), ValueKey::from(&Value::Integer(3)));
        assert_eq!(ValueKey::from(&Value::Text("a".into())), ValueKey::from(&Value::Text("a".into())));
        assert_eq!(ValueKey::from(&Value::Null), ValueKey::from(&Value::Null));
    }

    #[test]
    fn distinct_values_produce_distinct_keys() {
        assert_ne!(ValueKey::from(&Value::Integer(3)), ValueKey::from(&Value::Integer(4)));
        assert_ne!(ValueKey::from(&Value::Integer(1)), ValueKey::from(&Value::Boolean(true)));
    }
}
EOF

echo "==> Writing crates/rasica-validation/src/finding.rs..."
cat > crates/rasica-validation/src/finding.rs << 'EOF'
//! Structured outcomes recorded by every check in this crate, matching
//! the Validation Report's five recorded categories (§6.6): successful
//! validations, failed validations, warnings, recommendations, and
//! assumptions.

use std::fmt;

/// Which of §6.6's five recorded outcome categories a single
/// [`ValidationFinding`] belongs to.
///
/// `Success` and `Failure` are the two outcomes of a strict pass/fail
/// structural check (schema, datatype, integrity, and — per constraint —
/// constraint checking). `Warning` flags a condition that is
/// structurally valid but worth surfacing (a high null ratio). This
/// crate's checks are all deterministic pass/fail/warn checks, so
/// `Recommendation` and `Assumption` are defined here as part of the
/// shared vocabulary §6.6 requires, but are not emitted by any Phase 4
/// check; they exist for later phases (e.g. Structural Inference, §15.8,
/// which must make genuine inferential judgement calls) to record
/// findings into the same report structure without a vocabulary change.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FindingKind {
    /// A check ran and found no violation.
    Success,
    /// A check ran and found a definite structural violation.
    Failure,
    /// A check ran and found a condition worth surfacing, short of a
    /// definite violation.
    Warning,
    /// A non-binding suggestion about the Dataset, distinct from a
    /// pass/fail outcome (§6.6). Not emitted by any Phase 4 check.
    Recommendation,
    /// An inferential judgement call a check had to make, recorded so it
    /// is visible rather than silent (§6.6). Not emitted by any Phase 4
    /// check.
    Assumption,
}

/// Which validation activity (§15.7 deliverable) produced a finding.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ValidationCategory {
    /// §9.2 "schema validation".
    Schema,
    /// §9.2 "datatype validation".
    Datatype,
    /// §9.2 "integrity".
    Integrity,
    /// §9.2 "missing values".
    NullAnalysis,
    /// §9.2 "duplicate detection".
    Duplicate,
    /// §11.15 Domain-contributed structural constraints, evaluated here.
    Constraint,
}

/// Where in the Dataset a finding applies, at the coarsest level that is
/// still precise enough to act on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Location {
    /// The Dataset as a whole (e.g. "schema declares zero columns").
    Dataset,
    /// A single column, identified by both its 0-based index and name
    /// (both are kept: the index is stable under column renaming
    /// mid-report, the name is what a person reads).
    Column {
        /// 0-based column index within the schema.
        index: usize,
        /// The column's declared name.
        name: String,
    },
    /// A single row, identified by its 0-based index.
    Row {
        /// 0-based row index within the Dataset.
        index: usize,
    },
    /// A single cell, identified by 0-based row and column index.
    Cell {
        /// 0-based row index within the Dataset.
        row: usize,
        /// 0-based column index within the schema.
        column: usize,
    },
}

impl fmt::Display for Location {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Dataset => write!(f, "dataset"),
            Self::Column { index, name } => write!(f, "column {index} ('{name}')"),
            Self::Row { index } => write!(f, "row {index}"),
            Self::Cell { row, column } => write!(f, "row {row}, column {column}"),
        }
    }
}

/// One recorded outcome of a single validation activity (§6.6).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidationFinding {
    kind: FindingKind,
    category: ValidationCategory,
    code: &'static str,
    message: String,
    location: Location,
}

impl ValidationFinding {
    /// Constructs a finding. Not exposed outside this crate: every
    /// finding a caller sees was produced by one of this crate's own
    /// checks, never fabricated by a consumer (§6.6, "never contains
    /// analytical conclusions" — a consumer synthesising its own
    /// findings would defeat that guarantee).
    pub(crate) fn new(
        kind: FindingKind,
        category: ValidationCategory,
        code: &'static str,
        message: impl Into<String>,
        location: Location,
    ) -> Self {
        Self {
            kind,
            category,
            code,
            message: message.into(),
            location,
        }
    }

    /// The outcome category (§6.6) this finding belongs to.
    #[must_use]
    pub fn kind(&self) -> FindingKind {
        self.kind
    }

    /// Which validation activity (§15.7) produced this finding.
    #[must_use]
    pub fn category(&self) -> ValidationCategory {
        self.category
    }

    /// A stable, machine-matchable identifier for this finding's specific
    /// check (e.g. `"duplicate::row"`), independent of `message`'s
    /// human-readable wording.
    #[must_use]
    pub fn code(&self) -> &'static str {
        self.code
    }

    /// A human-readable description of this finding.
    #[must_use]
    pub fn message(&self) -> &str {
        &self.message
    }

    /// Where in the Dataset this finding applies.
    #[must_use]
    pub fn location(&self) -> &Location {
        &self.location
    }
}

impl fmt::Display for ValidationFinding {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[{:?}/{}] {} ({})", self.kind, self.code, self.message, self.location)
    }
}
EOF

echo "==> Writing crates/rasica-validation/src/schema_check.rs..."
cat > crates/rasica-validation/src/schema_check.rs << 'EOF'
//! Schema-level structural validation (§9.2 "schema validation").

use std::collections::HashSet;

use rasica_dataset::schema::Schema;

use crate::{
    dataset_view::column_name,
    finding::{FindingKind, Location, ValidationCategory, ValidationFinding},
};

/// Checks that `schema` is non-empty and every column has a non-empty,
/// unique name.
///
/// `rasica-dataset`'s own `Schema::new` already rejects a malformed
/// schema at construction time for any Dataset built through the normal
/// `DatasetBuilder` path (Document 00B). This check re-verifies the same
/// invariants independently against whatever `Schema` the Dataset in
/// hand actually reports, because the Validation Engine is
/// architecturally independent of Ingestion (§6.6) and must not assume
/// every Dataset it validates was necessarily built that way.
pub(crate) fn check_schema(schema: &Schema) -> Vec<ValidationFinding> {
    if schema.arity() == 0 {
        return vec![ValidationFinding::new(
            FindingKind::Failure,
            ValidationCategory::Schema,
            "schema::empty",
            "schema declares zero columns",
            Location::Dataset,
        )];
    }

    let mut findings = Vec::new();
    let mut seen_names: HashSet<&str> = HashSet::new();
    let mut clean = true;

    for (index, column) in schema.columns().iter().enumerate() {
        let name = column_name(column);
        if name.trim().is_empty() {
            clean = false;
            findings.push(ValidationFinding::new(
                FindingKind::Failure,
                ValidationCategory::Schema,
                "schema::empty_column_name",
                format!("column {index} has an empty name"),
                Location::Column { index, name: name.to_string() },
            ));
            continue;
        }
        if !seen_names.insert(name) {
            clean = false;
            findings.push(ValidationFinding::new(
                FindingKind::Failure,
                ValidationCategory::Schema,
                "schema::duplicate_column_name",
                format!("column name '{name}' is duplicated"),
                Location::Column { index, name: name.to_string() },
            ));
        }
    }

    if clean {
        findings.push(ValidationFinding::new(
            FindingKind::Success,
            ValidationCategory::Schema,
            "schema::well_formed",
            "schema is non-empty with uniquely and non-emptily named columns",
            Location::Dataset,
        ));
    }

    findings
}

#[cfg(test)]
mod tests {
    use super::*;
    use rasica_dataset::schema::{Column, ColumnType};

    #[test]
    #[allow(clippy::expect_used)]
    fn well_formed_schema_produces_exactly_one_success() {
        let schema = Schema::new(vec![
            Column::new("id", ColumnType::Integer),
            Column::new("label", ColumnType::Text),
        ])
        .expect("hand-written schema is well-formed");
        let findings = check_schema(&schema);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].kind(), FindingKind::Success);
    }
}
EOF

echo "==> Writing crates/rasica-validation/src/datatype_check.rs..."
cat > crates/rasica-validation/src/datatype_check.rs << 'EOF'
//! Per-cell datatype validation (§9.2 "datatype validation").

use rasica_dataset::{dataset::Dataset, schema::ColumnType, value::Value};

use crate::{
    dataset_view::{row_values, DatasetView},
    finding::{FindingKind, Location, ValidationCategory, ValidationFinding},
};

/// Checks that every cell's runtime [`Value`] variant agrees with its
/// column's declared [`ColumnType`] (a null cell agrees with every
/// column type, matching `rasica-dataset`'s own treatment of
/// `Value::Null`, Document 00B §4.6).
///
/// For any Dataset built through `DatasetBuilder`, this can never fail —
/// the builder enforces the same invariant at construction time. This
/// check exists as an independent second verification for the same
/// reason given in `schema_check`: Validation must not assume how the
/// Dataset in hand was built.
pub(crate) fn check_datatypes(dataset: &Dataset) -> Vec<ValidationFinding> {
    let schema = dataset.schema();
    let mut findings = Vec::new();
    let mut clean = true;

    for (row_index, row) in dataset.validation_rows().iter().enumerate() {
        for (column_index, (value, column)) in
            row_values(row).iter().zip(schema.columns()).enumerate()
        {
            if !value_matches(value, column.column_type()) {
                clean = false;
                findings.push(ValidationFinding::new(
                    FindingKind::Failure,
                    ValidationCategory::Datatype,
                    "datatype::mismatch",
                    format!(
                        "expected a value compatible with {:?}, found {value:?}",
                        column.column_type()
                    ),
                    Location::Cell { row: row_index, column: column_index },
                ));
            }
        }
    }

    if clean {
        findings.push(ValidationFinding::new(
            FindingKind::Success,
            ValidationCategory::Datatype,
            "datatype::consistent",
            "every cell's value matches its column's declared type",
            Location::Dataset,
        ));
    }

    findings
}

fn value_matches(value: &Value, column_type: ColumnType) -> bool {
    matches!(
        (value, column_type),
        (Value::Null, _)
            | (Value::Integer(_), ColumnType::Integer)
            | (Value::Float(_), ColumnType::Float)
            | (Value::Boolean(_), ColumnType::Boolean)
            | (Value::Text(_), ColumnType::Text)
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn null_agrees_with_every_column_type() {
        assert!(value_matches(&Value::Null, ColumnType::Integer));
        assert!(value_matches(&Value::Null, ColumnType::Text));
        assert!(value_matches(&Value::Null, ColumnType::Boolean));
        assert!(value_matches(&Value::Null, ColumnType::Float));
    }

    #[test]
    fn integer_does_not_agree_with_text() {
        assert!(!value_matches(&Value::Integer(1), ColumnType::Text));
    }
}
EOF

echo "==> Writing crates/rasica-validation/src/integrity_check.rs..."
cat > crates/rasica-validation/src/integrity_check.rs << 'EOF'
//! Dataset-level integrity validation (§9.2 "integrity"): row count and
//! per-row arity agree with the schema.

use rasica_dataset::dataset::Dataset;

use crate::{
    dataset_view::{row_values, DatasetView},
    finding::{FindingKind, Location, ValidationCategory, ValidationFinding},
};

/// Checks that `dataset.row_count()` agrees with the actual number of
/// rows held, and that every row's arity agrees with the schema's arity.
///
/// As with `schema_check` and `datatype_check`, this is guaranteed for
/// any Dataset built through `DatasetBuilder`; it is re-checked here
/// independently for the same reason (§6.6).
pub(crate) fn check_integrity(dataset: &Dataset) -> Vec<ValidationFinding> {
    let schema = dataset.schema();
    let rows = dataset.validation_rows();
    let mut findings = Vec::new();
    let mut clean = true;

    if rows.len() != dataset.row_count() {
        clean = false;
        findings.push(ValidationFinding::new(
            FindingKind::Failure,
            ValidationCategory::Integrity,
            "integrity::row_count_mismatch",
            format!(
                "row_count() reports {} but {} rows are held",
                dataset.row_count(),
                rows.len()
            ),
            Location::Dataset,
        ));
    }

    for (index, row) in rows.iter().enumerate() {
        let arity = row_values(row).len();
        if arity != schema.arity() {
            clean = false;
            findings.push(ValidationFinding::new(
                FindingKind::Failure,
                ValidationCategory::Integrity,
                "integrity::row_arity_mismatch",
                format!("row has {arity} values but the schema declares {} columns", schema.arity()),
                Location::Row { index },
            ));
        }
    }

    if clean {
        findings.push(ValidationFinding::new(
            FindingKind::Success,
            ValidationCategory::Integrity,
            "integrity::consistent",
            "row count and every row's arity agree with the schema",
            Location::Dataset,
        ));
    }

    findings
}
EOF

echo "==> Writing crates/rasica-validation/src/null_analysis.rs..."
cat > crates/rasica-validation/src/null_analysis.rs << 'EOF'
//! Missing-value / null analysis (§9.2 "missing values").

use rasica_dataset::{dataset::Dataset, value::Value};

use crate::{
    dataset_view::{column_name, row_values, DatasetView},
    error::ValidationError,
    finding::{FindingKind, Location, ValidationCategory, ValidationFinding},
};

/// Configuration for [`check_nulls`].
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct NullAnalysisOptions {
    /// A column whose null ratio meets or exceeds this fraction (in
    /// `[0.0, 1.0]`) is recorded as a [`FindingKind::Warning`] rather
    /// than a [`FindingKind::Success`].
    warning_threshold: f64,
}

impl NullAnalysisOptions {
    /// Constructs options with the given warning threshold.
    ///
    /// # Errors
    ///
    /// Returns [`ValidationError::InvalidThreshold`] if `warning_threshold`
    /// is not in `[0.0, 1.0]`.
    pub fn new(warning_threshold: f64) -> Result<Self, ValidationError> {
        if !(0.0..=1.0).contains(&warning_threshold) {
            return Err(ValidationError::InvalidThreshold { value: warning_threshold });
        }
        Ok(Self { warning_threshold })
    }

    /// The configured warning threshold.
    #[must_use]
    pub fn warning_threshold(&self) -> f64 {
        self.warning_threshold
    }
}

impl Default for NullAnalysisOptions {
    /// A column that is half or more null is flagged; this is a starting
    /// baseline (Appendix H's own numeric targets are likewise stated as
    /// baselines to be refined by ADR), not a claim that 50% is
    /// universally the right line for every dataset shape.
    fn default() -> Self {
        Self { warning_threshold: 0.5 }
    }
}

/// Records, per column, its null count and ratio, warning when the ratio
/// meets or exceeds `options.warning_threshold()`.
///
/// A dataset with zero rows records a `Success` per column rather than
/// dividing by zero: there is no evidence of a null problem in a column
/// with no rows to evaluate, which is the same "resolve the absence of
/// evidence to the safe case" stance `rasica-ingestion`'s own
/// `ColumnTypeAccumulator` takes for an all-null column (Phase 3).
pub(crate) fn check_nulls(dataset: &Dataset, options: NullAnalysisOptions) -> Vec<ValidationFinding> {
    let schema = dataset.schema();
    let row_count = dataset.row_count();
    let mut null_counts = vec![0usize; schema.arity()];

    for row in dataset.validation_rows() {
        for (index, value) in row_values(row).iter().enumerate() {
            if matches!(value, Value::Null) {
                null_counts[index] += 1;
            }
        }
    }

    schema
        .columns()
        .iter()
        .enumerate()
        .map(|(index, column)| {
            let name = column_name(column).to_string();
            let count = null_counts[index];

            if row_count == 0 {
                return ValidationFinding::new(
                    FindingKind::Success,
                    ValidationCategory::NullAnalysis,
                    "null::no_rows",
                    format!("column '{name}' has no rows to evaluate"),
                    Location::Column { index, name },
                );
            }

            #[allow(clippy::cast_precision_loss)] // row/null counts are far below f64's exact-integer ceiling.
            let ratio = count as f64 / row_count as f64;

            if ratio >= options.warning_threshold() {
                ValidationFinding::new(
                    FindingKind::Warning,
                    ValidationCategory::NullAnalysis,
                    "null::high_ratio",
                    format!(
                        "column '{name}' is {:.1}% null ({count}/{row_count}), at or above the {:.1}% threshold",
                        ratio * 100.0,
                        options.warning_threshold() * 100.0
                    ),
                    Location::Column { index, name },
                )
            } else {
                ValidationFinding::new(
                    FindingKind::Success,
                    ValidationCategory::NullAnalysis,
                    "null::within_threshold",
                    format!("column '{name}' is {:.1}% null ({count}/{row_count})", ratio * 100.0),
                    Location::Column { index, name },
                )
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_threshold_outside_unit_interval() {
        assert!(NullAnalysisOptions::new(-0.1).is_err());
        assert!(NullAnalysisOptions::new(1.1).is_err());
        assert!(NullAnalysisOptions::new(0.5).is_ok());
    }
}
EOF

echo "==> Writing crates/rasica-validation/src/duplicate_detection.rs..."
cat > crates/rasica-validation/src/duplicate_detection.rs << 'EOF'
//! Duplicate row detection (§9.2 "duplicate detection").

use std::collections::HashMap;

use rasica_dataset::dataset::Dataset;

use crate::{
    dataset_view::{row_values, DatasetView},
    finding::{FindingKind, Location, ValidationCategory, ValidationFinding},
    value_key::ValueKey,
};

/// Flags each row that is a content-identical duplicate of an earlier
/// row (a duplicate of a duplicate is flagged against the *original*
/// first-seen row, not the nearest preceding duplicate, so that grouping
/// duplicates by their `code`/message is unambiguous regardless of how
/// many repeats exist).
///
/// Uses one forward pass with a hash map keyed by [`ValueKey`] per row
/// (O(n) in row count), rather than an O(n^2) pairwise comparison —
/// required by this Dataset's scale target (Appendix H, up to
/// 10,000,000 rows).
pub(crate) fn check_duplicates(dataset: &Dataset) -> Vec<ValidationFinding> {
    let mut first_seen_at: HashMap<Vec<ValueKey>, usize> = HashMap::new();
    let mut findings = Vec::new();
    let mut clean = true;

    for (index, row) in dataset.validation_rows().iter().enumerate() {
        let key: Vec<ValueKey> = row_values(row).iter().map(ValueKey::from).collect();
        match first_seen_at.get(&key) {
            Some(&first_index) => {
                clean = false;
                findings.push(ValidationFinding::new(
                    FindingKind::Failure,
                    ValidationCategory::Duplicate,
                    "duplicate::row",
                    format!("row {index} duplicates row {first_index}"),
                    Location::Row { index },
                ));
            }
            None => {
                first_seen_at.insert(key, index);
            }
        }
    }

    if clean {
        findings.push(ValidationFinding::new(
            FindingKind::Success,
            ValidationCategory::Duplicate,
            "duplicate::none",
            "no duplicate rows detected",
            Location::Dataset,
        ));
    }

    findings
}
EOF

echo "==> Writing crates/rasica-validation/src/constraint.rs..."
cat > crates/rasica-validation/src/constraint.rs << 'EOF'
//! Structural validation constraints (§11.15 "Domain Validation").
//!
//! `ValidationConstraint` is authored in this crate, not in a later
//! Domain SDK phase: the Validation Engine depends only on
//! `rasica-common`/`rasica-core`/`rasica-dataset` and never on any
//! Domain Module (§8.9, "Validation → Domain: Validation is structural,
//! not semantic"), so the dependency must run the other way — a future
//! `DomainModule::contribute_validation` (Appendix G) returns
//! `Vec<ValidationConstraint>` defined *here*. This crate is this type's
//! authority under Appendix G's Type Authority Policy.
//!
//! §11.15's own examples map directly onto the three variants below:
//! "Revenue shall not be negative" is a [`ValidationConstraint::Range`]
//! with `min: Some(0.0)`; "Patient age shall be non-negative" is the
//! same shape; "Machine identifier shall be unique" is
//! [`ValidationConstraint::Unique`].

use std::collections::HashMap;

use rasica_dataset::{dataset::Dataset, schema::ColumnType, value::Value};

use crate::{
    dataset_view::{row_values, DatasetView},
    finding::{FindingKind, Location, ValidationCategory, ValidationFinding},
    value_key::ValueKey,
};

/// One structural constraint checked against a single named column.
///
/// A constraint naming a column absent from the Dataset in hand is not
/// treated as a Dataset defect — Domain Modules are written independent
/// of any one Dataset's shape — so it is recorded as a `Warning`
/// ("not applicable"), never a `Failure`.
#[derive(Debug, Clone, PartialEq)]
pub enum ValidationConstraint {
    /// Every value in `column` shall be non-null.
    NotNull {
        /// The column this constraint applies to.
        column: String,
    },
    /// Every non-null value in `column` shall be distinct from every
    /// other non-null value in the same column.
    Unique {
        /// The column this constraint applies to.
        column: String,
    },
    /// Every non-null numeric (`Integer` or `Float`) value in `column`
    /// shall fall within `[min, max]` (either bound may be absent).
    Range {
        /// The column this constraint applies to.
        column: String,
        /// The inclusive lower bound, if any.
        min: Option<f64>,
        /// The inclusive upper bound, if any.
        max: Option<f64>,
    },
}

impl ValidationConstraint {
    fn column_name(&self) -> &str {
        match self {
            Self::NotNull { column } | Self::Unique { column } | Self::Range { column, .. } => column,
        }
    }
}

/// Evaluates every constraint in `constraints` against `dataset`,
/// producing one or more findings per constraint.
pub(crate) fn check_constraints(dataset: &Dataset, constraints: &[ValidationConstraint]) -> Vec<ValidationFinding> {
    let schema = dataset.schema();
    let mut findings = Vec::new();

    for constraint in constraints {
        let Some(column_index) = schema.position_of(constraint.column_name()) else {
            findings.push(ValidationFinding::new(
                FindingKind::Warning,
                ValidationCategory::Constraint,
                "constraint::column_not_found",
                format!(
                    "constraint references column '{}', which this dataset does not have; skipped",
                    constraint.column_name()
                ),
                Location::Dataset,
            ));
            continue;
        };

        findings.extend(match constraint {
            ValidationConstraint::NotNull { column } => check_not_null(dataset, column_index, column),
            ValidationConstraint::Unique { column } => check_unique(dataset, column_index, column),
            ValidationConstraint::Range { column, min, max } => {
                check_range(dataset, column_index, column, *min, *max)
            }
        });
    }

    findings
}

fn check_not_null(dataset: &Dataset, column_index: usize, column: &str) -> Vec<ValidationFinding> {
    let mut findings = Vec::new();
    let mut clean = true;

    for (row_index, row) in dataset.validation_rows().iter().enumerate() {
        if matches!(row_values(row)[column_index], Value::Null) {
            clean = false;
            findings.push(ValidationFinding::new(
                FindingKind::Failure,
                ValidationCategory::Constraint,
                "constraint::not_null_violated",
                format!("column '{column}' is null, but a NotNull constraint applies"),
                Location::Cell { row: row_index, column: column_index },
            ));
        }
    }

    if clean {
        findings.push(ValidationFinding::new(
            FindingKind::Success,
            ValidationCategory::Constraint,
            "constraint::not_null_satisfied",
            format!("column '{column}' contains no null values"),
            Location::Column { index: column_index, name: column.to_string() },
        ));
    }

    findings
}

fn check_unique(dataset: &Dataset, column_index: usize, column: &str) -> Vec<ValidationFinding> {
    let mut first_seen_at: HashMap<ValueKey, usize> = HashMap::new();
    let mut findings = Vec::new();
    let mut clean = true;

    for (row_index, row) in dataset.validation_rows().iter().enumerate() {
        let value = &row_values(row)[column_index];
        if matches!(value, Value::Null) {
            continue; // nulls do not participate in uniqueness, matching Phase 3's typing convention.
        }
        let key = ValueKey::from(value);
        match first_seen_at.get(&key) {
            Some(&first_index) => {
                clean = false;
                findings.push(ValidationFinding::new(
                    FindingKind::Failure,
                    ValidationCategory::Constraint,
                    "constraint::unique_violated",
                    format!("column '{column}' value at row {row_index} duplicates row {first_index}"),
                    Location::Cell { row: row_index, column: column_index },
                ));
            }
            None => {
                first_seen_at.insert(key, row_index);
            }
        }
    }

    if clean {
        findings.push(ValidationFinding::new(
            FindingKind::Success,
            ValidationCategory::Constraint,
            "constraint::unique_satisfied",
            format!("column '{column}' contains no duplicate non-null values"),
            Location::Column { index: column_index, name: column.to_string() },
        ));
    }

    findings
}

fn check_range(
    dataset: &Dataset,
    column_index: usize,
    column: &str,
    min: Option<f64>,
    max: Option<f64>,
) -> Vec<ValidationFinding> {
    let column_type = dataset.schema().columns()[column_index].column_type();
    if !matches!(column_type, ColumnType::Integer | ColumnType::Float) {
        return vec![ValidationFinding::new(
            FindingKind::Warning,
            ValidationCategory::Constraint,
            "constraint::range_not_applicable",
            format!("column '{column}' is {column_type:?}, not numeric; Range constraint skipped"),
            Location::Column { index: column_index, name: column.to_string() },
        )];
    }

    let mut findings = Vec::new();
    let mut clean = true;

    for (row_index, row) in dataset.validation_rows().iter().enumerate() {
        let value = &row_values(row)[column_index];
        let Some(numeric) = as_f64(value) else {
            continue; // null: nulls do not participate in range checking.
        };
        let below_min = min.is_some_and(|bound| numeric < bound);
        let above_max = max.is_some_and(|bound| numeric > bound);
        if below_min || above_max {
            clean = false;
            findings.push(ValidationFinding::new(
                FindingKind::Failure,
                ValidationCategory::Constraint,
                "constraint::range_violated",
                format!("column '{column}' value {numeric} at row {row_index} is outside [{min:?}, {max:?}]"),
                Location::Cell { row: row_index, column: column_index },
            ));
        }
    }

    if clean {
        findings.push(ValidationFinding::new(
            FindingKind::Success,
            ValidationCategory::Constraint,
            "constraint::range_satisfied",
            format!("column '{column}' contains no values outside [{min:?}, {max:?}]"),
            Location::Column { index: column_index, name: column.to_string() },
        ));
    }

    findings
}

#[allow(clippy::cast_precision_loss)] // Range bounds are f64; exact-integer precision beyond 2^52 is not a target here.
fn as_f64(value: &Value) -> Option<f64> {
    match value {
        Value::Integer(i) => Some(*i as f64),
        Value::Float(f) => Some(*f),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn column_name_reads_back_every_variant() {
        assert_eq!(ValidationConstraint::NotNull { column: "a".into() }.column_name(), "a");
        assert_eq!(ValidationConstraint::Unique { column: "b".into() }.column_name(), "b");
        assert_eq!(
            ValidationConstraint::Range { column: "c".into(), min: None, max: None }.column_name(),
            "c"
        );
    }
}
EOF

echo "==> Writing crates/rasica-validation/src/error.rs..."
cat > crates/rasica-validation/src/error.rs << 'EOF'
//! Errors produced while configuring a validation run (Architecture Spec
//! §14.9; Document 00A §4.4).
//!
//! Running `validate` itself is infallible by design — a Dataset always
//! yields a Validation Report, recording whatever it found (§6.6);
//! failure here means a caller misconfigured the run itself, before any
//! check touched a Dataset.

use thiserror::Error;

use rasica_common::error::{ErrorCode, ErrorSeverity, RasicaError};

/// Errors from configuring a validation run.
#[derive(Debug, Error, Clone, Copy, PartialEq)]
pub enum ValidationError {
    /// A threshold parameter was outside its required `[0.0, 1.0]` range.
    #[error("threshold {value} is not within [0.0, 1.0]")]
    InvalidThreshold {
        /// The rejected value.
        value: f64,
    },
}

impl RasicaError for ValidationError {
    fn error_code(&self) -> ErrorCode {
        match self {
            Self::InvalidThreshold { .. } => ErrorCode("validation::invalid_threshold"),
        }
    }

    fn severity(&self) -> ErrorSeverity {
        // Caught before any check runs against a Dataset, i.e. before any
        // Validation Report exists — the same rationale `rasica-ingestion`
        // gives for its own `IngestionError::severity` (Phase 3).
        ErrorSeverity::Recoverable
    }
}
EOF

echo "==> Writing crates/rasica-validation/src/report.rs..."
cat > crates/rasica-validation/src/report.rs << 'EOF'
//! The Validation Report (§6.6): the Tier 1 — Immutable (§6.2A) record of
//! every validation activity performed on a Dataset.

use rasica_core::prelude::Immutable;

use crate::finding::{FindingKind, ValidationFinding};

/// Immutable record of every validation activity performed on a Dataset
/// (§6.6). Constructed exclusively via [`ValidationReportBuilder`]; once
/// built, offers no API capable of mutating its contents, satisfying the
/// Tier 1 (§6.2A) `Immutable` marker implemented below.
///
/// Per §6.6's architectural rules: a `ValidationReport` never modifies
/// the Dataset it was built from (this type holds no reference to one,
/// only its `origin` string and shape), and never contains an analytical
/// conclusion — [`ValidationReport::is_structurally_valid`] reports only
/// whether every structural check passed, not any judgement about what
/// the data means.
#[derive(Debug, Clone, PartialEq)]
pub struct ValidationReport {
    origin: String,
    row_count: usize,
    column_count: usize,
    findings: Vec<ValidationFinding>,
}

impl ValidationReport {
    /// The origin (e.g. source path or in-memory tag) of the Dataset this
    /// report was built from.
    #[must_use]
    pub fn origin(&self) -> &str {
        &self.origin
    }

    /// The row count of the Dataset this report was built from.
    #[must_use]
    pub fn row_count(&self) -> usize {
        self.row_count
    }

    /// The column count (schema arity) of the Dataset this report was
    /// built from.
    #[must_use]
    pub fn column_count(&self) -> usize {
        self.column_count
    }

    /// Every finding recorded, in the fixed check order `validate`
    /// documents (schema, datatype, integrity, null analysis, duplicate
    /// detection, then constraints) — the same order on every run for
    /// the same inputs (§15.7, "deterministic diagnostics").
    #[must_use]
    pub fn findings(&self) -> &[ValidationFinding] {
        &self.findings
    }

    /// Findings of exactly `kind`, in recorded order.
    pub fn findings_of_kind(&self, kind: FindingKind) -> impl Iterator<Item = &ValidationFinding> {
        self.findings.iter().filter(move |finding| finding.kind() == kind)
    }

    /// Every recorded [`FindingKind::Success`].
    pub fn successes(&self) -> impl Iterator<Item = &ValidationFinding> {
        self.findings_of_kind(FindingKind::Success)
    }

    /// Every recorded [`FindingKind::Failure`].
    pub fn failures(&self) -> impl Iterator<Item = &ValidationFinding> {
        self.findings_of_kind(FindingKind::Failure)
    }

    /// Every recorded [`FindingKind::Warning`].
    pub fn warnings(&self) -> impl Iterator<Item = &ValidationFinding> {
        self.findings_of_kind(FindingKind::Warning)
    }

    /// Every recorded [`FindingKind::Recommendation`].
    pub fn recommendations(&self) -> impl Iterator<Item = &ValidationFinding> {
        self.findings_of_kind(FindingKind::Recommendation)
    }

    /// Every recorded [`FindingKind::Assumption`].
    pub fn assumptions(&self) -> impl Iterator<Item = &ValidationFinding> {
        self.findings_of_kind(FindingKind::Assumption)
    }

    /// Whether every structural check recorded zero [`FindingKind::Failure`]
    /// findings. This is a purely structural signal (§6.6) — it carries no
    /// judgement about the Dataset's analytical suitability.
    #[must_use]
    pub fn is_structurally_valid(&self) -> bool {
        self.failures().next().is_none()
    }
}

impl Immutable for ValidationReport {}

/// Builder for [`ValidationReport`], mutable only until [`Self::build`]
/// consumes it — the same construction pattern `rasica-dataset`'s own
/// `DatasetBuilder` uses for its Tier 1 object (Document 00B).
pub(crate) struct ValidationReportBuilder {
    origin: String,
    row_count: usize,
    column_count: usize,
    findings: Vec<ValidationFinding>,
}

impl ValidationReportBuilder {
    pub(crate) fn new(origin: impl Into<String>, row_count: usize, column_count: usize) -> Self {
        Self {
            origin: origin.into(),
            row_count,
            column_count,
            findings: Vec::new(),
        }
    }

    pub(crate) fn extend(&mut self, findings: impl IntoIterator<Item = ValidationFinding>) {
        self.findings.extend(findings);
    }

    pub(crate) fn build(self) -> ValidationReport {
        ValidationReport {
            origin: self.origin,
            row_count: self.row_count,
            column_count: self.column_count,
            findings: self.findings,
        }
    }
}
EOF

echo "==> Writing crates/rasica-validation/src/validate.rs..."
cat > crates/rasica-validation/src/validate.rs << 'EOF'
//! `validate`: this crate's single entry point (§15.7), running every
//! check this crate defines, in a fixed order, and assembling their
//! findings into one [`crate::report::ValidationReport`] (§6.6).
//!
//! Check order is fixed, not merely "current": schema, then datatype,
//! then integrity, then null analysis, then duplicate detection, then
//! constraints. Findings are appended to the report in this order and
//! never reordered afterward, so a given Dataset, origin, and constraint
//! set always produce byte-identical report contents run over run —
//! §15.7's "deterministic diagnostics" exit criterion.

use rasica_dataset::dataset::Dataset;

use crate::{
    constraint::{check_constraints, ValidationConstraint},
    datatype_check::check_datatypes,
    duplicate_detection::check_duplicates,
    integrity_check::check_integrity,
    null_analysis::{check_nulls, NullAnalysisOptions},
    report::{ValidationReport, ValidationReportBuilder},
    schema_check::check_schema,
};

/// Runtime configuration for [`validate`].
#[derive(Debug, Clone, Default)]
pub struct ValidationOptions {
    /// Configuration for the null-analysis check.
    pub null: NullAnalysisOptions,
}

/// Runs every structural check this crate defines against `dataset`,
/// plus each constraint in `constraints`, and returns the resulting
/// immutable [`ValidationReport`].
///
/// `origin` is recorded on the report for traceability (e.g. the same
/// origin string `rasica-ingestion` recorded when it produced this
/// Dataset); it is supplied by the caller rather than read off the
/// Dataset, since Validation depends on `rasica-dataset` alone and must
/// not assume any particular provenance-recording convention beyond it
/// (§6.6, "an independent architectural concern").
///
/// This function never fails: every check records what it found — pass,
/// fail, or warning — rather than returning an error, matching §6.6's
/// description of the Validation Report as an unconditional record of
/// validation *activity*, not a gate that can itself be rejected.
#[must_use]
pub fn validate(
    dataset: &Dataset,
    origin: impl Into<String>,
    constraints: &[ValidationConstraint],
    options: &ValidationOptions,
) -> ValidationReport {
    let schema = dataset.schema();
    let mut builder = ValidationReportBuilder::new(origin, dataset.row_count(), schema.arity());

    builder.extend(check_schema(schema));
    builder.extend(check_datatypes(dataset));
    builder.extend(check_integrity(dataset));
    builder.extend(check_nulls(dataset, options.null));
    builder.extend(check_duplicates(dataset));
    builder.extend(check_constraints(dataset, constraints));

    builder.build()
}
EOF

echo "==> Writing crates/rasica-validation/src/lib.rs..."
cat > crates/rasica-validation/src/lib.rs << 'EOF'
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
mod datatype_check;
mod dataset_view;
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
EOF

echo "==> Writing crates/rasica-validation/src/prelude.rs..."
cat > crates/rasica-validation/src/prelude.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-validation/benches/validation.rs..."
cat > crates/rasica-validation/benches/validation.rs << 'EOF'
//! Benchmarks a full `validate` pass (every check, no constraints) over a
//! synthetic, deterministically generated Dataset, isolating validation
//! cost from ingestion cost — the same isolation rationale
//! `rasica-ingestion`'s own `csv_ingestion` benchmark documents (Phase 3).

#![allow(missing_docs, clippy::expect_used, clippy::unwrap_used, clippy::cast_possible_wrap)]

use criterion::{criterion_group, criterion_main, Criterion};
use rasica_dataset::{
    dataset::DatasetBuilder,
    row::Row,
    schema::{Column, ColumnType, Schema},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};
use rasica_validation::{validate, ValidationOptions};

fn synthetic_dataset(rows: usize, columns: usize) -> rasica_dataset::dataset::Dataset {
    let schema = Schema::new(
        (0..columns)
            .map(|c| Column::new(format!("col{c}"), ColumnType::Integer))
            .collect(),
    )
    .expect("synthetic schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    for r in 0..rows {
        let values = (0..columns).map(|c| Value::Integer(((r * columns + c) % 97) as i64)).collect();
        builder.push_row(Row::new(values)).expect("synthetic row matches synthetic schema");
    }
    builder.build(SourceMetadata::new(SourceFormat::InMemory, "synthetic"))
}

fn bench_validate(c: &mut Criterion) {
    let dataset = synthetic_dataset(10_000, 20);
    c.bench_function("validate_10k_rows_20_cols_no_constraints", |b| {
        b.iter(|| validate(&dataset, "synthetic", &[], &ValidationOptions::default()));
    });
}

criterion_group!(benches, bench_validate);
criterion_main!(benches);
EOF

echo "==> Writing crates/rasica-validation/tests/fault_injection.rs..."
cat > crates/rasica-validation/tests/fault_injection.rs << 'EOF'
//! Fault-injection tests per §15.7's verification requirement: known
//! faults are injected and confirmed detected, well-formed data is
//! confirmed to raise no false positives, and repeated runs are
//! confirmed to produce identical reports.

use rasica_dataset::{
    dataset::{Dataset, DatasetBuilder},
    row::Row,
    schema::{Column, ColumnType, Schema},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};
use rasica_validation::{
    constraint::ValidationConstraint, finding::ValidationCategory, validate, NullAnalysisOptions, ValidationOptions,
};

#[allow(clippy::expect_used)]
fn well_formed_dataset() -> Dataset {
    let schema = Schema::new(vec![
        Column::new("id", ColumnType::Integer),
        Column::new("name", ColumnType::Text),
        Column::new("revenue", ColumnType::Float),
    ])
    .expect("hand-written schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    builder
        .push_row(Row::new(vec![Value::Integer(1), Value::Text("Ada".into()), Value::Float(100.0)]))
        .expect("row matches schema");
    builder
        .push_row(Row::new(vec![Value::Integer(2), Value::Text("Grace".into()), Value::Float(250.0)]))
        .expect("row matches schema");
    builder.build(SourceMetadata::new(SourceFormat::InMemory, "well_formed"))
}

#[test]
fn well_formed_dataset_raises_no_failures_with_no_constraints() {
    let dataset = well_formed_dataset();
    let report = validate(&dataset, "well_formed", &[], &ValidationOptions::default());
    assert!(report.is_structurally_valid());
    assert_eq!(report.failures().count(), 0);
}

#[test]
#[allow(clippy::expect_used)]
fn duplicate_row_is_detected_and_absence_is_not_false_positive() {
    let clean = well_formed_dataset();
    let clean_report = validate(&clean, "clean", &[], &ValidationOptions::default());
    assert_eq!(clean_report.findings_of_kind(rasica_validation::finding::FindingKind::Failure).count(), 0);

    let schema = Schema::new(vec![Column::new("id", ColumnType::Integer)]).expect("schema is well-formed");
    let mut builder = DatasetBuilder::new(schema);
    builder.push_row(Row::new(vec![Value::Integer(7)])).expect("row matches schema");
    builder.push_row(Row::new(vec![Value::Integer(7)])).expect("row matches schema");
    let duplicated = builder.build(SourceMetadata::new(SourceFormat::InMemory, "duplicated"));

    let report = validate(&duplicated, "duplicated", &[], &ValidationOptions::default());
    assert!(!report.is_structurally_valid());
    assert!(report.failures().any(|f| f.category() == ValidationCategory::Duplicate));
}

#[test]
#[allow(clippy::expect_used)]
fn high_null_ratio_warns_and_low_ratio_does_not() {
    let schema = Schema::new(vec![Column::new("value", ColumnType::Integer)]).expect("schema is well-formed");

    let mut mostly_null = DatasetBuilder::new(schema.clone());
    mostly_null.push_row(Row::new(vec![Value::Null])).expect("row matches schema");
    mostly_null.push_row(Row::new(vec![Value::Null])).expect("row matches schema");
    mostly_null.push_row(Row::new(vec![Value::Integer(1)])).expect("row matches schema");
    let mostly_null_dataset = mostly_null.build(SourceMetadata::new(SourceFormat::InMemory, "mostly_null"));

    let report = validate(
        &mostly_null_dataset,
        "mostly_null",
        &[],
        &ValidationOptions { null: NullAnalysisOptions::new(0.5).expect("0.5 is a valid threshold") },
    );
    assert!(report.warnings().any(|f| f.category() == ValidationCategory::NullAnalysis));

    let mut no_nulls = DatasetBuilder::new(schema);
    no_nulls.push_row(Row::new(vec![Value::Integer(1)])).expect("row matches schema");
    let no_nulls_dataset = no_nulls.build(SourceMetadata::new(SourceFormat::InMemory, "no_nulls"));

    let clean_report = validate(&no_nulls_dataset, "no_nulls", &[], &ValidationOptions::default());
    assert_eq!(
        clean_report
            .findings()
            .iter()
            .filter(|f| f.category() == ValidationCategory::NullAnalysis
                && f.kind() == rasica_validation::finding::FindingKind::Warning)
            .count(),
        0
    );
}

#[test]
#[allow(clippy::expect_used)]
fn not_null_constraint_violation_is_detected() {
    let schema = Schema::new(vec![Column::new("name", ColumnType::Text)]).expect("schema is well-formed");
    let mut builder = DatasetBuilder::new(schema);
    builder.push_row(Row::new(vec![Value::Null])).expect("row matches schema");
    let dataset = builder.build(SourceMetadata::new(SourceFormat::InMemory, "nullable_name"));

    let report = validate(
        &dataset,
        "nullable_name",
        &[ValidationConstraint::NotNull { column: "name".into() }],
        &ValidationOptions::default(),
    );
    assert!(report.failures().any(|f| f.code() == "constraint::not_null_violated"));
}

#[test]
#[allow(clippy::expect_used)]
fn unique_constraint_violation_is_detected() {
    let schema = Schema::new(vec![Column::new("id", ColumnType::Integer)]).expect("schema is well-formed");
    let mut builder = DatasetBuilder::new(schema);
    builder.push_row(Row::new(vec![Value::Integer(1)])).expect("row matches schema");
    builder.push_row(Row::new(vec![Value::Integer(1)])).expect("row matches schema");
    let dataset = builder.build(SourceMetadata::new(SourceFormat::InMemory, "duplicate_ids"));

    let report = validate(
        &dataset,
        "duplicate_ids",
        &[ValidationConstraint::Unique { column: "id".into() }],
        &ValidationOptions::default(),
    );
    assert!(report.failures().any(|f| f.code() == "constraint::unique_violated"));
}

#[test]
#[allow(clippy::expect_used)]
fn range_constraint_violation_is_detected_and_valid_data_is_not_a_false_positive() {
    let dataset = well_formed_dataset(); // "revenue" column: 100.0, 250.0.

    let clean_report = validate(
        &dataset,
        "well_formed",
        &[ValidationConstraint::Range { column: "revenue".into(), min: Some(0.0), max: None }],
        &ValidationOptions::default(),
    );
    assert!(!clean_report.failures().any(|f| f.code() == "constraint::range_violated"));

    let schema = Schema::new(vec![Column::new("revenue", ColumnType::Float)]).expect("schema is well-formed");
    let mut builder = DatasetBuilder::new(schema);
    builder.push_row(Row::new(vec![Value::Float(-5.0)])).expect("row matches schema");
    let negative_dataset = builder.build(SourceMetadata::new(SourceFormat::InMemory, "negative_revenue"));

    let report = validate(
        &negative_dataset,
        "negative_revenue",
        &[ValidationConstraint::Range { column: "revenue".into(), min: Some(0.0), max: None }],
        &ValidationOptions::default(),
    );
    assert!(report.failures().any(|f| f.code() == "constraint::range_violated"));
}

#[test]
#[allow(clippy::expect_used)]
fn constraint_on_absent_column_warns_rather_than_fails() {
    let dataset = well_formed_dataset();
    let report = validate(
        &dataset,
        "well_formed",
        &[ValidationConstraint::NotNull { column: "does_not_exist".into() }],
        &ValidationOptions::default(),
    );
    assert!(report.is_structurally_valid());
    assert!(report.warnings().any(|f| f.code() == "constraint::column_not_found"));
}

#[test]
#[allow(clippy::expect_used)]
fn repeated_validation_of_the_same_dataset_is_deterministic() {
    let dataset = well_formed_dataset();
    let first = validate(&dataset, "well_formed", &[], &ValidationOptions::default());
    for _ in 0..3 {
        let repeat = validate(&dataset, "well_formed", &[], &ValidationOptions::default());
        assert_eq!(first, repeat);
    }
}

#[test]
fn validation_report_is_immutable_tier_1() {
    fn assert_immutable<T: rasica_core::prelude::Immutable>(_: &T) {}
    let dataset = well_formed_dataset();
    let report = validate(&dataset, "well_formed", &[], &ValidationOptions::default());
    assert_immutable(&report);
}
EOF

# ---------------------------------------------------------------------------
# Patch: tests/workspace_smoke/Cargo.toml
# ---------------------------------------------------------------------------

echo "==> Patching tests/workspace_smoke/Cargo.toml (add rasica-validation dep)..."
if ! grep -q "rasica-validation" tests/workspace_smoke/Cargo.toml; then
  # Ensure the file ends with a newline before appending, to avoid the
  # same concatenation bug hit during Phase 2's rollout.
  [ -n "$(tail -c1 tests/workspace_smoke/Cargo.toml)" ] && echo >> tests/workspace_smoke/Cargo.toml
  cat >> tests/workspace_smoke/Cargo.toml << 'EOF'
rasica-validation = { path = "../../crates/rasica-validation", version = "0.1.0" }
EOF
else
  echo "    (already patched, skipping)"
fi

# ---------------------------------------------------------------------------
# Patch: tests/workspace_smoke/tests/smoke.rs
# ---------------------------------------------------------------------------

echo "==> Extending tests/workspace_smoke/tests/smoke.rs (Phase 4 test)..."
if ! grep -q "validates_a_hand_built_dataset_and_flags_a_duplicate_row" tests/workspace_smoke/tests/smoke.rs; then
  cat >> tests/workspace_smoke/tests/smoke.rs << 'EOF'

#[test]
#[allow(clippy::expect_used, clippy::items_after_statements)]
fn validates_a_hand_built_dataset_and_flags_a_duplicate_row() {
    use rasica_dataset::{
        dataset::DatasetBuilder,
        row::Row,
        schema::{Column, ColumnType, Schema},
        source::{SourceFormat, SourceMetadata},
        value::Value,
    };
    use rasica_validation::{validate, ValidationOptions};

    let schema = Schema::new(vec![
        Column::new("id", ColumnType::Integer),
        Column::new("label", ColumnType::Text),
    ])
    .expect("hand-written schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    builder
        .push_row(Row::new(vec![Value::Integer(1), Value::Text("alpha".into())]))
        .expect("hand-written row matches hand-written schema");
    builder
        .push_row(Row::new(vec![Value::Integer(1), Value::Text("alpha".into())]))
        .expect("hand-written row matches hand-written schema");
    let dataset = builder.build(SourceMetadata::new(SourceFormat::InMemory, "smoke"));

    let report = validate(&dataset, "smoke", &[], &ValidationOptions::default());

    assert!(!report.is_structurally_valid());
    assert!(report
        .failures()
        .any(|f| f.category() == rasica_validation::finding::ValidationCategory::Duplicate));

    // Reuses Document 00B's own smoke assertion pattern: Validation Report is Tier 1.
    fn assert_immutable<T: rasica_core::prelude::Immutable>(_: &T) {}
    assert_immutable(&report);
}
EOF
else
  echo "    (already patched, skipping)"
fi

echo ""
echo "==> Done. Phase 4 (rasica-validation) scaffolded."
echo ""
echo "Next steps:"
echo "  1. cargo check --workspace"
echo "  2. cargo nextest run --workspace"
echo "  3. cargo clippy --workspace --all-targets -- -D warnings"
echo "  4. cargo fmt --all"
echo "  5. cargo bench --workspace"
echo "  6. cargo deny check"
echo ""
echo "Note: this crate assumes 'Dataset::rows() -> &[Row]', 'Row::values() ->"
echo "&[Value]', and 'Column::name() -> &str' on your Phase 2 rasica-dataset"
echo "crate. If any of those three names differ, the only file that needs"
echo "editing is crates/rasica-validation/src/dataset_view.rs."
