//! Excel (`.xlsx`) ingestion (Architecture Spec §15.6, Initial Source: Excel).
//!
//! Only `.xlsx` (Office Open XML) is targeted explicitly; calamine's
//! `open_workbook_auto` also accepts legacy `.xls` and `OpenDocument` `.ods`
//! transparently, so this reader is not artificially restricted to `.xlsx`,
//! but `.xlsx` is the only format this document's fixtures and exit
//! criteria (§8) exercise.
//!
//! Uses calamine's `Data` enum (the crate's `DataType` was renamed to a
//! trait as of calamine 0.24/0.25; `Data` is the concrete cell-value type
//! implementing it).

use std::path::Path;

use calamine::{open_workbook_auto, Data, Reader};
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
pub fn read(path: &Path, options: &ExcelOptions) -> Result<Dataset, IngestionError> {
    // ← change param, ~line 33
    let origin = path.display().to_string();

    let mut workbook =
        open_workbook_auto(path).map_err(|cause| IngestionError::SourceUnreadable {
            origin: origin.clone(),
            cause: std::io::Error::new(std::io::ErrorKind::InvalidData, cause),
        })?;

    let sheet_name = match &options.sheet_name {
        Some(name) => {
            if !workbook.sheet_names().iter().any(|s| s == name) {
                return Err(IngestionError::ExcelSheetNotFound {
                    origin: origin.clone(),
                    sheet: name.clone(),
                });
            }
            name.clone()
        }
        None => workbook
            .sheet_names()
            .first()
            .cloned()
            .ok_or_else(|| IngestionError::Empty { origin: origin.clone() })?,
    };

    let range = workbook.worksheet_range(&sheet_name).map_err(|cause| {
        IngestionError::SourceUnreadable {
            origin: origin.clone(),
            cause: std::io::Error::new(std::io::ErrorKind::InvalidData, cause),
        }
    })?;

    let mut rows_iter = range.rows();
    let header =
        rows_iter.next().ok_or_else(|| IngestionError::Empty { origin: origin.clone() })?;
    let arity = header.len();
    if arity == 0 {
        return Err(IngestionError::Empty { origin: origin.clone() });
    }

    let data_rows: Vec<&[Data]> = rows_iter.collect();
    if data_rows.is_empty() {
        return Err(IngestionError::Empty { origin: origin.clone() });
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
    let column_types: Vec<ColumnType> =
        accumulators.into_iter().map(ColumnTypeAccumulator::finish).collect();

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
        builder.push_row(Row::new(values)).map_err(IngestionError::DatasetConstructionFailed)?;
    }

    Ok(builder.build(SourceMetadata::new(SourceFormat::Excel, origin)))
}

/// Classifies one Excel cell's [`NaturalType`], or `None` if the cell is
/// empty ([`Data::Empty`]).
///
/// Per §1.4 Note 4, [`Data::DateTime`] is classified as
/// [`NaturalType::Text`]: temporal semantics are out of scope for this
/// phase, and calamine's textual rendering of the underlying value is
/// lossless.
fn natural_type_of(cell: &Data) -> Option<NaturalType> {
    match cell {
        Data::Empty => None,
        Data::Bool(_) => Some(NaturalType::Boolean),
        Data::Int(_) => Some(NaturalType::Integer),
        Data::Float(_) => Some(NaturalType::Float),
        Data::String(_)
        | Data::DateTime(_)
        | Data::DateTimeIso(_)
        | Data::DurationIso(_)
        | Data::Error(_) => Some(NaturalType::Text),
    }
}

/// Converts one Excel cell into a [`Value`] under its column's resolved type.
///
/// As in §4.5, this cannot fail: `column_type` is the join (§4.3) of every
/// cell's own [`NaturalType`] observed in pass 1, so every cell already
/// agrees with it — a numeric cell being widened to [`ColumnType::Text`]
/// is rendered via calamine's own `to_string()`, which is exact and lossless.
#[allow(clippy::cast_precision_loss)]
fn parse_value(cell: &Data, column_type: ColumnType) -> Value {
    if matches!(cell, Data::Empty) {
        return Value::Null;
    }
    match (cell, column_type) {
        (Data::Bool(b), ColumnType::Boolean) => Value::Boolean(*b),
        (Data::Int(i), ColumnType::Integer) => Value::Integer(*i),
        (Data::Int(i), ColumnType::Float) => Value::Float(*i as f64),
        (Data::Float(f), ColumnType::Float) => Value::Float(*f),
        (_, ColumnType::Text) => Value::Text(cell.to_string()),
        (cell, column_type) => unreachable!(
            "column_type {column_type:?} was resolved from this exact cell {cell:?} in pass 1"
        ),
    }
}
