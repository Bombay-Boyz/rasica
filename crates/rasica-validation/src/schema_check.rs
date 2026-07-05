//! Schema-level structural validation (§9.2 "schema validation").

use std::collections::HashSet;

use rasica_dataset::schema::Schema;

use crate::{
    dataset_view::column_name,
    finding::{FindingKind, Location, ValidationCategory, ValidationFinding},
};

/// Checks that `schema` is non-empty and every column has a non-empty,
/// unique name.
///
/// `rasica-dataset`'s own `Schema::new` already rejects a malformed
/// schema at construction time for any Dataset built through the normal
/// `DatasetBuilder` path (Document 00B). This check re-verifies the same
/// invariants independently against whatever `Schema` the Dataset in
/// hand actually reports, because the Validation Engine is
/// architecturally independent of Ingestion (§6.6) and must not assume
/// every Dataset it validates was necessarily built that way.
pub(crate) fn check_schema(schema: &Schema) -> Vec<ValidationFinding> {
    if schema.arity() == 0 {
        return vec![ValidationFinding::new(
            FindingKind::Failure,
            ValidationCategory::Schema,
            "schema::empty",
            "schema declares zero columns",
            Location::Dataset,
        )];
    }

    let mut findings = Vec::new();
    let mut seen_names: HashSet<&str> = HashSet::new();
    let mut clean = true;

    for (index, column) in schema.columns().iter().enumerate() {
        let name = column_name(column);
        if name.trim().is_empty() {
            clean = false;
            findings.push(ValidationFinding::new(
                FindingKind::Failure,
                ValidationCategory::Schema,
                "schema::empty_column_name",
                format!("column {index} has an empty name"),
                Location::Column { index, name: name.to_string() },
            ));
            continue;
        }
        if !seen_names.insert(name) {
            clean = false;
            findings.push(ValidationFinding::new(
                FindingKind::Failure,
                ValidationCategory::Schema,
                "schema::duplicate_column_name",
                format!("column name '{name}' is duplicated"),
                Location::Column { index, name: name.to_string() },
            ));
        }
    }

    if clean {
        findings.push(ValidationFinding::new(
            FindingKind::Success,
            ValidationCategory::Schema,
            "schema::well_formed",
            "schema is non-empty with uniquely and non-emptily named columns",
            Location::Dataset,
        ));
    }

    findings
}

#[cfg(test)]
mod tests {
    use super::*;
    use rasica_dataset::schema::{Column, ColumnType};

    #[test]
    #[allow(clippy::expect_used)]
    fn well_formed_schema_produces_exactly_one_success() {
        let schema = Schema::new(vec![
            Column::new("id", ColumnType::Integer),
            Column::new("label", ColumnType::Text),
        ])
        .expect("hand-written schema is well-formed");
        let findings = check_schema(&schema);
        assert_eq!(findings.len(), 1);
        assert_eq!(findings[0].kind(), FindingKind::Success);
    }
}
