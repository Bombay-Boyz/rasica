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
