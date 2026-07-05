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
        .map_err(|cause| IngestionError::SourceUnreadable { origin: origin.clone(), cause })?;
    let text = strip_bom_and_validate_utf8(&raw_bytes)
        .map_err(|cause| IngestionError::InvalidEncoding { origin: origin.clone(), cause })?;

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
        return Err(IngestionError::Empty { origin: origin.clone() });
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
        return Err(IngestionError::Empty { origin: origin.clone() });
    }

    // Pass 1: resolve one ColumnType per column.
    let mut accumulators: Vec<ColumnTypeAccumulator> =
        vec![ColumnTypeAccumulator::new(); header.len()];
    for record in &records {
        for (position, raw) in record.iter().enumerate() {
            let natural_type = if raw.is_empty() { None } else { Some(classify_text(raw)) };
            accumulators[position].observe(natural_type);
        }
    }
    let column_types: Vec<ColumnType> =
        accumulators.into_iter().map(ColumnTypeAccumulator::finish).collect();

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
        builder.push_row(Row::new(values)).map_err(IngestionError::DatasetConstructionFailed)?;
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
            raw.parse().expect("column_type was resolved from this exact value in pass 1"),
        ),
        ColumnType::Float => Value::Float(
            raw.parse().expect("column_type was resolved from this exact value in pass 1"),
        ),
        ColumnType::Text => Value::Text(raw.to_owned()),
    }
}
