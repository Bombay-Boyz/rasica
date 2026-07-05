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
pub(crate) fn check_nulls(
    dataset: &Dataset,
    options: NullAnalysisOptions,
) -> Vec<ValidationFinding> {
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
