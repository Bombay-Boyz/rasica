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
/// # Panics
///
/// Never panics under normal use: the internal `.expect()` on
/// `column_names` is unreachable because `objects` was checked non-empty
/// immediately above, which guarantees `column_names` was set in the loop.
#[allow(clippy::expect_used)]
pub fn read(mut reader: impl Read, origin: impl Into<String>) -> Result<Dataset, IngestionError> {
    let origin = origin.into();

    let mut raw_bytes = Vec::new();
    reader
        .read_to_end(&mut raw_bytes)
        .map_err(|cause| IngestionError::SourceUnreadable { origin: origin.clone(), cause })?;
    let text = strip_bom_and_validate_utf8(&raw_bytes)
        .map_err(|cause| IngestionError::InvalidEncoding { origin: origin.clone(), cause })?;

    let parsed: JsonValue =
        serde_json::from_str(text).map_err(|cause| IngestionError::SourceUnreadable {
            origin: origin.clone(),
            cause: std::io::Error::new(std::io::ErrorKind::InvalidData, cause),
        })?;

    let JsonValue::Array(elements) = parsed else {
        return Err(IngestionError::UnsupportedJsonShape { origin: origin.clone() });
    };
    if elements.is_empty() {
        return Err(IngestionError::Empty { origin: origin.clone() });
    }

    // Column order is the lexicographic key order of the first (and, once
    // validated below, every) object — `serde_json::Map`'s default
    // backing (`BTreeMap`) already iterates in this order (§1.4 Note 5).
    let mut column_names: Option<Vec<String>> = None;
    let mut objects = Vec::with_capacity(elements.len());
    for (index, element) in elements.into_iter().enumerate() {
        let JsonValue::Object(map) = element else {
            return Err(IngestionError::UnsupportedJsonShape { origin: origin.clone() });
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
    let column_types: Vec<ColumnType> =
        accumulators.into_iter().map(ColumnTypeAccumulator::finish).collect();

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
        builder.push_row(Row::new(values)).map_err(IngestionError::DatasetConstructionFailed)?;
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
        (JsonValue::Number(n), ColumnType::Float) => {
            Value::Float(n.as_f64().expect("every serde_json::Number converts losslessly to f64"))
        }
        (JsonValue::String(s), ColumnType::Text) => Value::Text(s.clone()),
        (field, ColumnType::Text) => Value::Text(field.to_string()),
        (field, column_type) => unreachable!(
            "column_type {column_type:?} was resolved from this exact field {field:?} in pass 1"
        ),
    }
}
