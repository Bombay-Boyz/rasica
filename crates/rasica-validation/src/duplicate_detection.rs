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
