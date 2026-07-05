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
            Self::NotNull { column } | Self::Unique { column } | Self::Range { column, .. } => {
                column
            }
        }
    }
}

/// Evaluates every constraint in `constraints` against `dataset`,
/// producing one or more findings per constraint.
pub(crate) fn check_constraints(
    dataset: &Dataset,
    constraints: &[ValidationConstraint],
) -> Vec<ValidationFinding> {
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
            ValidationConstraint::NotNull { column } => {
                check_not_null(dataset, column_index, column)
            }
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
                    format!(
                        "column '{column}' value at row {row_index} duplicates row {first_index}"
                    ),
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
