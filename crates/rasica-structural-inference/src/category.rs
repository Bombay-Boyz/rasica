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
