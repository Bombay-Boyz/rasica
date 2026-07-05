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
            format!("row_count() reports {} but {} rows are held", dataset.row_count(), rows.len()),
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
                format!(
                    "row has {arity} values but the schema declares {} columns",
                    schema.arity()
                ),
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
