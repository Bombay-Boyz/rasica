#!/usr/bin/env bash
# Adds Phase 5 (Structural Inference Engine) to an existing RASICA
# Phase 1+2(+3) workspace, per Architecture Spec §9.3 and §15.8, §6.7
# (Structural Knowledge), and Document 00E (the Phase 5 Implementation
# Specification this script implements).
#
# ADDITIVE and idempotent, same conventions as setup_rasica_phase4.sh:
# creates the new `rasica-structural-inference` crate in full, and patches
# root Cargo.toml + tests/workspace_smoke/{Cargo.toml,tests/smoke.rs}.
#
# Architectural notes this script encodes (Document 00E):
#   - §0 / §8.3: per the Core Dependency Graph, Structural Inference is
#     the pipeline stage after the Validation Engine, but its own
#     compile-time dependency is `rasica-dataset` alone (plus
#     `rasica-common`/`rasica-core`) — §6.7 defines Structural Knowledge
#     as derived from the Dataset alone, never from the Validation
#     Report. This crate therefore does NOT depend on `rasica-validation`
#     and can be scaffolded whether or not Phase 4 has been run yet; this
#     script only requires `crates/rasica-dataset` (Phase 2) and
#     `crates/rasica-ingestion` (Phase 3, needed by this crate's own
#     dev-dependency test suite — see §7.2) to already exist.
#   - §6.7: every fact this crate produces is a structural, mechanically
#     verifiable observation, never a semantic claim; column *names* are
#     never consulted by any heuristic (§4.1) — only declared type and
#     values.
#   - §2.2 / Principle 1-2: every heuristic is a closed-form, deterministic
#     function; no learned models, no sampling, no hashing with a random
#     seed, and non-null numeric/category values are sorted before folding
#     so that `StructuralKnowledge`'s derived facts do not depend on row
#     order (§4.2/§4.3's fingerprint-determinism notes).
#   - §5.1/§5.3/§5.4 RECONCILIATION NOTE: Document 00E's own §5.1 ordering
#     list states precedence as Identifier, Temporal, Categorical,
#     Continuous, Unclassified, but §5.3's Continuous condition ("not
#     already claimed by Identifier or Temporal") and §5.4's Categorical
#     condition ("not already claimed by Identifier, Temporal, or
#     Continuous") only compose consistently if Continuous is evaluated
#     BEFORE Categorical — otherwise Categorical's own stated condition
#     ("distinct-value count ... is at least 1") would claim every
#     surviving column unconditionally, and Continuous would be
#     unreachable. Separately, §5.4's literal "at least 1" wording is
#     also inconsistent with §4.1's own doc comment for
#     `VariableRole::Categorical` ("a *small*, repeated set of distinct
#     values relative to the row count") and with §5.6's own worked
#     example of `Unclassified` ("a Text column with high cardinality
#     that isn't recognisably temporal — e.g. free-text comments"), which
#     is only reachable at all if Categorical is bounded above by the
#     same `max(20, row_count / 20)` threshold §5.3 uses as Continuous's
#     lower bound. This script implements the reading that makes both the
#     ordering and the worked examples (§7.1's own fixture corpus: a
#     `name` column of mostly-distinct free text is `Unclassified`, not
#     `Categorical`) consistent: Continuous is checked before Categorical,
#     and Categorical requires distinct_count in `[1, max(20, row_count /
#     20)]` rather than merely `>= 1`. See `role.rs` for the resulting
#     implementation and its own doc comment.
#   - §5.7: relationship evidence is restricted to `Identifier` x
#     `Identifier` column pairs within a single Dataset, using
#     `RelationshipKind::ValueSubset` as the sole evidence kind, exactly
#     as specified — cross-Dataset evidence is explicitly out of scope.
#
# ADAPTATION NOTE (parallel to Phase 4's own ADAPTATION NOTE): Document
# 00E's §4.4/§4.5 sketch `ColumnRef`/`StructuralKnowledge` as carrying a
# `dataset_id: rasica_common::Id<rasica_dataset::dataset::DatasetMarker>`
# field. `setup_rasica_phase4.sh` — the one scaffold script for this
# workspace this script could check against directly — never exercises
# any `Id<Marker>`/`Identifiable` construct; its own `ValidationReport`
# (§6.6) deliberately carries a plain caller-supplied `origin: String`
# instead of a Dataset identity handle, for exactly the same
# "architecturally independent, must not assume a provenance-recording
# convention beyond `rasica-dataset` itself" reason §0 gives here. Since
# this phase's relationship evidence is, by its own §5.7 scope, restricted
# to a single Dataset (cross-Dataset evidence is an explicit deferred
# capability), a `dataset_id` field would be carried on every value
# without ever varying within one `infer` call. This script therefore
# follows `rasica-validation`'s proven `origin: String` precedent instead
# of the unconfirmed `Id<DatasetMarker>` construct: `StructuralKnowledge`
# takes a caller-supplied `origin` string (see `infer`'s signature), and
# `ColumnRef` is scoped to `column_position` alone. If your actual
# `rasica-common`/`rasica-dataset` does define `Id<DatasetMarker>` and you
# want `StructuralKnowledge`/`ColumnRef` to carry it for future
# cross-Dataset work, the only files that need editing are
# `src/knowledge.rs` and `src/relationship.rs`.
#
# ADAPTATION NOTE 2: Document 00E's §5.2 heuristic description references
# `rasica_dataset::metadata::ColumnMetadata::unique` as an existing,
# already-computed fact this crate could reuse. `setup_rasica_phase4.sh`
# does not exercise any `Metadata`/`ColumnMetadata` API either — its own
# null-analysis and duplicate-detection checks both recompute their facts
# directly from `Dataset::rows()` rather than relying on a precomputed
# Metadata value. This script follows that same proven, minimal-assumption
# approach: every heuristic in `role.rs` computes its own non-null count
# and distinct count directly from the Dataset's rows (isolated, as with
# Phase 4, behind `src/dataset_view.rs`), rather than depending on an
# unconfirmed `Metadata`/`ColumnMetadata` surface.
#
# Usage: run from the rasica/ project root.
#
#   chmod +x setup_rasica_phase5.sh
#   ./setup_rasica_phase5.sh

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
  echo "Error: crates/rasica-ingestion must already exist (Phase 3; this"
  echo "       crate's own test suite reuses rasica-ingestion::csv::read to"
  echo "       load its accuracy-benchmark fixtures, per Document 00E §7.2)."
  exit 1
fi

echo "==> Creating crates/rasica-structural-inference directory structure..."
mkdir -p crates/rasica-structural-inference/src
mkdir -p crates/rasica-structural-inference/benches
mkdir -p crates/rasica-structural-inference/tests/fixtures

# ---------------------------------------------------------------------------
# Patch: workspace root Cargo.toml
# ---------------------------------------------------------------------------

echo "==> Patching root Cargo.toml (add rasica-structural-inference member)..."
if ! grep -q '"crates/rasica-structural-inference"' Cargo.toml; then
  python3 - << 'PYEOF'
with open("Cargo.toml") as f:
    content = f.read()

marker = '    "tests/workspace_smoke",'
if marker not in content:
    raise SystemExit(
        "Error: could not find the expected 'tests/workspace_smoke' "
        "workspace member line in Cargo.toml to anchor the patch against."
    )

# Anchored on the one member line guaranteed to exist regardless of which
# earlier phases (3? 4?) have already been scaffolded into this workspace,
# rather than assuming a specific predecessor entry, since Phase 5 does
# not require Phase 4 to have been run first (Document 00E §0).
content = content.replace(
    marker,
    '    "crates/rasica-structural-inference",\n' + marker,
    1,
)

with open("Cargo.toml", "w") as f:
    f.write(content)
PYEOF
else
  echo "    (already patched, skipping)"
fi

# ---------------------------------------------------------------------------
# rasica-structural-inference crate
# ---------------------------------------------------------------------------

echo "==> Writing crates/rasica-structural-inference/Cargo.toml..."
cat > crates/rasica-structural-inference/Cargo.toml << 'EOF'
[package]
name = "rasica-structural-inference"
description = "Structural Inference Engine: deterministic identification of identifiers, continuous/categorical/temporal variables, distributions, and relationship evidence, producing immutable Structural Knowledge."
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
# Only this crate's *test suite* reads CSV fixtures, via rasica-ingestion's
# own reader (Document 00E §7.2); the library itself never depends on it.
rasica-ingestion = { path = "../rasica-ingestion", version = "0.1.0" }
proptest = { workspace = true }
rstest = { workspace = true }
criterion = { workspace = true }
# serde_json is already a workspace dependency (added in Phase 3 for JSON
# ingestion); reused here, not redeclared, so this crate never resolves a
# second version. No `serde` dependency is needed: tests/accuracy.rs only
# deserializes into HashMap<String, HashMap<String, String>>, which serde
# implements for out of the box — no #[derive] required.
serde_json = { workspace = true }

[[bench]]
name = "structural_inference"
harness = false
EOF

echo "==> Writing crates/rasica-structural-inference/src/dataset_view.rs..."
cat > crates/rasica-structural-inference/src/dataset_view.rs << 'EOF'
//! Isolates the exact read-only accessor names this crate assumes
//! `rasica-dataset` exposes on `Dataset`, `Row`, `Schema`, and `Column` —
//! the same isolation convention `rasica-validation` established for
//! Phase 4, and the same four accessor names it already assumes
//! (`Dataset::rows()`, `Row::values()`, `Column::name()`, plus
//! `Column::column_type()`, exercised there by `constraint.rs`).
//!
//! Every other module in this crate calls through here rather than
//! calling `rasica_dataset` directly for row/value/name/type access, so
//! that a future rename in `rasica-dataset`'s public surface requires
//! editing exactly one file.

use rasica_dataset::{
    row::Row,
    schema::{Column, ColumnType},
    value::Value,
};

/// This crate's own Dataset accessor, isolated from every other module.
pub(crate) trait InferenceView {
    /// Every row currently held by the Dataset, in a stable, deterministic
    /// order (the order established at construction).
    fn inference_rows(&self) -> &[Row];
}

impl InferenceView for rasica_dataset::dataset::Dataset {
    fn inference_rows(&self) -> &[Row] {
        self.rows()
    }
}

/// This crate's own Row accessor.
pub(crate) fn row_values(row: &Row) -> &[Value] {
    row.values()
}

/// This crate's own Column name accessor. Currently unused by any
/// heuristic (§4.1: names are deliberately excluded from classification)
/// but kept here, not deleted, so this module's isolation surface stays
/// symmetric with `rasica-validation`'s identical four accessors — a
/// future consumer of `dataset_view` gains this for free without
/// reopening the isolation boundary.
#[allow(dead_code)]
pub(crate) fn column_name(column: &Column) -> &str {
    column.name()
}

/// This crate's own Column type accessor.
pub(crate) fn column_type(column: &Column) -> ColumnType {
    column.column_type()
}
EOF

echo "==> Writing crates/rasica-structural-inference/src/value_key.rs..."
cat > crates/rasica-structural-inference/src/value_key.rs << 'EOF'
//! A `Hash + Eq` view of `rasica_dataset::value::Value`, used wherever
//! this crate needs set/map membership over cell values — distinct-value
//! counting (§5.2-§5.4), duplicate temporal-parse tallying (§5.5), and
//! candidate-key subset evidence (§5.7) — at better than O(n^2).
//!
//! This is a direct copy of `rasica-validation`'s own `value_key.rs`
//! (Phase 4): `Value::Float`'s `f64` is not itself `Hash + Eq` (NaN's
//! reflexivity failure), so this module hashes the bit pattern instead,
//! which is exactly as discriminating as the platform's own `f64`
//! equality for every non-NaN value, and treats all NaN payloads as one
//! equivalence class — an acceptable, documented narrowing for the
//! set-membership purposes this crate needs, for the same reasons Phase
//! 4 documents.

use rasica_dataset::value::Value;

/// A hashable, equality-comparable key for one cell value.
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

echo "==> Writing crates/rasica-structural-inference/src/error.rs..."
cat > crates/rasica-structural-inference/src/error.rs << 'EOF'
//! Errors from `infer` (Architecture Spec §14.9; Document 00E §6).
//!
//! `infer` is otherwise infallible: once a Dataset has at least one row,
//! every column receives *some* `VariableRole` (including the
//! `Unclassified` catch-all, §5.6) and no heuristic can fail. The only
//! precondition `infer` itself enforces is a non-empty Dataset.

use thiserror::Error;

use rasica_common::error::{ErrorCode, ErrorSeverity, RasicaError};

/// Errors from calling [`crate::knowledge::infer`].
#[derive(Debug, Error, Clone, Copy, PartialEq, Eq)]
pub enum InferenceError {
    /// The Dataset has zero rows. No heuristic in this crate (§5) is
    /// meaningful without at least one row to observe, so `infer` rejects
    /// this case explicitly rather than producing a `StructuralKnowledge`
    /// of all-`Unclassified` columns that would misrepresent "nothing
    /// observed" as "observed and found unclassifiable".
    #[error("dataset has zero rows; structural inference requires at least one row")]
    EmptyDataset,
}

impl RasicaError for InferenceError {
    fn error_code(&self) -> ErrorCode {
        match self {
            Self::EmptyDataset => ErrorCode("structural_inference::empty_dataset"),
        }
    }

    fn severity(&self) -> ErrorSeverity {
        // Caught before any heuristic runs, i.e. before any
        // StructuralKnowledge exists — the same rationale
        // rasica-validation gives for its own ValidationError::severity
        // (Phase 4) and rasica-ingestion for IngestionError (Phase 3).
        ErrorSeverity::Recoverable
    }
}
EOF

echo "==> Writing crates/rasica-structural-inference/src/temporal_format.rs..."
cat > crates/rasica-structural-inference/src/temporal_format.rs << 'EOF'
//! The closed, fixed set of recognised temporal text formats (§5.5):
//! `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM:SS`, and `MM/DD/YYYY`. Deliberately not
//! general-purpose date/time parsing — matching the "closed enumeration"
//! style Document 00C's own `SourceFormat`/`ColumnType` use, and §2.2's
//! exclusion of anything beyond a closed-form deterministic function from
//! this crate.
//!
//! No external date/time crate is introduced for this: each format is a
//! small, fixed-width, positionally-anchored pattern, so validating it by
//! hand keeps this crate's dependency footprint unchanged (Document 00E
//! §8, "this crate needs no new external dependency").

/// Whether `text` parses successfully against at least one of the three
/// recognised formats.
pub(crate) fn parses_as_temporal(text: &str) -> bool {
    parses_ymd(text) || parses_ymd_hms(text) || parses_mdy(text)
}

fn is_ascii_digits(bytes: &[u8]) -> bool {
    !bytes.is_empty() && bytes.iter().all(u8::is_ascii_digit)
}

/// Calendrically valid year/month/day (accounting for leap years),
/// independent of separator style — shared by every format below.
fn valid_calendar_date(year: u32, month: u32, day: u32) -> bool {
    if !(1..=12).contains(&month) {
        return false;
    }
    let is_leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    let days_in_month = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if is_leap {
                29
            } else {
                28
            }
        }
        _ => unreachable!("month already validated to be in 1..=12"),
    };
    (1..=days_in_month).contains(&day)
}

/// `YYYY-MM-DD`.
fn parses_ymd(text: &str) -> bool {
    let bytes = text.as_bytes();
    if bytes.len() != 10 || bytes[4] != b'-' || bytes[7] != b'-' {
        return false;
    }
    if !is_ascii_digits(&bytes[0..4]) || !is_ascii_digits(&bytes[5..7]) || !is_ascii_digits(&bytes[8..10]) {
        return false;
    }
    let (Ok(year), Ok(month), Ok(day)) = (text[0..4].parse(), text[5..7].parse(), text[8..10].parse()) else {
        return false;
    };
    valid_calendar_date(year, month, day)
}

/// `YYYY-MM-DDTHH:MM:SS` (RFC 3339-style, without a timezone offset).
fn parses_ymd_hms(text: &str) -> bool {
    let bytes = text.as_bytes();
    if bytes.len() != 19 || bytes[10] != b'T' || bytes[13] != b':' || bytes[16] != b':' {
        return false;
    }
    if !parses_ymd(&text[0..10]) {
        return false;
    }
    if !is_ascii_digits(&bytes[11..13]) || !is_ascii_digits(&bytes[14..16]) || !is_ascii_digits(&bytes[17..19]) {
        return false;
    }
    let (Ok(hour), Ok(minute), Ok(second)): (Result<u32, _>, Result<u32, _>, Result<u32, _>) =
        (text[11..13].parse(), text[14..16].parse(), text[17..19].parse())
    else {
        return false;
    };
    hour <= 23 && minute <= 59 && second <= 59
}

/// `MM/DD/YYYY`.
fn parses_mdy(text: &str) -> bool {
    let bytes = text.as_bytes();
    if bytes.len() != 10 || bytes[2] != b'/' || bytes[5] != b'/' {
        return false;
    }
    if !is_ascii_digits(&bytes[0..2]) || !is_ascii_digits(&bytes[3..5]) || !is_ascii_digits(&bytes[6..10]) {
        return false;
    }
    let (Ok(month), Ok(day), Ok(year)) = (text[0..2].parse(), text[3..5].parse(), text[6..10].parse()) else {
        return false;
    };
    valid_calendar_date(year, month, day)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_every_recognised_format() {
        assert!(parses_as_temporal("2024-02-29")); // leap year
        assert!(parses_as_temporal("2024-02-29T13:45:00"));
        assert!(parses_as_temporal("02/29/2024"));
    }

    #[test]
    fn rejects_malformed_or_out_of_range_values() {
        assert!(!parses_as_temporal("2023-02-29")); // not a leap year
        assert!(!parses_as_temporal("2023-13-01")); // invalid month
        assert!(!parses_as_temporal("2023-04-31")); // April has 30 days
        assert!(!parses_as_temporal("13/40/2023")); // invalid month/day (MM/DD/YYYY)
        assert!(!parses_as_temporal("2023-01-01T24:00:00")); // hour out of range
        assert!(!parses_as_temporal("not a date"));
        assert!(!parses_as_temporal(""));
    }
}
EOF

echo "==> Writing crates/rasica-structural-inference/src/role.rs..."
cat > crates/rasica-structural-inference/src/role.rs << 'EOF'
//! `VariableRole` (§4.1) and the per-column classification decision list
//! (§5).

use rasica_dataset::{schema::ColumnType, value::Value};

use crate::temporal_format::parses_as_temporal;

/// The structural role §6.7/§9.3 assigns to a single column, determined
/// solely from the column's own declared type and values — never from its
/// name, and never from any Domain Module (§6.7: "without consulting
/// Domain Modules").
///
/// Column *names* are deliberately excluded from every heuristic in this
/// crate, even though a name like `"customer_id"` is a strong informal
/// signal: using it would make classification depend on naming
/// convention rather than on structure, which is exactly the
/// structural/semantic boundary §6.7 draws. A column named `"x"` and a
/// column named `"customer_id"` containing identical values classify
/// identically.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum VariableRole {
    /// Every non-null value is unique across the column, the column is
    /// not entirely null, and the column's declared type is
    /// [`ColumnType::Integer`] or [`ColumnType::Text`] (§5.2).
    Identifier,
    /// Numeric ([`ColumnType::Integer`] or [`ColumnType::Float`]) values
    /// whose distinct-value count exceeds the shared cardinality
    /// threshold, relative to row count (§5.3).
    Continuous,
    /// A non-empty, bounded (small relative to row count) set of distinct
    /// values (§5.4).
    Categorical,
    /// [`ColumnType::Text`] values, at least 90% of which parse as one of
    /// the recognised temporal formats (§5.5, `temporal_format`).
    Temporal,
    /// No heuristic below claimed the column: either the column is
    /// entirely null, or it is high-cardinality `Text` that is not
    /// recognisably temporal (e.g. free-text comments) (§5.6).
    Unclassified,
}

/// The fraction of a `Text` column's non-null values that must parse as a
/// recognised temporal format for the column to be classified `Temporal`
/// (§5.5, a **[DRAFT DECISION]** in Document 00E, adopted here as
/// specified: tolerating a small fraction of malformed entries in an
/// otherwise-temporal column without requiring Phase 4's validation
/// machinery to run first).
const TEMPORAL_PARSE_THRESHOLD: f64 = 0.9;

/// The distinct-value-count boundary between `Continuous`/`Categorical`:
/// at least 20 distinct values in absolute terms, or 5% of `row_count`,
/// whichever is larger (§5.3, a **[DRAFT DECISION]** in Document 00E).
///
/// This is also used, symmetrically, as `Categorical`'s *upper* bound —
/// see this module's top-of-file reconciliation note (in the generating
/// script's header) for why `Categorical` must be bounded above by this
/// same threshold rather than merely requiring `distinct_count >= 1`.
#[must_use]
pub(crate) fn continuous_categorical_threshold(row_count: usize) -> usize {
    (row_count / 20).max(20)
}

/// Classifies one column, given its declared type, the dataset's row
/// count, its non-null values (in dataset row order), and its distinct
/// non-null value count.
///
/// This is the fixed, ordered decision list of §5.1: Identifier, then
/// Temporal, then Continuous, then Categorical, then Unclassified — the
/// role of the *first* heuristic that claims the column, never a scoring
/// competition (§5.1: "keeps the classification auditable as a simple,
/// explicit precedence rule").
pub(crate) fn classify(
    column_type: ColumnType,
    row_count: usize,
    non_null_values: &[&Value],
    distinct_count: usize,
) -> VariableRole {
    let non_null_count = non_null_values.len();

    if is_identifier(column_type, non_null_count, distinct_count) {
        return VariableRole::Identifier;
    }
    if is_temporal(column_type, non_null_values) {
        return VariableRole::Temporal;
    }
    if is_continuous(column_type, row_count, distinct_count) {
        return VariableRole::Continuous;
    }
    if is_categorical(row_count, distinct_count) {
        return VariableRole::Categorical;
    }
    VariableRole::Unclassified
}

/// §5.2.
fn is_identifier(column_type: ColumnType, non_null_count: usize, distinct_count: usize) -> bool {
    matches!(column_type, ColumnType::Integer | ColumnType::Text) && non_null_count > 0 && distinct_count == non_null_count
}

/// §5.5.
fn is_temporal(column_type: ColumnType, non_null_values: &[&Value]) -> bool {
    if column_type != ColumnType::Text || non_null_values.is_empty() {
        return false;
    }
    #[allow(clippy::cast_precision_loss)] // non-null counts are far below f64's exact-integer ceiling.
    let non_null_count = non_null_values.len() as f64;

    let parseable = non_null_values
        .iter()
        .filter(|value| match value {
            Value::Text(text) => parses_as_temporal(text),
            _ => false,
        })
        .count();
    #[allow(clippy::cast_precision_loss)]
    let ratio = parseable as f64 / non_null_count;
    ratio >= TEMPORAL_PARSE_THRESHOLD
}

/// §5.3. Assumes Identifier/Temporal have already been ruled out by the
/// caller's fixed evaluation order.
fn is_continuous(column_type: ColumnType, row_count: usize, distinct_count: usize) -> bool {
    matches!(column_type, ColumnType::Integer | ColumnType::Float)
        && distinct_count > continuous_categorical_threshold(row_count)
}

/// §5.4, bounded above per this module's reconciliation note. Assumes
/// Identifier/Temporal/Continuous have already been ruled out by the
/// caller's fixed evaluation order.
fn is_categorical(row_count: usize, distinct_count: usize) -> bool {
    (1..=continuous_categorical_threshold(row_count)).contains(&distinct_count)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn values(values: &[Value]) -> Vec<&Value> {
        values.iter().collect()
    }

    #[test]
    fn identifier_requires_exact_type_and_full_distinctness() {
        let ints = [Value::Integer(1), Value::Integer(2), Value::Integer(3)];
        assert_eq!(classify(ColumnType::Integer, 3, &values(&ints), 3), VariableRole::Identifier);

        // A Float column with all-unique values is deliberately NOT an
        // identifier (§5.2: "not what 'identifier' structurally means").
        let floats = [Value::Float(1.0), Value::Float(2.0)];
        assert_ne!(classify(ColumnType::Float, 2, &values(&floats), 2), VariableRole::Identifier);
    }

    #[test]
    fn all_null_column_is_never_an_identifier() {
        assert_ne!(classify(ColumnType::Integer, 5, &[], 0), VariableRole::Identifier);
    }

    #[test]
    fn temporal_is_recognised_even_with_up_to_ten_percent_malformed_entries() {
        let mut raw = vec![Value::Text("2024-01-01".into()); 9];
        raw.push(Value::Text("not a date".into()));
        assert_eq!(classify(ColumnType::Text, 10, &values(&raw), 2), VariableRole::Temporal);
    }

    #[test]
    fn temporal_is_checked_before_categorical_for_low_cardinality_dates() {
        // Three distinct dates, REPEATED across many rows (10 rows, 3
        // distinct values) — non-unique, so Identifier cannot claim this
        // column; Categorical's low-cardinality test would otherwise claim
        // it first if Temporal were not checked before it (Document 00E
        // §5.1's own worked example).
        let raw = [
            Value::Text("2024-01-01".into()),
            Value::Text("2024-02-01".into()),
            Value::Text("2024-03-01".into()),
            Value::Text("2024-01-01".into()),
            Value::Text("2024-02-01".into()),
            Value::Text("2024-03-01".into()),
            Value::Text("2024-01-01".into()),
            Value::Text("2024-02-01".into()),
            Value::Text("2024-03-01".into()),
            Value::Text("2024-01-01".into()),
        ];
        assert_eq!(classify(ColumnType::Text, 10, &values(&raw), 3), VariableRole::Temporal);
    }

    #[rstest::rstest]
    #[case::just_below_threshold(19, VariableRole::Categorical)]
    #[case::just_above_threshold(21, VariableRole::Continuous)]
    fn continuous_categorical_boundary_is_respected(#[case] distinct_count: usize, #[case] expected: VariableRole) {
        // row_count = 100 -> threshold = max(20, 100/20) = 20.
        let role = classify(ColumnType::Float, 100, &[], distinct_count);
        assert_eq!(role, expected);
    }

    #[test]
    fn categorical_does_not_claim_high_cardinality_free_text() {
        // 25 distinct values on 30 rows, threshold = max(20, 30/20) = 20:
        // distinct_count (25) exceeds the bound, so this is Unclassified,
        // not Categorical (Document 00E's `name` fixture column).
        assert_eq!(classify(ColumnType::Text, 30, &[], 25), VariableRole::Unclassified);
    }

    #[test]
    fn entirely_null_column_is_unclassified() {
        assert_eq!(classify(ColumnType::Text, 10, &[], 0), VariableRole::Unclassified);
    }

    #[test]
    fn boolean_like_low_cardinality_column_is_categorical() {
        assert_eq!(classify(ColumnType::Boolean, 1000, &[], 2), VariableRole::Categorical);
    }
}
EOF

echo "==> Writing crates/rasica-structural-inference/src/distribution.rs..."
cat > crates/rasica-structural-inference/src/distribution.rs << 'EOF'
//! `DistributionSummary` (§6.7's "distributions" deliverable, scoped per
//! §2.2 to closed-form descriptive statistics rather than
//! distribution-family fitting).

/// A deterministic, closed-form descriptive summary of a `Continuous`
/// column's non-null values.
///
/// All five fields are computed from non-null values only; nulls are
/// excluded from every statistic.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DistributionSummary {
    minimum: f64,
    maximum: f64,
    mean: f64,
    median: f64,
    /// The population standard deviation (divisor `n`, not `n - 1`):
    /// Structural Knowledge describes the dataset's *own* observed
    /// spread, not an inference about a hypothetical larger population,
    /// so the population (not sample) formula is the structurally
    /// correct one here.
    standard_deviation: f64,
}

impl DistributionSummary {
    /// The minimum non-null value observed.
    #[must_use]
    pub fn minimum(&self) -> f64 {
        self.minimum
    }

    /// The maximum non-null value observed.
    #[must_use]
    pub fn maximum(&self) -> f64 {
        self.maximum
    }

    /// The arithmetic mean of the non-null values observed.
    #[must_use]
    pub fn mean(&self) -> f64 {
        self.mean
    }

    /// The median of the non-null values observed.
    #[must_use]
    pub fn median(&self) -> f64 {
        self.median
    }

    /// The population standard deviation of the non-null values observed.
    #[must_use]
    pub fn standard_deviation(&self) -> f64 {
        self.standard_deviation
    }

    /// Derives a summary from `values`, a column's non-null numeric
    /// values in dataset row order.
    ///
    /// Sorts `values` before summing — an `O(n log n)` cost already paid
    /// for `median` — rather than summing in row order, so that this
    /// summary's derived-fingerprint bytes do not depend on an otherwise
    /// irrelevant upstream row-ordering change (Document 00E §4.2's
    /// determinism note).
    ///
    /// # Panics
    ///
    /// Panics if `values` is empty. This is a programming defect, not a
    /// data condition: `infer` (§6) only calls this once a column has
    /// already been classified `Continuous`, which itself requires a
    /// distinct-value count exceeding a positive threshold, and therefore
    /// requires at least one non-null value to exist.
    #[must_use]
    pub(crate) fn derive(values: &[f64]) -> Self {
        assert!(
            !values.is_empty(),
            "DistributionSummary::derive called with no values; this is a caller defect \
             (only Continuous columns, which are non-empty by construction, may reach here)"
        );

        let mut sorted = values.to_vec();
        sorted.sort_by(f64::total_cmp);

        let minimum = sorted[0];
        let maximum = sorted[sorted.len() - 1];

        #[allow(clippy::cast_precision_loss)] // column lengths are far below f64's exact-integer ceiling.
        let count = sorted.len() as f64;
        let mean = sorted.iter().sum::<f64>() / count;

        let median = if sorted.len() % 2 == 0 {
            let mid = sorted.len() / 2;
            f64::midpoint(sorted[mid - 1], sorted[mid])
        } else {
            sorted[sorted.len() / 2]
        };

        let variance = sorted.iter().map(|value| (value - mean).powi(2)).sum::<f64>() / count;
        let standard_deviation = variance.sqrt();

        Self {
            minimum,
            maximum,
            mean,
            median,
            standard_deviation,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[allow(clippy::float_cmp)] // exact values, hand-computed from small fixed inputs.
    fn matches_hand_computed_statistics() {
        let summary = DistributionSummary::derive(&[2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]);
        assert_eq!(summary.minimum(), 2.0);
        assert_eq!(summary.maximum(), 9.0);
        assert_eq!(summary.mean(), 5.0);
        assert_eq!(summary.median(), 4.5);
        assert_eq!(summary.standard_deviation(), 2.0);
    }

    #[test]
    #[allow(clippy::float_cmp)]
    fn odd_length_median_is_the_middle_element() {
        let summary = DistributionSummary::derive(&[3.0, 1.0, 2.0]);
        assert_eq!(summary.median(), 2.0);
    }

    #[test]
    fn result_is_independent_of_input_order() {
        let ascending = DistributionSummary::derive(&[1.0, 2.0, 3.0, 4.0, 5.0]);
        let shuffled = DistributionSummary::derive(&[4.0, 1.0, 5.0, 2.0, 3.0]);
        assert_eq!(ascending, shuffled);
    }

    #[test]
    #[should_panic(expected = "no values")]
    fn panics_on_empty_input() {
        let _ = DistributionSummary::derive(&[]);
    }
}
EOF

echo "==> Writing crates/rasica-structural-inference/src/category.rs..."
cat > crates/rasica-structural-inference/src/category.rs << 'EOF'
//! `CategorySummary` (§6.7's "categorical variables" deliverable).

use std::collections::HashMap;

use rasica_dataset::value::Value;

/// A deterministic summary of a `Categorical` column: each distinct
/// non-null value observed, together with its occurrence count.
#[derive(Debug, Clone, PartialEq)]
pub struct CategorySummary {
    /// Sorted by `label` (not by frequency): frequency-sorting would make
    /// field order depend on the data's row-count distribution, which is
    /// the same fingerprint-determinism hazard
    /// [`crate::distribution::DistributionSummary`] documents for sort
    /// order (Document 00E §4.3).
    categories: Vec<CategoryCount>,
}

impl CategorySummary {
    /// Every distinct category observed, in ascending `label` order.
    #[must_use]
    pub fn categories(&self) -> &[CategoryCount] {
        &self.categories
    }

    /// Derives a summary from `values`, a `Categorical` column's non-null
    /// values in dataset row order.
    pub(crate) fn derive(values: &[&Value]) -> Self {
        let mut counts: HashMap<String, u64> = HashMap::new();
        for value in values {
            *counts.entry(render_label(value)).or_insert(0) += 1;
        }

        let mut categories: Vec<CategoryCount> =
            counts.into_iter().map(|(label, count)| CategoryCount { label, count }).collect();
        categories.sort_by(|a, b| a.label.cmp(&b.label));

        Self { categories }
    }
}

/// One distinct value's occurrence count within a `Categorical` column.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CategoryCount {
    label: String,
    count: u64,
}

impl CategoryCount {
    /// The category's canonical text rendering.
    #[must_use]
    pub fn label(&self) -> &str {
        &self.label
    }

    /// The number of rows in which this value occurred.
    #[must_use]
    pub fn count(&self) -> u64 {
        self.count
    }
}

/// Renders a non-null [`Value`] to its canonical text form.
///
/// # Panics
///
/// Panics if given [`Value::Null`]: categories are derived only from
/// non-null values (nulls are Null Analysis's concern, not this crate's —
/// see Document 00E §0's Phase 4 boundary note), so a `Null` reaching
/// here is a caller defect, not a data condition.
fn render_label(value: &Value) -> String {
    match value {
        Value::Null => unreachable!("CategorySummary::derive is never called with a null value"),
        Value::Boolean(b) => b.to_string(),
        Value::Integer(i) => i.to_string(),
        Value::Float(f) => f.to_string(),
        Value::Text(s) => s.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[allow(clippy::unwrap_used)]
    fn counts_and_sorts_by_label() {
        let values = [
            Value::Text("gold".into()),
            Value::Text("bronze".into()),
            Value::Text("gold".into()),
            Value::Text("silver".into()),
        ];
        let refs: Vec<&Value> = values.iter().collect();
        let summary = CategorySummary::derive(&refs);

        let labels: Vec<&str> = summary.categories().iter().map(CategoryCount::label).collect();
        assert_eq!(labels, ["bronze", "gold", "silver"]);

        let gold = summary.categories().iter().find(|c| c.label() == "gold").unwrap();
        assert_eq!(gold.count(), 2);
    }

    #[test]
    fn is_independent_of_input_order() {
        let a = [Value::Boolean(true), Value::Boolean(false), Value::Boolean(true)];
        let b = [Value::Boolean(false), Value::Boolean(true), Value::Boolean(true)];
        let a_refs: Vec<&Value> = a.iter().collect();
        let b_refs: Vec<&Value> = b.iter().collect();
        assert_eq!(CategorySummary::derive(&a_refs), CategorySummary::derive(&b_refs));
    }
}
EOF

echo "==> Writing crates/rasica-structural-inference/src/relationship.rs..."
cat > crates/rasica-structural-inference/src/relationship.rs << 'EOF'
//! `RelationshipEvidence` (§6.7's "relationships" deliverable, §5.7):
//! deterministic, mechanically-observed candidate-key evidence between
//! `Identifier`-classified columns of a single Dataset.
//!
//! This is deliberately scoped to *evidence*, not a resolved semantic
//! relationship — interpreting this evidence into an actual knowledge
//! graph edge is the Knowledge Engine's job (Phase 6), not this crate's.

use std::collections::HashSet;

use crate::value_key::ValueKey;

/// Identifies one column within the Dataset being inferred over, by
/// position.
///
/// Scoped to a single Dataset for this phase (§5.7 restricts relationship
/// evidence to identifier pairs within one Dataset; cross-Dataset evidence
/// is an explicitly deferred capability) — see the generating script's
/// ADAPTATION NOTE for why this does not also carry a Dataset identity
/// handle.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ColumnRef {
    column_position: usize,
}

impl ColumnRef {
    pub(crate) fn new(column_position: usize) -> Self {
        Self { column_position }
    }

    /// The 0-based column index within the Dataset's schema.
    #[must_use]
    pub fn column_position(&self) -> usize {
        self.column_position
    }
}

/// The specific, mechanically-checkable relationship a piece of evidence
/// asserts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RelationshipKind {
    /// Both `left` and `right` are classified `Identifier`, and every
    /// non-null value in `right` also appears as a value in `left`
    /// (§5.7's candidate foreign-key check). This does not distinguish
    /// which side is the "parent" — that is a semantic judgement out of
    /// scope here — it only records that the subset relationship holds in
    /// this direction.
    ValueSubset,
}

/// A single piece of deterministic, mechanically-observed evidence that
/// two columns may be related.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RelationshipEvidence {
    left: ColumnRef,
    right: ColumnRef,
    kind: RelationshipKind,
}

impl RelationshipEvidence {
    /// The column whose value set was checked as the (candidate) superset.
    #[must_use]
    pub fn left(&self) -> ColumnRef {
        self.left
    }

    /// The column whose value set was checked as the (candidate) subset.
    #[must_use]
    pub fn right(&self) -> ColumnRef {
        self.right
    }

    /// The specific relationship this evidence asserts.
    #[must_use]
    pub fn kind(&self) -> RelationshipKind {
        self.kind
    }
}

/// Computes §5.7's `ValueSubset` evidence over every ordered pair of
/// distinct columns in `identifier_columns` — each entry being an
/// `Identifier`-classified column's position and the set of its non-null
/// values.
///
/// Iterates ordered pairs `(left, right)` with `left != right` in
/// ascending `(left_position, right_position)` order, so that evidence
/// order never depends on hash-map iteration order (the same determinism
/// concern `value_key`/`ValueKey` exists to satisfy elsewhere in this
/// crate) — only on the fixed column order the schema itself declares.
pub(crate) fn detect_value_subset_evidence(
    identifier_columns: &[(usize, HashSet<ValueKey>)],
) -> Vec<RelationshipEvidence> {
    let mut evidence = Vec::new();

    for (left_position, left_values) in identifier_columns {
        for (right_position, right_values) in identifier_columns {
            if left_position == right_position {
                continue;
            }
            if right_values.is_empty() {
                continue; // a non-empty subset is required (§5.7).
            }
            if right_values.is_subset(left_values) {
                evidence.push(RelationshipEvidence {
                    left: ColumnRef::new(*left_position),
                    right: ColumnRef::new(*right_position),
                    kind: RelationshipKind::ValueSubset,
                });
            }
        }
    }

    evidence
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key_set(values: &[i64]) -> HashSet<ValueKey> {
        values.iter().map(|v| ValueKey::from(&rasica_dataset::value::Value::Integer(*v))).collect()
    }

    #[test]
    fn detects_a_subset_relationship_in_one_direction() {
        let columns = [(0, key_set(&[1, 2, 3, 4, 5])), (1, key_set(&[2, 4]))];
        let evidence = detect_value_subset_evidence(&columns);
        assert_eq!(evidence.len(), 1);
        assert_eq!(evidence[0].left().column_position(), 0);
        assert_eq!(evidence[0].right().column_position(), 1);
        assert_eq!(evidence[0].kind(), RelationshipKind::ValueSubset);
    }

    #[test]
    fn identical_value_sets_produce_evidence_in_both_directions() {
        let columns = [(0, key_set(&[1, 2, 3])), (1, key_set(&[1, 2, 3]))];
        let evidence = detect_value_subset_evidence(&columns);
        assert_eq!(evidence.len(), 2);
    }

    #[test]
    fn disjoint_columns_produce_no_evidence() {
        let columns = [(0, key_set(&[1, 2, 3])), (1, key_set(&[4, 5, 6]))];
        assert!(detect_value_subset_evidence(&columns).is_empty());
    }

    #[test]
    fn empty_right_hand_column_produces_no_evidence() {
        let columns = [(0, key_set(&[1, 2, 3])), (1, HashSet::new())];
        assert!(detect_value_subset_evidence(&columns).is_empty());
    }
}
EOF

echo "==> Writing crates/rasica-structural-inference/src/knowledge.rs..."
cat > crates/rasica-structural-inference/src/knowledge.rs << 'EOF'
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
///
/// GAP FIX (Phase 6 bridging note): `name` is new relative to the
/// original scaffold. §4.1's "column names are never consulted by any
/// heuristic" constraint is about *classification* (`role.rs`'s
/// heuristics remain name-blind, and this field is populated only after
/// `classify` has already run — see `infer` below); it does not forbid
/// *storing* the name for a downstream consumer's benefit. Without this
/// field, a column is identifiable only by position, which left the
/// Knowledge Engine (Phase 6) needing the original `Dataset` passed
/// alongside `StructuralKnowledge` just to recover column names for
/// graph-node labels — and needing to guard against the two arguments
/// ever referring to different Datasets. Storing `name` here removes
/// both problems.
#[derive(Debug, Clone, PartialEq)]
pub struct ColumnKnowledge {
    name: String,
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
        name: impl Into<String>,
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
        Self { name: name.into(), role, distribution, categories }
    }

    /// This column's name, as declared in the originating Dataset's
    /// `Schema` (Phase 6 gap fix, §0). Recorded for downstream labelling
    /// only — no heuristic in `role.rs` reads this field, and none may.
    #[must_use]
    pub fn name(&self) -> &str {
        &self.name
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
pub fn infer(dataset: &Dataset, origin: impl Into<String>) -> Result<StructuralKnowledge, InferenceError> {
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
        let distinct: HashSet<ValueKey> = non_null_values.iter().map(|value| ValueKey::from(*value)).collect();
        let distinct_count = distinct.len();

        let role = classify(this_column_type, row_count, non_null_values, distinct_count);

        let distribution = (role == VariableRole::Continuous).then(|| {
            let numeric: Vec<f64> = non_null_values.iter().filter_map(|value| as_f64(value)).collect();
            DistributionSummary::derive(&numeric)
        });

        let categories = (role == VariableRole::Categorical).then(|| CategorySummary::derive(non_null_values));

        if role == VariableRole::Identifier {
            identifier_columns.push((index, distinct));
        }

        columns.push(ColumnKnowledge::new(column.name(), role, distribution, categories));
    }

    let relationships = detect_value_subset_evidence(&identifier_columns);

    Ok(StructuralKnowledge {
        origin: origin.into(),
        columns,
        relationships,
    })
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
        let schema = Schema::new(vec![Column::new("col", col_type)]).expect("schema is well-formed");
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
    fn column_knowledge_carries_the_schema_column_name() {
        let dataset = dataset_with_rows(ColumnType::Integer, vec![Value::Integer(1), Value::Integer(2)]);
        let knowledge = infer(&dataset, "test").expect("non-empty dataset infers successfully");
        assert_eq!(knowledge.column(0).expect("column 0 exists").name(), "col");
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
        let values = vec![Value::Text("a".into()), Value::Text("b".into()), Value::Text("a".into())];
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
EOF

echo "==> Writing crates/rasica-structural-inference/src/lib.rs..."
cat > crates/rasica-structural-inference/src/lib.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-structural-inference/src/prelude.rs..."
cat > crates/rasica-structural-inference/src/prelude.rs << 'EOF'
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
EOF

echo "==> Writing crates/rasica-structural-inference/benches/structural_inference.rs..."
cat > crates/rasica-structural-inference/benches/structural_inference.rs << 'EOF'
//! Benchmarks a full `infer` pass over a synthetic, deterministically
//! generated Dataset with a representative mix of column shapes (an
//! Identifier, a Continuous, and a Categorical column), isolating
//! inference cost from ingestion cost — the same isolation rationale
//! `rasica-validation`'s own `validation` benchmark documents (Phase 4).

#![allow(missing_docs, clippy::expect_used, clippy::unwrap_used, clippy::cast_possible_wrap, clippy::cast_precision_loss)]

use criterion::{criterion_group, criterion_main, Criterion};
use rasica_dataset::{
    dataset::{Dataset, DatasetBuilder},
    row::Row,
    schema::{Column, ColumnType, Schema},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};
use rasica_structural_inference::infer;

fn synthetic_dataset(rows: usize) -> Dataset {
    let schema = Schema::new(vec![
        Column::new("id", ColumnType::Integer),
        Column::new("amount", ColumnType::Float),
        Column::new("tier", ColumnType::Text),
    ])
    .expect("synthetic schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    let tiers = ["bronze", "silver", "gold"];
    for r in 0..rows {
        let values = vec![
            Value::Integer(r as i64),
            Value::Float((r % 97) as f64 * 1.5),
            Value::Text(tiers[r % tiers.len()].to_string()),
        ];
        builder.push_row(Row::new(values)).expect("synthetic row matches synthetic schema");
    }
    builder.build(SourceMetadata::new(SourceFormat::InMemory, "synthetic"))
}

fn bench_infer(c: &mut Criterion) {
    let dataset = synthetic_dataset(10_000);
    c.bench_function("infer_10k_rows_3_cols", |b| {
        b.iter(|| infer(&dataset, "synthetic").expect("synthetic dataset is non-empty"));
    });
}

criterion_group!(benches, bench_infer);
criterion_main!(benches);
EOF

echo "==> Generating tests/fixtures/ (hand-labelled corpus, Document 00E §7.1)..."
python3 - << 'PYEOF'
import json

names = [
    "Ada Lovelace", "Grace Hopper", "Alan Turing", "Katherine Johnson",
    "Margaret Hamilton", "Alonzo Church", "Barbara Liskov", "John McCarthy",
    "Edsger Dijkstra", "Donald Knuth", "Frances Allen", "Radia Perlman",
    "Vint Cerf", "Tim Berners-Lee", "Linus Torvalds", "Guido van Rossum",
    "James Gosling", "Anita Borg", "Shafi Goldwasser", "Whitfield Diffie",
    "Martin Hellman", "Adele Goldberg", "Dennis Ritchie", "Ken Thompson",
]  # 24 distinct names.

signup_dates = [f"2020-{(i % 12) + 1:02d}-{(i % 27) + 1:02d}" for i in range(29)]  # 29 distinct dates.
tiers = ["bronze", "silver", "gold"]

customers_rows = []
for i in range(30):
    customer_id = i + 1
    name = names[i % len(names)]              # 24 distinct values across 30 rows.
    signup_date = signup_dates[i % len(signup_dates)]  # 29 distinct values across 30 rows.
    tier = tiers[i % len(tiers)]               # 3 distinct values.
    lifetime_value = round(100.0 + i * 13.37, 2)       # 30 distinct values.
    customers_rows.append((customer_id, name, signup_date, tier, f"{lifetime_value:.2f}"))

with open("crates/rasica-structural-inference/tests/fixtures/customers_ground_truth.csv", "w") as f:
    f.write("id,name,signup_date,tier,lifetime_value\n")
    for row in customers_rows:
        f.write(",".join(str(field) for field in row) + "\n")

statuses = ["ok", "fault"]
recorded_ats = [f"2021-{(i % 12) + 1:02d}-{(i % 27) + 1:02d}T{(i % 24):02d}:{(i % 60):02d}:00" for i in range(29)]

sensor_rows = []
for i in range(30):
    reading_id = i + 1
    sensor_status = statuses[i % len(statuses)]        # 2 distinct values.
    temperature_celsius = round(15.0 + i * 0.37, 2)    # 30 distinct values.
    recorded_at = recorded_ats[i % len(recorded_ats)]  # 29 distinct values across 30 rows.
    sensor_rows.append((reading_id, sensor_status, f"{temperature_celsius:.2f}", recorded_at))

with open("crates/rasica-structural-inference/tests/fixtures/sensor_readings_ground_truth.csv", "w") as f:
    f.write("reading_id,sensor_status,temperature_celsius,recorded_at\n")
    for row in sensor_rows:
        f.write(",".join(str(field) for field in row) + "\n")

ground_truth = {
    "customers_ground_truth.csv": {
        "id": "Identifier",
        "name": "Unclassified",
        "signup_date": "Temporal",
        "tier": "Categorical",
        "lifetime_value": "Continuous",
    },
    "sensor_readings_ground_truth.csv": {
        "reading_id": "Identifier",
        "sensor_status": "Categorical",
        "temperature_celsius": "Continuous",
        "recorded_at": "Temporal",
    },
}

with open("crates/rasica-structural-inference/tests/fixtures/ground_truth.json", "w") as f:
    json.dump(ground_truth, f, indent=2, sort_keys=True)
    f.write("\n")
PYEOF

echo "==> Writing crates/rasica-structural-inference/tests/accuracy.rs..."
cat > crates/rasica-structural-inference/tests/accuracy.rs << 'EOF'
//! The accuracy benchmark (Document 00E §7.2, implementing §15.8's own
//! Verification clause: "Benchmark against manually classified
//! datasets").
//!
//! For each fixture in `tests/fixtures/`, ingests it, runs `infer`, and
//! compares the resulting `VariableRole` for every column against
//! `tests/fixtures/ground_truth.json`'s recorded expectation — read
//! directly from the file rather than hand-duplicated as Rust literals,
//! so the ground truth and this test's assertions cannot silently drift
//! apart across edits (§7.1).
//!
//! Per §7.2: with only two small fixtures as specified here (nine columns
//! total), the practical initial assertion is exact agreement on every
//! single column, a 100% pass rate — the 95% threshold from §1.2 is
//! intended to apply once the corpus is grown large enough for a
//! percentage to be statistically meaningful rather than an artifact of
//! a tiny sample.

use std::collections::HashMap;
use std::fs::File;
use std::io::BufReader;
use std::path::Path;

use rasica_ingestion::csv::{self, CsvOptions};
use rasica_structural_inference::VariableRole;

/// Parses the JSON string form of a `VariableRole` recorded in
/// `ground_truth.json` back into the enum, for comparison against
/// `infer`'s actual output.
fn parse_role(name: &str) -> VariableRole {
    match name {
        "Identifier" => VariableRole::Identifier,
        "Continuous" => VariableRole::Continuous,
        "Categorical" => VariableRole::Categorical,
        "Temporal" => VariableRole::Temporal,
        "Unclassified" => VariableRole::Unclassified,
        other => panic!("ground_truth.json contains an unrecognised VariableRole name: {other:?}"),
    }
}

#[test]
#[allow(clippy::expect_used)]
fn infer_matches_manually_classified_ground_truth() {
    let fixtures_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");

    let ground_truth_raw =
        std::fs::read_to_string(fixtures_dir.join("ground_truth.json")).expect("ground_truth.json is present");
    let ground_truth: HashMap<String, HashMap<String, String>> =
        serde_json::from_str(&ground_truth_raw).expect("ground_truth.json is well-formed");

    let mut total_columns = 0usize;
    let mut matching_columns = 0usize;
    let mut mismatches = Vec::new();

    // Sorted for a deterministic test-failure message order, independent
    // of filesystem directory-listing order.
    let mut fixture_names: Vec<&String> = ground_truth.keys().collect();
    fixture_names.sort();

    for fixture_name in fixture_names {
        let expected_roles = &ground_truth[fixture_name];
        let fixture_path = fixtures_dir.join(fixture_name);

        // rasica_ingestion::csv::read takes (impl Read, origin, CsvOptions),
        // matching Document 00C's actual signature exactly.
        let file = File::open(&fixture_path)
            .unwrap_or_else(|error| panic!("failed to open fixture {fixture_name:?}: {error}"));
        let dataset = csv::read(BufReader::new(file), fixture_name.clone(), CsvOptions::default())
            .unwrap_or_else(|error| panic!("failed to ingest fixture {fixture_name:?}: {error}"));

        let knowledge = rasica_structural_inference::infer(&dataset, fixture_name.clone())
            .expect("every fixture has at least one row");

        let schema = dataset.schema();
        for (index, column) in schema.columns().iter().enumerate() {
            let column_name = column.name();
            let Some(expected_name) = expected_roles.get(column_name) else {
                panic!("ground_truth.json has no entry for {fixture_name}::{column_name}");
            };
            let expected = parse_role(expected_name);
            let actual = knowledge.column(index).expect("column index is in range").role();

            total_columns += 1;
            if actual == expected {
                matching_columns += 1;
            } else {
                mismatches.push(format!(
                    "{fixture_name}::{column_name}: expected {expected:?}, got {actual:?}"
                ));
            }
        }
    }

    assert!(
        mismatches.is_empty(),
        "structural inference disagreed with manually classified ground truth on {} of {} column(s):\n{}",
        mismatches.len(),
        total_columns,
        mismatches.join("\n")
    );

    // Document 00E §1.2's exit criterion, restated as the interim
    // "100% on this small corpus" reading (§7.2) that the 95% threshold is
    // meant to generalise once the fixture corpus grows.
    #[allow(clippy::cast_precision_loss)]
    let accuracy = matching_columns as f64 / total_columns as f64;
    assert!(accuracy >= 0.95, "classification accuracy {accuracy:.1}% is below the 95% exit criterion (§1.2)");
}
EOF

# ---------------------------------------------------------------------------
# Patch: tests/workspace_smoke/Cargo.toml
# ---------------------------------------------------------------------------

echo "==> Patching tests/workspace_smoke/Cargo.toml (add rasica-structural-inference dep)..."
if ! grep -q "rasica-structural-inference" tests/workspace_smoke/Cargo.toml; then
  # Ensure the file ends with a newline before appending, to avoid the
  # same concatenation bug Phase 4's rollout notes guarding against.
  [ -n "$(tail -c1 tests/workspace_smoke/Cargo.toml)" ] && echo >> tests/workspace_smoke/Cargo.toml
  cat >> tests/workspace_smoke/Cargo.toml << 'EOF'
rasica-structural-inference = { path = "../../crates/rasica-structural-inference", version = "0.1.0" }
EOF
else
  echo "    (already patched, skipping)"
fi

# ---------------------------------------------------------------------------
# Patch: tests/workspace_smoke/tests/smoke.rs
# ---------------------------------------------------------------------------

echo "==> Extending tests/workspace_smoke/tests/smoke.rs (Phase 5 test)..."
if ! grep -q "infers_structural_knowledge_from_a_hand_built_dataset" tests/workspace_smoke/tests/smoke.rs; then
  cat >> tests/workspace_smoke/tests/smoke.rs << 'EOF'

#[test]
#[allow(clippy::expect_used, clippy::items_after_statements)]
fn infers_structural_knowledge_from_a_hand_built_dataset() {
    use rasica_dataset::{
        dataset::DatasetBuilder,
        row::Row,
        schema::{Column, ColumnType, Schema},
        source::{SourceFormat, SourceMetadata},
        value::Value,
    };
    use rasica_structural_inference::{infer, VariableRole};

    let schema = Schema::new(vec![
        Column::new("id", ColumnType::Integer),
        Column::new("tier", ColumnType::Text),
    ])
    .expect("hand-written schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    let tiers = ["bronze", "silver", "gold", "bronze", "silver"];
    for (i, tier) in tiers.iter().enumerate() {
        builder
            .push_row(Row::new(vec![Value::Integer(i as i64), Value::Text((*tier).into())]))
            .expect("hand-written row matches hand-written schema");
    }
    let dataset = builder.build(SourceMetadata::new(SourceFormat::InMemory, "smoke"));

    let knowledge = infer(&dataset, "smoke").expect("hand-built dataset has rows");

    assert_eq!(knowledge.column(0).expect("column 0 exists").role(), VariableRole::Identifier);
    assert_eq!(knowledge.column(1).expect("column 1 exists").role(), VariableRole::Categorical);

    // Reuses rasica-validation's own smoke assertion pattern (Phase 4):
    // Structural Knowledge is Tier 1.
    fn assert_immutable<T: rasica_core::prelude::Immutable>(_: &T) {}
    assert_immutable(&knowledge);
}
EOF
else
  echo "    (already patched, skipping)"
fi

echo ""
echo "==> Done. Phase 5 (rasica-structural-inference) scaffolded."
echo ""
echo "Next steps:"
echo "  1. cargo check --workspace"
echo "  2. cargo nextest run --workspace"
echo "  3. cargo clippy --workspace --all-targets -- -D warnings"
echo "  4. cargo fmt --all"
echo "  5. cargo bench --workspace"
echo "  6. cargo deny check"
echo ""
echo "Notes:"
echo "  - This crate assumes 'Dataset::rows() -> &[Row]', 'Row::values() ->"
echo "    &[Value]', 'Column::name() -> &str', and 'Column::column_type() ->"
echo "    ColumnType' on your Phase 2 rasica-dataset crate (the same four"
echo "    names rasica-validation already assumes). If any differ, the only"
echo "    file that needs editing is"
echo "    crates/rasica-structural-inference/src/dataset_view.rs."
echo "  - tests/accuracy.rs calls rasica_ingestion::csv::read(reader, origin,"
echo "    CsvOptions), matching Document 00C's actual signature."
echo "  - Two [DRAFT DECISION] points from Document 00E carried into code"
echo "    as named constants for easy review/adjustment:"
echo "    'role::TEMPORAL_PARSE_THRESHOLD' (90%) and"
echo "    'role::continuous_categorical_threshold' (max(20, row_count/20))."
echo "  - See this script's own header comment for how it resolves an"
echo "    internal inconsistency between Document 00E's §5.1 ordering list"
echo "    and its §5.3/§5.4/§5.6 worked examples (Continuous-before-"
echo "    Categorical, and a bounded-above Categorical range)."
echo ""
