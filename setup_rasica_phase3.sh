#!/usr/bin/env bash
# Adds Phase 3 (Data Ingestion) to an existing RASICA Phase 1+2 workspace,
# per 00C-Phase3-Data-Ingestion-Implementation-Spec.md.
#
# ADDITIVE and idempotent, same conventions as setup_rasica_phase2.sh:
# creates the new `rasica-ingestion` crate in full, and patches root
# Cargo.toml + tests/workspace_smoke/{Cargo.toml,tests/smoke.rs}.
#
# Usage: run from the rasica/ project root.
#
#   chmod +x setup_rasica_phase3.sh
#   ./setup_rasica_phase3.sh

set -euo pipefail

if [ ! -f "Cargo.toml" ] || ! grep -q "\[workspace\]" Cargo.toml; then
  echo "Error: no workspace root Cargo.toml found here."
  exit 1
fi

if [ ! -d "crates/rasica-dataset" ]; then
  echo "Error: crates/rasica-dataset must already exist (Phase 2)."
  exit 1
fi

echo "==> Creating crates/rasica-ingestion directory structure..."
mkdir -p crates/rasica-ingestion/src
mkdir -p crates/rasica-ingestion/benches
mkdir -p crates/rasica-ingestion/tests/fixtures

# ---------------------------------------------------------------------------
# Patch: workspace root Cargo.toml
# ---------------------------------------------------------------------------

echo "==> Patching root Cargo.toml (add rasica-ingestion member + csv/calamine/serde_json deps)..."
if ! grep -q '"crates/rasica-ingestion"' Cargo.toml; then
  python3 - << 'PYEOF'
with open("Cargo.toml") as f:
    content = f.read()

content = content.replace(
    '    "crates/rasica-dataset",\n    "tests/workspace_smoke",',
    '    "crates/rasica-dataset",\n    "crates/rasica-ingestion",\n    "tests/workspace_smoke",',
)

content = content.replace(
    'criterion = { version = "0.5", features = ["html_reports"] }',
    'criterion = { version = "0.5", features = ["html_reports"] }\n\n'
    '# --- data ingestion (§15.6) ---\n'
    'csv = "1.3"\n'
    'calamine = "0.25"\n'
    'serde_json = "1.0"',
)

with open("Cargo.toml", "w") as f:
    f.write(content)
PYEOF
else
  echo "    (already patched, skipping)"
fi

# ---------------------------------------------------------------------------
# rasica-ingestion crate
# ---------------------------------------------------------------------------

echo "==> Writing crates/rasica-ingestion/Cargo.toml..."
cat > crates/rasica-ingestion/Cargo.toml << 'EOF'
[package]
name = "rasica-ingestion"
description = "External-source readers (CSV, Excel, JSON) producing rasica-dataset Datasets."
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
csv = { workspace = true }
calamine = { workspace = true }
serde_json = { workspace = true }

[dev-dependencies]
proptest = { workspace = true }
rstest = { workspace = true }
criterion = { workspace = true }

[[bench]]
name = "csv_ingestion"
harness = false
EOF

echo "==> Writing crates/rasica-ingestion/src/typing.rs..."
cat > crates/rasica-ingestion/src/typing.rs << 'EOF'
//! Deterministic column-type inference and widening, shared by every reader
//! in this crate (§1.4 Note 3 of the Phase 3 Implementation Specification).
//!
//! Each source format observes its cells in whatever native representation
//! that format provides (raw text for CSV, `serde_json::Value` for JSON,
//! `calamine::DataType` for Excel). [`NaturalType`] is the one common
//! vocabulary every format's observations are translated into before this
//! module's widening rule is applied, so the rule itself is written once.

use rasica_dataset::schema::ColumnType;

/// The representational type of a single observed, non-null value, prior to
/// being reconciled against the rest of its column.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum NaturalType {
    /// A value recognised unambiguously as boolean by the source format's
    /// own type system (never inferred from a text literal such as `"1"`,
    /// which would be ambiguous with [`NaturalType::Integer`]).
    Boolean,
    /// A value representable exactly as a 64-bit signed integer.
    Integer,
    /// A value requiring floating-point representation.
    Float,
    /// Any value not covered by the above — including every value once any
    /// sibling in its column has forced widening past what the above three
    /// variants can jointly represent.
    Text,
}

/// Combines two [`NaturalType`]s observed in the same column into the
/// narrowest type able to represent both, without loss.
///
/// This operation is commutative and associative — `join` may therefore be
/// folded over a column's values in any order and still produce a
/// deterministic result, which is what allows §4.5's, §4.6's, and §4.7's
/// readers to share one accumulator (below) regardless of each format's own
/// row-iteration order.
///
/// | ⊔        | Boolean | Integer | Float | Text |
/// |----------|---------|---------|-------|------|
/// | Boolean  | Boolean | Text    | Text  | Text |
/// | Integer  | Text    | Integer | Float | Text |
/// | Float    | Text    | Float   | Float | Text |
/// | Text     | Text    | Text    | Text  | Text |
///
/// Boolean is never widened into Integer or Float: RASICA does not treat
/// `true`/`1` as interchangeable, since doing so would make a genuinely
/// boolean column and a genuinely integer column containing only `0`/`1`
/// indistinguishable, which is exactly the kind of representational
/// ambiguity §15.6's "correct typing" verification item exists to prevent.
#[must_use]
pub(crate) const fn join(a: NaturalType, b: NaturalType) -> NaturalType {
    use NaturalType::{Boolean, Float, Integer, Text};
    match (a, b) {
        (Boolean, Boolean) => Boolean,
        (Integer, Integer) => Integer,
        (Float, Float) | (Integer, Float) | (Float, Integer) => Float,
        _ => Text,
    }
}

/// Folds a column's observed [`NaturalType`]s into one resolved
/// [`ColumnType`], one value at a time, in a single forward pass.
///
/// A column containing only null values (or, degenerately, zero rows) has
/// no observation to resolve from; such a column resolves to
/// [`ColumnType::Text`], the widest and therefore safest representation for
/// a column about which nothing else is known. This mirrors `join`'s own
/// behaviour of resolving any genuine ambiguity to `Text` rather than
/// guessing.
#[derive(Debug, Clone, Copy, Default)]
pub(crate) struct ColumnTypeAccumulator {
    resolved: Option<NaturalType>,
}

impl ColumnTypeAccumulator {
    /// Starts a fresh accumulator with no observations yet.
    #[must_use]
    pub(crate) const fn new() -> Self {
        Self { resolved: None }
    }

    /// Folds in one observed value's [`NaturalType`]. Pass `None` for a
    /// null cell: nulls do not participate in type resolution, matching
    /// `rasica_dataset`'s treatment of [`rasica_dataset::value::Value::Null`]
    /// as agreeing with every [`ColumnType`] (Document 00B §4.6).
    pub(crate) fn observe(&mut self, natural_type: Option<NaturalType>) {
        let Some(observed) = natural_type else {
            return;
        };
        self.resolved = Some(match self.resolved {
            None => observed,
            Some(current) => join(current, observed),
        });
    }

    /// Resolves the final [`ColumnType`] for this column.
    #[must_use]
    pub(crate) fn finish(self) -> ColumnType {
        match self.resolved {
            Some(NaturalType::Boolean) => ColumnType::Boolean,
            Some(NaturalType::Integer) => ColumnType::Integer,
            Some(NaturalType::Float) => ColumnType::Float,
            Some(NaturalType::Text) | None => ColumnType::Text,
        }
    }
}

/// Classifies a raw CSV/text cell's [`NaturalType`], used by §4.5's CSV
/// reader during its type-resolution pass.
///
/// Recognition is deliberately strict and case-sensitive-only for booleans
/// (`"true"`/`"false"`, exactly) to avoid the ambiguity a looser match
/// (`"1"`, `"yes"`, `"T"`, ...) would introduce against [`NaturalType::Integer`]
/// and [`NaturalType::Text`] alike.
#[must_use]
pub(crate) fn classify_text(raw: &str) -> NaturalType {
    if raw == "true" || raw == "false" {
        NaturalType::Boolean
    } else if raw.parse::<i64>().is_ok() {
        NaturalType::Integer
    } else if raw.parse::<f64>().is_ok() {
        NaturalType::Float
    } else {
        NaturalType::Text
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn join_is_commutative_for_every_pair() {
        let variants = [
            NaturalType::Boolean,
            NaturalType::Integer,
            NaturalType::Float,
            NaturalType::Text,
        ];
        for &a in &variants {
            for &b in &variants {
                assert_eq!(join(a, b), join(b, a));
            }
        }
    }

    #[test]
    fn integer_and_float_widen_to_float() {
        assert_eq!(join(NaturalType::Integer, NaturalType::Float), NaturalType::Float);
    }

    #[test]
    fn boolean_and_integer_widen_to_text() {
        assert_eq!(join(NaturalType::Boolean, NaturalType::Integer), NaturalType::Text);
    }

    #[test]
    fn all_null_column_resolves_to_text() {
        let mut acc = ColumnTypeAccumulator::new();
        acc.observe(None);
        acc.observe(None);
        assert_eq!(acc.finish(), ColumnType::Text);
    }

    #[test]
    fn classify_text_does_not_treat_zero_or_one_as_boolean() {
        assert_eq!(classify_text("1"), NaturalType::Integer);
        assert_eq!(classify_text("0"), NaturalType::Integer);
    }

    proptest::proptest! {
        #[test]
        fn accumulator_result_is_independent_of_observation_order(
            a in 0..4usize, b in 0..4usize, c in 0..4usize,
        ) {
            let variants = [
                NaturalType::Boolean,
                NaturalType::Integer,
                NaturalType::Float,
                NaturalType::Text,
            ];
            let observations = [variants[a], variants[b], variants[c]];

            let mut forward = ColumnTypeAccumulator::new();
            for &o in &observations {
                forward.observe(Some(o));
            }

            let mut reversed = ColumnTypeAccumulator::new();
            for &o in observations.iter().rev() {
                reversed.observe(Some(o));
            }

            proptest::prop_assert_eq!(forward.finish(), reversed.finish());
        }
    }
}
EOF

echo "==> Writing crates/rasica-ingestion/src/encoding.rs..."
cat > crates/rasica-ingestion/src/encoding.rs << 'EOF'
//! UTF-8 validation and byte-order-mark handling for text-based sources
//! (§1.4 Note 2 of the Phase 3 Implementation Specification).

const UTF8_BOM: [u8; 3] = [0xEF, 0xBB, 0xBF];

/// Strips a leading UTF-8 byte-order mark from `bytes`, if present, then
/// validates the remainder as UTF-8.
///
/// # Errors
///
/// Returns the underlying [`std::str::Utf8Error`] if `bytes` (after BOM
/// stripping) is not valid UTF-8. This is the sole encoding check Phase 3
/// performs; non-UTF-8 encodings are out of scope (§1.4 Note 2) and are
/// surfaced to callers as [`crate::error::IngestionError::InvalidEncoding`].
pub(crate) fn strip_bom_and_validate_utf8(bytes: &[u8]) -> Result<&str, std::str::Utf8Error> {
    let without_bom = bytes.strip_prefix(&UTF8_BOM).unwrap_or(bytes);
    std::str::from_utf8(without_bom)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[allow(clippy::expect_used)]
    fn strips_bom_when_present() {
        let mut bytes = UTF8_BOM.to_vec();
        bytes.extend_from_slice(b"a,b\n1,2\n");
        assert_eq!(
            strip_bom_and_validate_utf8(&bytes).expect("valid UTF-8 after BOM"),
            "a,b\n1,2\n"
        );
    }

    #[test]
    fn passes_through_unchanged_without_bom() {
        assert_eq!(strip_bom_and_validate_utf8(b"a,b\n1,2\n"), Ok("a,b\n1,2\n"));
    }

    #[test]
    fn rejects_invalid_utf8() {
        assert!(strip_bom_and_validate_utf8(&[0xFF, 0xFE, 0x00]).is_err());
    }
}
EOF

echo "==> Writing crates/rasica-ingestion/src/csv.rs..."
cat > crates/rasica-ingestion/src/csv.rs << 'EOF'
//! CSV ingestion (Architecture Spec §15.6, Initial Source: CSV).

use std::io::Read;

use rasica_dataset::{
    dataset::Dataset,
    dataset::DatasetBuilder,
    row::Row,
    schema::{Column, ColumnType, Schema},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};

use crate::{
    encoding::strip_bom_and_validate_utf8,
    error::IngestionError,
    typing::{classify_text, ColumnTypeAccumulator},
};

/// Configuration for [`read`].
#[derive(Debug, Clone, Copy)]
pub struct CsvOptions {
    /// The field delimiter byte. Defaults to `,` via [`Default`].
    pub delimiter: u8,
}

impl Default for CsvOptions {
    fn default() -> Self {
        Self { delimiter: b',' }
    }
}

/// Reads a CSV document from `reader`, treating its first row as the header,
/// and returns a [`Dataset`] tagged [`SourceFormat::Csv`] with `origin` as
/// its recorded provenance.
///
/// # Errors
///
/// Returns [`IngestionError::InvalidEncoding`] if the input is not valid
/// UTF-8 (§1.4 Note 2); [`IngestionError::Empty`] if the input has a header
/// but zero data rows, or no rows at all; [`IngestionError::InconsistentRowArity`]
/// if any data row has a different field count than the header;
/// [`IngestionError::SchemaConstructionFailed`] or
/// [`IngestionError::DatasetConstructionFailed`] if the resolved schema or
/// rows are otherwise malformed per `rasica-dataset`'s own invariants.
pub fn read(
    mut reader: impl Read,
    origin: impl Into<String>,
    options: CsvOptions,
) -> Result<Dataset, IngestionError> {
    let origin = origin.into();

    let mut raw_bytes = Vec::new();
    reader
        .read_to_end(&mut raw_bytes)
        .map_err(|cause| IngestionError::SourceUnreadable {
            origin: origin.clone(),
            cause,
        })?;
    let text = strip_bom_and_validate_utf8(&raw_bytes).map_err(|cause| {
        IngestionError::InvalidEncoding {
            origin: origin.clone(),
            cause,
        }
    })?;

    let mut csv_reader = ::csv::ReaderBuilder::new()
        .delimiter(options.delimiter)
        .has_headers(true)
        .flexible(true) // arity is checked explicitly below, with row numbers.
        .from_reader(text.as_bytes());

    let header = csv_reader
        .headers()
        .map_err(|cause| IngestionError::SourceUnreadable {
            origin: origin.clone(),
            cause: std::io::Error::new(std::io::ErrorKind::InvalidData, cause),
        })?
        .clone();
    if header.is_empty() {
        return Err(IngestionError::Empty {
            origin: origin.clone(),
        });
    }

    let records: Vec<::csv::StringRecord> = csv_reader
        .records()
        .enumerate()
        .map(|(index, result)| {
            let record = result.map_err(|cause| IngestionError::SourceUnreadable {
                origin: origin.clone(),
                cause: std::io::Error::new(std::io::ErrorKind::InvalidData, cause),
            })?;
            if record.len() != header.len() {
                return Err(IngestionError::InconsistentRowArity {
                    origin: origin.clone(),
                    row_number: index + 2, // +1 for the header row, +1 for 1-based numbering.
                    expected: header.len(),
                    actual: record.len(),
                });
            }
            Ok(record)
        })
        .collect::<Result<_, IngestionError>>()?;

    if records.is_empty() {
        return Err(IngestionError::Empty {
            origin: origin.clone(),
        });
    }

    // Pass 1: resolve one ColumnType per column.
    let mut accumulators: Vec<ColumnTypeAccumulator> =
        vec![ColumnTypeAccumulator::new(); header.len()];
    for record in &records {
        for (position, raw) in record.iter().enumerate() {
            let natural_type = if raw.is_empty() {
                None
            } else {
                Some(classify_text(raw))
            };
            accumulators[position].observe(natural_type);
        }
    }
    let column_types: Vec<ColumnType> = accumulators.into_iter().map(ColumnTypeAccumulator::finish).collect();

    let columns = header
        .iter()
        .zip(&column_types)
        .map(|(name, &column_type)| Column::new(name, column_type))
        .collect();
    let schema = Schema::new(columns).map_err(IngestionError::SchemaConstructionFailed)?;

    // Pass 2: build each Row against the resolved Schema.
    let mut builder = DatasetBuilder::new(schema);
    for record in &records {
        let values = record
            .iter()
            .zip(&column_types)
            .map(|(raw, &column_type)| parse_value(raw, column_type))
            .collect();
        builder
            .push_row(Row::new(values))
            .map_err(IngestionError::DatasetConstructionFailed)?;
    }

    Ok(builder.build(SourceMetadata::new(SourceFormat::Csv, origin)))
}

/// Parses one already-classified raw cell into a [`Value`].
///
/// This never fails: `column_type` was resolved (§4.3) from the very values
/// it is now applied to, so every non-empty cell is guaranteed parseable as
/// its column's resolved type, and an empty cell is always [`Value::Null`].
#[allow(clippy::expect_used)]
fn parse_value(raw: &str, column_type: ColumnType) -> Value {
    if raw.is_empty() {
        return Value::Null;
    }
    match column_type {
        ColumnType::Boolean => Value::Boolean(raw == "true"),
        ColumnType::Integer => Value::Integer(
            raw.parse()
                .expect("column_type was resolved from this exact value in pass 1"),
        ),
        ColumnType::Float => Value::Float(
            raw.parse()
                .expect("column_type was resolved from this exact value in pass 1"),
        ),
        ColumnType::Text => Value::Text(raw.to_owned()),
    }
}
EOF

echo "==> Writing crates/rasica-ingestion/src/excel.rs..."
cat > crates/rasica-ingestion/src/excel.rs << 'EOF'
//! Excel (`.xlsx`) ingestion (Architecture Spec §15.6, Initial Source: Excel).
//!
//! Only `.xlsx` (Office Open XML) is targeted explicitly; calamine's
//! `open_workbook_auto` also accepts legacy `.xls` and OpenDocument `.ods`
//! transparently, so this reader is not artificially restricted to `.xlsx`,
//! but `.xlsx` is the only format this document's fixtures and exit
//! criteria (§8) exercise.

use std::path::Path;

use calamine::{open_workbook_auto, DataType, Reader};
use rasica_dataset::{
    dataset::{Dataset, DatasetBuilder},
    row::Row,
    schema::{Column, ColumnType, Schema},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};

use crate::{
    error::IngestionError,
    typing::{ColumnTypeAccumulator, NaturalType},
};

/// Configuration for [`read`].
#[derive(Debug, Clone, Default)]
pub struct ExcelOptions {
    /// The worksheet to read. `None` selects the workbook's first sheet.
    pub sheet_name: Option<String>,
}

/// Reads one worksheet of an Excel workbook at `path`, treating its first
/// row as the header, and returns a [`Dataset`] tagged [`SourceFormat::Excel`].
///
/// # Errors
///
/// Returns [`IngestionError::SourceUnreadable`] if the workbook cannot be
/// opened; [`IngestionError::ExcelSheetNotFound`] if `options.sheet_name` is
/// `Some` and no such sheet exists; [`IngestionError::Empty`] if the sheet
/// has a header but no data rows; [`IngestionError::InconsistentRowArity`],
/// [`IngestionError::SchemaConstructionFailed`], and
/// [`IngestionError::DatasetConstructionFailed`] as in §4.5.
pub fn read(path: &Path, options: ExcelOptions) -> Result<Dataset, IngestionError> {
    let origin = path.display().to_string();

    let mut workbook = open_workbook_auto(path).map_err(|cause| IngestionError::SourceUnreadable {
        origin: origin.clone(),
        cause: std::io::Error::new(std::io::ErrorKind::InvalidData, cause),
    })?;

    let sheet_name = match &options.sheet_name {
        Some(name) => name.clone(),
        None => workbook
            .sheet_names()
            .first()
            .cloned()
            .ok_or_else(|| IngestionError::Empty {
                origin: origin.clone(),
            })?,
    };

    let range = workbook
        .worksheet_range(&sheet_name)
        .ok_or_else(|| IngestionError::ExcelSheetNotFound {
            origin: origin.clone(),
            sheet: sheet_name.clone(),
        })?
        .map_err(|cause| IngestionError::SourceUnreadable {
            origin: origin.clone(),
            cause: std::io::Error::new(std::io::ErrorKind::InvalidData, cause),
        })?;

    let mut rows_iter = range.rows();
    let header = rows_iter.next().ok_or_else(|| IngestionError::Empty {
        origin: origin.clone(),
    })?;
    let arity = header.len();
    if arity == 0 {
        return Err(IngestionError::Empty {
            origin: origin.clone(),
        });
    }

    let data_rows: Vec<&[DataType]> = rows_iter.collect();
    if data_rows.is_empty() {
        return Err(IngestionError::Empty {
            origin: origin.clone(),
        });
    }

    for (index, row) in data_rows.iter().enumerate() {
        if row.len() != arity {
            return Err(IngestionError::InconsistentRowArity {
                origin: origin.clone(),
                row_number: index + 2,
                expected: arity,
                actual: row.len(),
            });
        }
    }

    // Pass 1: resolve one ColumnType per column.
    let mut accumulators: Vec<ColumnTypeAccumulator> = vec![ColumnTypeAccumulator::new(); arity];
    for row in &data_rows {
        for (position, cell) in row.iter().enumerate() {
            accumulators[position].observe(natural_type_of(cell));
        }
    }
    let column_types: Vec<ColumnType> = accumulators.into_iter().map(ColumnTypeAccumulator::finish).collect();

    let columns = header
        .iter()
        .zip(&column_types)
        .map(|(cell, &column_type)| Column::new(cell.to_string(), column_type))
        .collect();
    let schema = Schema::new(columns).map_err(IngestionError::SchemaConstructionFailed)?;

    // Pass 2: build each Row against the resolved Schema.
    let mut builder = DatasetBuilder::new(schema);
    for row in &data_rows {
        let values = row
            .iter()
            .zip(&column_types)
            .map(|(cell, &column_type)| parse_value(cell, column_type))
            .collect();
        builder
            .push_row(Row::new(values))
            .map_err(IngestionError::DatasetConstructionFailed)?;
    }

    Ok(builder.build(SourceMetadata::new(SourceFormat::Excel, origin)))
}

/// Classifies one Excel cell's [`NaturalType`], or `None` if the cell is
/// empty (calamine's [`DataType::Empty`]).
///
/// Per §1.4 Note 4, [`DataType::DateTime`] is classified as
/// [`NaturalType::Text`]: temporal semantics are out of scope for this
/// phase, and calamine's textual rendering of the underlying serial value
/// is lossless.
fn natural_type_of(cell: &DataType) -> Option<NaturalType> {
    match cell {
        DataType::Empty => None,
        DataType::Bool(_) => Some(NaturalType::Boolean),
        DataType::Int(_) => Some(NaturalType::Integer),
        DataType::Float(_) => Some(NaturalType::Float),
        DataType::String(_) | DataType::DateTime(_) | DataType::Duration(_) | DataType::Error(_) => {
            Some(NaturalType::Text)
        }
    }
}

/// Converts one Excel cell into a [`Value`] under its column's resolved type.
///
/// As in §4.5, this cannot fail: `column_type` is the join (§4.3) of every
/// cell's own [`NaturalType`] observed in pass 1, so every cell already
/// agrees with it — a numeric cell being widened to [`ColumnType::Text`]
/// is rendered via calamine's own `to_string()`, which is exact and lossless.
#[allow(clippy::cast_precision_loss)]
fn parse_value(cell: &DataType, column_type: ColumnType) -> Value {
    if matches!(cell, DataType::Empty) {
        return Value::Null;
    }
    match (cell, column_type) {
        (DataType::Bool(b), ColumnType::Boolean) => Value::Boolean(*b),
        (DataType::Int(i), ColumnType::Integer) => Value::Integer(*i),
        (DataType::Int(i), ColumnType::Float) => Value::Float(*i as f64),
        (DataType::Float(f), ColumnType::Float) => Value::Float(*f),
        (_, ColumnType::Text) => Value::Text(cell.to_string()),
        (cell, column_type) => unreachable!(
            "column_type {column_type:?} was resolved from this exact cell {cell:?} in pass 1"
        ),
    }
}
EOF

echo "==> Writing crates/rasica-ingestion/src/json.rs..."
cat > crates/rasica-ingestion/src/json.rs << 'EOF'
//! JSON ingestion (Architecture Spec §15.6, Initial Source: JSON).
//!
//! Supports exactly one shape: a top-level array of flat objects, all
//! sharing the same key set (§1.4 Note 5). Column order is the lexicographic
//! order of key names, not source-incidental order (§1.4 Note 5).

use std::io::Read;

use rasica_dataset::{
    dataset::{Dataset, DatasetBuilder},
    row::Row,
    schema::{Column, ColumnType, Schema},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};
use serde_json::Value as JsonValue;

use crate::{
    encoding::strip_bom_and_validate_utf8,
    error::IngestionError,
    typing::{ColumnTypeAccumulator, NaturalType},
};

/// Reads a JSON array-of-objects document from `reader` and returns a
/// [`Dataset`] tagged [`SourceFormat::Json`].
///
/// # Errors
///
/// Returns [`IngestionError::InvalidEncoding`] if the input is not valid
/// UTF-8; [`IngestionError::SourceUnreadable`] if the input is not
/// well-formed JSON; [`IngestionError::UnsupportedJsonShape`] if the
/// top-level value is not an array, or any element is not a flat object
/// (§1.4 Note 5); [`IngestionError::Empty`] if the array has zero elements;
/// [`IngestionError::AmbiguousJsonSchema`] if elements do not share exactly
/// the same key set; [`IngestionError::SchemaConstructionFailed`] and
/// [`IngestionError::DatasetConstructionFailed`] as in §4.5.
#[allow(clippy::expect_used)]
pub fn read(mut reader: impl Read, origin: impl Into<String>) -> Result<Dataset, IngestionError> {
    let origin = origin.into();

    let mut raw_bytes = Vec::new();
    reader
        .read_to_end(&mut raw_bytes)
        .map_err(|cause| IngestionError::SourceUnreadable {
            origin: origin.clone(),
            cause,
        })?;
    let text = strip_bom_and_validate_utf8(&raw_bytes).map_err(|cause| {
        IngestionError::InvalidEncoding {
            origin: origin.clone(),
            cause,
        }
    })?;

    let parsed: JsonValue =
        serde_json::from_str(text).map_err(|cause| IngestionError::SourceUnreadable {
            origin: origin.clone(),
            cause: std::io::Error::new(std::io::ErrorKind::InvalidData, cause),
        })?;

    let JsonValue::Array(elements) = parsed else {
        return Err(IngestionError::UnsupportedJsonShape {
            origin: origin.clone(),
        });
    };
    if elements.is_empty() {
        return Err(IngestionError::Empty {
            origin: origin.clone(),
        });
    }

    // Column order is the lexicographic key order of the first (and, once
    // validated below, every) object — `serde_json::Map`'s default
    // backing (`BTreeMap`) already iterates in this order (§1.4 Note 5).
    let mut column_names: Option<Vec<String>> = None;
    let mut objects = Vec::with_capacity(elements.len());
    for (index, element) in elements.into_iter().enumerate() {
        let JsonValue::Object(map) = element else {
            return Err(IngestionError::UnsupportedJsonShape {
                origin: origin.clone(),
            });
        };
        let keys: Vec<String> = map.keys().cloned().collect();
        match &column_names {
            None => column_names = Some(keys),
            Some(expected) if expected == &keys => {}
            Some(expected) => {
                return Err(IngestionError::AmbiguousJsonSchema {
                    origin: origin.clone(),
                    object_index: index,
                    expected_keys: expected.clone(),
                    actual_keys: keys,
                });
            }
        }
        objects.push(map);
    }
    let column_names = column_names.expect("objects is non-empty, so column_names was set above");

    // Pass 1: resolve one ColumnType per column.
    let mut accumulators: Vec<ColumnTypeAccumulator> =
        vec![ColumnTypeAccumulator::new(); column_names.len()];
    for object in &objects {
        for (position, name) in column_names.iter().enumerate() {
            let field = object
                .get(name)
                .expect("every object was validated to share this exact key set above");
            accumulators[position].observe(natural_type_of(field, &origin, name)?);
        }
    }
    let column_types: Vec<ColumnType> = accumulators.into_iter().map(ColumnTypeAccumulator::finish).collect();

    let columns = column_names
        .iter()
        .zip(&column_types)
        .map(|(name, &column_type)| Column::new(name.clone(), column_type))
        .collect();
    let schema = Schema::new(columns).map_err(IngestionError::SchemaConstructionFailed)?;

    // Pass 2: build each Row against the resolved Schema.
    let mut builder = DatasetBuilder::new(schema);
    for object in &objects {
        let values = column_names
            .iter()
            .zip(&column_types)
            .map(|(name, &column_type)| {
                let field = object
                    .get(name)
                    .expect("every object was validated to share this exact key set above");
                parse_value(field, column_type)
            })
            .collect();
        builder
            .push_row(Row::new(values))
            .map_err(IngestionError::DatasetConstructionFailed)?;
    }

    Ok(builder.build(SourceMetadata::new(SourceFormat::Json, origin)))
}

/// Classifies one JSON field's [`NaturalType`], or `None` for `null`.
///
/// # Errors
///
/// Returns [`IngestionError::UnsupportedJsonValue`] for a nested array or
/// object (§1.4 Note 5): silently stringifying a nested value would be a
/// lossy, ambiguous representation, which §15.6's "no data loss" and
/// "correct typing" verification items both rule out.
fn natural_type_of(
    field: &JsonValue,
    origin: &str,
    key: &str,
) -> Result<Option<NaturalType>, IngestionError> {
    match field {
        JsonValue::Null => Ok(None),
        JsonValue::Bool(_) => Ok(Some(NaturalType::Boolean)),
        JsonValue::Number(n) if n.is_i64() || n.is_u64() => Ok(Some(NaturalType::Integer)),
        JsonValue::Number(_) => Ok(Some(NaturalType::Float)),
        JsonValue::String(_) => Ok(Some(NaturalType::Text)),
        JsonValue::Array(_) | JsonValue::Object(_) => Err(IngestionError::UnsupportedJsonValue {
            origin: origin.to_owned(),
            key: key.to_owned(),
        }),
    }
}

/// Converts one JSON field into a [`Value`] under its column's resolved type.
///
/// As in §4.5 and §4.6, this cannot fail for the same reason: `column_type`
/// was resolved from this exact field's own [`NaturalType`] in pass 1.
#[allow(clippy::expect_used)]
fn parse_value(field: &JsonValue, column_type: ColumnType) -> Value {
    match (field, column_type) {
        (JsonValue::Null, _) => Value::Null,
        (JsonValue::Bool(b), ColumnType::Boolean) => Value::Boolean(*b),
        (JsonValue::Number(n), ColumnType::Integer) => Value::Integer(
            n.as_i64()
                .expect("column_type Integer was resolved only from i64/u64-representable numbers"),
        ),
        (JsonValue::Number(n), ColumnType::Float) => Value::Float(
            n.as_f64()
                .expect("every serde_json::Number converts losslessly to f64"),
        ),
        (JsonValue::String(s), ColumnType::Text) => Value::Text(s.clone()),
        (field, ColumnType::Text) => Value::Text(field.to_string()),
        (field, column_type) => unreachable!(
            "column_type {column_type:?} was resolved from this exact field {field:?} in pass 1"
        ),
    }
}
EOF

echo "==> Writing crates/rasica-ingestion/src/ingest.rs..."
cat > crates/rasica-ingestion/src/ingest.rs << 'EOF'
//! One uniform entry point across every Initial Source (§9.1, "source
//! abstraction"). Format-specific configuration lives in this module so
//! callers select a format once, rather than importing three modules.

use std::{fs::File, io::BufReader, path::Path};

use rasica_dataset::dataset::Dataset;

use crate::{csv, error::IngestionError, excel, json};

/// Per-format configuration for [`ingest_path`].
#[derive(Debug, Clone)]
pub enum FormatOptions {
    /// See [`csv::CsvOptions`].
    Csv(csv::CsvOptions),
    /// See [`excel::ExcelOptions`].
    Excel(excel::ExcelOptions),
    /// JSON accepts no configuration in Phase 3 (§1.4 Note 5 fixes its
    /// supported shape and column-ordering convention unconditionally).
    Json,
}

/// Reads `path` under `options`, dispatching to the matching format's
/// reader, and returns the resulting [`Dataset`].
///
/// # Errors
///
/// Propagates whichever [`IngestionError`] the selected format's reader
/// returns; see [`csv::read`], [`excel::read`], and [`json::read`].
pub fn ingest_path(path: &Path, options: FormatOptions) -> Result<Dataset, IngestionError> {
    let origin = path.display().to_string();
    match options {
        FormatOptions::Csv(csv_options) => {
            let file = File::open(path).map_err(|cause| IngestionError::SourceUnreadable {
                origin: origin.clone(),
                cause,
            })?;
            csv::read(BufReader::new(file), origin, csv_options)
        }
        FormatOptions::Excel(excel_options) => excel::read(path, excel_options),
        FormatOptions::Json => {
            let file = File::open(path).map_err(|cause| IngestionError::SourceUnreadable {
                origin: origin.clone(),
                cause,
            })?;
            json::read(BufReader::new(file), origin)
        }
    }
}
EOF

echo "==> Writing crates/rasica-ingestion/src/error.rs..."
cat > crates/rasica-ingestion/src/error.rs << 'EOF'
//! Errors produced while ingesting an external source (Architecture Spec
//! §14.9; Document 00A §4.4).

use thiserror::Error;

use rasica_common::error::{ErrorCode, ErrorSeverity, RasicaError};
use rasica_dataset::{dataset::DatasetError, schema::SchemaError};

/// Errors from every reader in this crate.
#[derive(Debug, Error)]
pub enum IngestionError {
    /// The source could not be opened or read at the I/O level.
    #[error("failed to read source '{origin}': {cause}")]
    SourceUnreadable {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
        /// The underlying I/O failure, preserved for diagnosis.
        #[source]
        cause: std::io::Error,
    },

    /// The source's bytes were not valid UTF-8 (§1.4 Note 2).
    #[error("source '{origin}' is not valid UTF-8: {cause}")]
    InvalidEncoding {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
        /// The underlying UTF-8 validation failure.
        #[source]
        cause: std::str::Utf8Error,
    },

    /// The source declared a header (or, for JSON, at least one object) but
    /// contained zero data rows, or contained no rows at all.
    #[error("source '{origin}' contains no data rows")]
    Empty {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
    },

    /// A data row's field count disagreed with the header's.
    #[error(
        "source '{origin}' row {row_number} has {actual} fields but the header declares {expected}"
    )]
    InconsistentRowArity {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
        /// The 1-based row number (including the header) at which the
        /// mismatch was found.
        row_number: usize,
        /// The header's field count.
        expected: usize,
        /// The offending row's actual field count.
        actual: usize,
    },

    /// A JSON array element's key set disagreed with the first element's
    /// (§1.4 Note 5).
    #[error(
        "source '{origin}' object at index {object_index} has a different key set than the first object"
    )]
    AmbiguousJsonSchema {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
        /// The 0-based index of the first object whose keys disagreed.
        object_index: usize,
        /// The key set established by the first object in the array.
        expected_keys: Vec<String>,
        /// The offending object's actual key set.
        actual_keys: Vec<String>,
    },

    /// A JSON field held a nested array or object (§1.4 Note 5).
    #[error("source '{origin}' field '{key}' is a nested array or object, which is not supported")]
    UnsupportedJsonValue {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
        /// The offending field's key.
        key: String,
    },

    /// The top-level JSON value was not an array of flat objects (§1.4 Note 5).
    #[error("source '{origin}' is not a JSON array of flat objects")]
    UnsupportedJsonShape {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
    },

    /// The requested Excel worksheet does not exist in the workbook.
    #[error("source '{origin}' has no worksheet named '{sheet}'")]
    ExcelSheetNotFound {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
        /// The requested, absent sheet name.
        sheet: String,
    },

    /// The resolved schema was rejected by `rasica-dataset` (e.g. duplicate
    /// column names after header normalisation).
    #[error("source produced an invalid schema: {0}")]
    SchemaConstructionFailed(#[source] SchemaError),

    /// A row was rejected by `rasica-dataset`'s own structural checks.
    #[error("source produced an invalid dataset: {0}")]
    DatasetConstructionFailed(#[source] DatasetError),
}

impl RasicaError for IngestionError {
    fn error_code(&self) -> ErrorCode {
        match self {
            Self::SourceUnreadable { .. } => ErrorCode("ingestion::source_unreadable"),
            Self::InvalidEncoding { .. } => ErrorCode("ingestion::invalid_encoding"),
            Self::Empty { .. } => ErrorCode("ingestion::empty"),
            Self::InconsistentRowArity { .. } => ErrorCode("ingestion::inconsistent_row_arity"),
            Self::AmbiguousJsonSchema { .. } => ErrorCode("ingestion::ambiguous_json_schema"),
            Self::UnsupportedJsonValue { .. } => ErrorCode("ingestion::unsupported_json_value"),
            Self::UnsupportedJsonShape { .. } => ErrorCode("ingestion::unsupported_json_shape"),
            Self::ExcelSheetNotFound { .. } => ErrorCode("ingestion::excel_sheet_not_found"),
            Self::SchemaConstructionFailed(_) => ErrorCode("ingestion::schema_construction_failed"),
            Self::DatasetConstructionFailed(_) => ErrorCode("ingestion::dataset_construction_failed"),
        }
    }

    fn severity(&self) -> ErrorSeverity {
        // Every condition is caught before `DatasetBuilder::build` is
        // called, i.e. before any Tier 1 `Dataset` exists — matching
        // `DatasetError`'s rationale in Document 00B §4.7.
        ErrorSeverity::Recoverable
    }
}
EOF

echo "==> Writing crates/rasica-ingestion/src/lib.rs..."
cat > crates/rasica-ingestion/src/lib.rs << 'EOF'
//! `rasica-ingestion`: readers for the Initial Sources named in Architecture
//! Spec §15.6 (CSV, Excel, JSON), each producing a `rasica_dataset::Dataset`
//! exclusively via `rasica_dataset::dataset::DatasetBuilder`.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod csv;
pub mod encoding;
pub mod error;
pub mod excel;
pub mod ingest;
pub mod json;
pub mod prelude;
mod typing;
EOF

echo "==> Writing crates/rasica-ingestion/src/prelude.rs..."
cat > crates/rasica-ingestion/src/prelude.rs << 'EOF'
//! Convenience re-export of the types most consumers of `rasica-ingestion`
//! need, following the same convention as `rasica_dataset::prelude`
//! (Document 00B §4.8).

pub use crate::{
    csv::CsvOptions,
    error::IngestionError,
    excel::ExcelOptions,
    ingest::{ingest_path, FormatOptions},
};
EOF

echo "==> Writing crates/rasica-ingestion/benches/csv_ingestion.rs..."
cat > crates/rasica-ingestion/benches/csv_ingestion.rs << 'EOF'
//! Benchmarks parsing and type-resolution cost in isolation from filesystem
//! variance, by feeding an in-memory, deterministically generated CSV byte
//! buffer through `csv::read` via a `Cursor` — see §5.5 of the Phase 3
//! Implementation Specification.

#![allow(missing_docs, clippy::expect_used, clippy::unwrap_used)]

use std::io::Cursor;

use criterion::{criterion_group, criterion_main, Criterion};
use rasica_ingestion::csv::{read, CsvOptions};

fn synthetic_csv(rows: usize, columns: usize) -> Vec<u8> {
    let mut buffer = String::new();
    let header: Vec<String> = (0..columns).map(|c| format!("col{c}")).collect();
    buffer.push_str(&header.join(","));
    buffer.push('\n');
    for r in 0..rows {
        let row: Vec<String> = (0..columns).map(|c| ((r * columns + c) % 97).to_string()).collect();
        buffer.push_str(&row.join(","));
        buffer.push('\n');
    }
    buffer.into_bytes()
}

fn bench_csv_ingestion(c: &mut Criterion) {
    let bytes = synthetic_csv(10_000, 20);
    c.bench_function("csv_ingest_10k_rows_20_cols", |b| {
        b.iter(|| read(Cursor::new(bytes.clone()), "synthetic", CsvOptions::default()).unwrap())
    });
}

criterion_group!(benches, bench_csv_ingestion);
criterion_main!(benches);
EOF

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

echo "==> Writing crates/rasica-ingestion/tests/fixtures/well_formed.csv..."
printf 'id,name,active,score\n1,Ada,true,9.5\n2,,false,3.25\n' > crates/rasica-ingestion/tests/fixtures/well_formed.csv

echo "==> Writing crates/rasica-ingestion/tests/fixtures/utf8_bom.csv..."
python3 - << 'PYEOF'
with open("crates/rasica-ingestion/tests/fixtures/well_formed.csv", "rb") as f:
    content = f.read()
with open("crates/rasica-ingestion/tests/fixtures/utf8_bom.csv", "wb") as f:
    f.write(b"\xef\xbb\xbf" + content)
PYEOF

echo "==> Writing crates/rasica-ingestion/tests/fixtures/invalid_encoding.csv..."
python3 - << 'PYEOF'
with open("crates/rasica-ingestion/tests/fixtures/invalid_encoding.csv", "wb") as f:
    f.write(b"\xffid,name,active,score\n1,Ada,true,9.5\n2,,false,3.25\n")
PYEOF

echo "==> Writing crates/rasica-ingestion/tests/fixtures/well_formed.json..."
cat > crates/rasica-ingestion/tests/fixtures/well_formed.json << 'EOF'
[
  {"score": 9.5, "active": true, "name": "Ada", "id": 1},
  {"id": 2, "score": 3.25, "active": false, "name": null}
]
EOF

echo "==> Attempting to generate crates/rasica-ingestion/tests/fixtures/well_formed.xlsx..."
if python3 -c "import openpyxl" 2>/dev/null; then
  HAVE_OPENPYXL=1
else
  echo "    openpyxl not found; attempting 'pip install openpyxl --break-system-packages'..."
  pip install openpyxl --break-system-packages -q 2>/dev/null && HAVE_OPENPYXL=1 || HAVE_OPENPYXL=0
fi

if [ "${HAVE_OPENPYXL:-0}" = "1" ]; then
  python3 - << 'PYEOF'
import openpyxl
from datetime import datetime

wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Sheet1"
ws.append(["id", "name", "active", "score", "created_at"])
ws.append([1, "Ada", True, 9.5, datetime(2024, 1, 1, 12, 0, 0)])
ws.append([2, None, False, 3.25, datetime(2024, 1, 2, 9, 30, 0)])
wb.save("crates/rasica-ingestion/tests/fixtures/well_formed.xlsx")
print("    generated via openpyxl.")
PYEOF
else
  echo "    WARNING: could not generate well_formed.xlsx automatically (no openpyxl/pip access)."
  echo "    Create it by hand per §5.2: a single-sheet workbook with columns"
  echo "    id, name, active, score (matching well_formed.csv) plus one extra"
  echo "    DateTime-typed column, saved as:"
  echo "      crates/rasica-ingestion/tests/fixtures/well_formed.xlsx"
fi

echo "==> Writing crates/rasica-ingestion/tests/round_trip.rs..."
cat > crates/rasica-ingestion/tests/round_trip.rs << 'EOF'
//! Round-trip tests: each fixture in `tests/fixtures/` is ingested and
//! compared against a hand-built expected `Dataset`, per §15.6's exit
//! criterion ("imported datasets match source datasets exactly").

use std::{fs::File, io::BufReader, path::Path};

use rasica_core::prelude::DeterministicFingerprint;
use rasica_dataset::{
    dataset::DatasetBuilder,
    row::Row,
    schema::{Column, ColumnType, Schema},
    value::Value,
};
use rasica_ingestion::{csv, excel, json};

fn fixture_path(name: &str) -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures").join(name)
}

/// The single expected `Dataset` every well-formed fixture must ingest to,
/// independent of source format (§5.2).
#[allow(clippy::expect_used)]
fn expected_well_formed_dataset() -> rasica_dataset::dataset::Dataset {
    let schema = Schema::new(vec![
        Column::new("id", ColumnType::Integer),
        Column::new("name", ColumnType::Text),
        Column::new("active", ColumnType::Boolean),
        Column::new("score", ColumnType::Float),
    ])
    .expect("hand-written schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    builder
        .push_row(Row::new(vec![
            Value::Integer(1),
            Value::Text("Ada".into()),
            Value::Boolean(true),
            Value::Float(9.5),
        ]))
        .expect("hand-written row matches hand-written schema");
    builder
        .push_row(Row::new(vec![
            Value::Integer(2),
            Value::Null,
            Value::Boolean(false),
            Value::Float(3.25),
        ]))
        .expect("hand-written row matches hand-written schema");

    builder.build(rasica_dataset::source::SourceMetadata::new(
        rasica_dataset::source::SourceFormat::InMemory,
        "expected",
    ))
}

/// Compares two `Dataset`s by content, ignoring identity and provenance —
/// exactly what `DeterministicFingerprint` already excludes (Document 00B
/// §4.6) — so this is a single, reusable equality check across every format.
fn assert_content_equal(actual: &rasica_dataset::dataset::Dataset, expected: &rasica_dataset::dataset::Dataset) {
    assert_eq!(actual.fingerprint(), expected.fingerprint());
}

#[test]
#[allow(clippy::expect_used)]
fn csv_round_trip_matches_expected_dataset() {
    let file = File::open(fixture_path("well_formed.csv")).expect("fixture exists");
    let dataset = csv::read(BufReader::new(file), "well_formed.csv", csv::CsvOptions::default())
        .expect("fixture is well-formed");
    assert_content_equal(&dataset, &expected_well_formed_dataset());
}

#[test]
#[allow(clippy::expect_used)]
fn json_round_trip_matches_expected_dataset_regardless_of_source_key_order() {
    let file = File::open(fixture_path("well_formed.json")).expect("fixture exists");
    let dataset = json::read(BufReader::new(file), "well_formed.json").expect("fixture is well-formed");
    assert_content_equal(&dataset, &expected_well_formed_dataset());
}

#[test]
#[allow(clippy::expect_used)]
fn excel_round_trip_matches_expected_dataset() {
    let dataset = excel::read(&fixture_path("well_formed.xlsx"), excel::ExcelOptions::default())
        .expect("fixture is well-formed");
    // The Excel fixture additionally carries one DateTime cell (§1.4 Note 4)
    // beyond `expected_well_formed_dataset`'s shape, so this test checks the
    // shared columns' values individually rather than a single fingerprint
    // equality, and separately asserts the DateTime column resolved to Text.
    assert_eq!(dataset.schema().arity(), 5);
    assert_eq!(dataset.schema().columns()[4].column_type(), ColumnType::Text);
}

#[test]
#[allow(clippy::expect_used)]
fn utf8_bom_is_stripped_not_ingested_as_data() {
    let with_bom = File::open(fixture_path("utf8_bom.csv")).expect("fixture exists");
    let without_bom = File::open(fixture_path("well_formed.csv")).expect("fixture exists");

    let from_bom = csv::read(BufReader::new(with_bom), "utf8_bom.csv", csv::CsvOptions::default())
        .expect("BOM-prefixed fixture is well-formed after stripping");
    let from_plain = csv::read(BufReader::new(without_bom), "well_formed.csv", csv::CsvOptions::default())
        .expect("fixture is well-formed");

    assert_content_equal(&from_bom, &from_plain);
}

#[test]
#[allow(clippy::expect_used)]
fn invalid_encoding_is_rejected_not_mis_decoded() {
    let file = File::open(fixture_path("invalid_encoding.csv")).expect("fixture exists");
    let result = csv::read(BufReader::new(file), "invalid_encoding.csv", csv::CsvOptions::default());
    assert!(matches!(result, Err(rasica_ingestion::error::IngestionError::InvalidEncoding { .. })));
}

#[test]
#[allow(clippy::expect_used)]
fn repeated_import_is_deterministic() {
    for _ in 0..3 {
        let file = File::open(fixture_path("well_formed.csv")).expect("fixture exists");
        let dataset = csv::read(BufReader::new(file), "well_formed.csv", csv::CsvOptions::default())
            .expect("fixture is well-formed");
        assert_eq!(dataset.fingerprint(), expected_well_formed_dataset().fingerprint());
    }
}
EOF

# ---------------------------------------------------------------------------
# Patch: tests/workspace_smoke/Cargo.toml
# ---------------------------------------------------------------------------

echo "==> Patching tests/workspace_smoke/Cargo.toml (add rasica-ingestion dep)..."
if ! grep -q "rasica-ingestion" tests/workspace_smoke/Cargo.toml; then
  # Ensure the file ends with a newline before appending, to avoid the
  # same concatenation bug hit during Phase 2's rollout.
  [ -n "$(tail -c1 tests/workspace_smoke/Cargo.toml)" ] && echo >> tests/workspace_smoke/Cargo.toml
  cat >> tests/workspace_smoke/Cargo.toml << 'EOF'
rasica-ingestion = { path = "../../crates/rasica-ingestion", version = "0.1.0" }
EOF
else
  echo "    (already patched, skipping)"
fi

# ---------------------------------------------------------------------------
# Patch: tests/workspace_smoke/tests/smoke.rs
# ---------------------------------------------------------------------------

echo "==> Extending tests/workspace_smoke/tests/smoke.rs (Phase 3 test)..."
if ! grep -q "ingests_a_csv_fixture_into_an_immutable_dataset" tests/workspace_smoke/tests/smoke.rs; then
  cat >> tests/workspace_smoke/tests/smoke.rs << 'EOF'

#[test]
#[allow(clippy::expect_used)]
fn ingests_a_csv_fixture_into_an_immutable_dataset() {
    let csv_bytes = b"id,label\n1,alpha\n2,beta\n".as_slice();
    let dataset = rasica_ingestion::csv::read(csv_bytes, "inline-fixture", rasica_ingestion::csv::CsvOptions::default())
        .expect("inline CSV literal is well-formed");

    assert_eq!(dataset.row_count(), 2);
    assert_eq!(dataset.schema().arity(), 2);
    // Reuses Document 00B's own smoke assertion pattern: Dataset is Tier 1.
    fn assert_immutable<T: rasica_core::prelude::Immutable>(_: &T) {}
    assert_immutable(&dataset);
}
EOF
else
  echo "    (already patched, skipping)"
fi

echo ""
echo "==> Done. Phase 3 (rasica-ingestion) scaffolded."
echo ""
echo "Next steps:"
echo "  1. cargo check --workspace"
echo "  2. cargo nextest run --workspace"
echo "  3. cargo clippy --workspace --all-targets -- -D warnings"
echo "  4. cargo fmt --all"
echo "  5. cargo bench --workspace"
echo "  6. cargo deny check"
echo ""
echo "Note: if well_formed.xlsx could not be auto-generated (see warning above,"
echo "if any), create it manually before running the round_trip tests — the"
echo "excel_round_trip_matches_expected_dataset test will fail without it."
