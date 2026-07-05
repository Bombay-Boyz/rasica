//! Fault-injection tests per §15.7's verification requirement: known
//! faults are injected and confirmed detected, well-formed data is
//! confirmed to raise no false positives, and repeated runs are
//! confirmed to produce identical reports.

use rasica_dataset::{
    dataset::{Dataset, DatasetBuilder},
    row::Row,
    schema::{Column, ColumnType, Schema},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};
use rasica_validation::{
    constraint::ValidationConstraint, finding::ValidationCategory, validate, NullAnalysisOptions,
    ValidationOptions,
};

#[allow(clippy::expect_used)]
fn well_formed_dataset() -> Dataset {
    let schema = Schema::new(vec![
        Column::new("id", ColumnType::Integer),
        Column::new("name", ColumnType::Text),
        Column::new("revenue", ColumnType::Float),
    ])
    .expect("hand-written schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    builder
        .push_row(Row::new(vec![Value::Integer(1), Value::Text("Ada".into()), Value::Float(100.0)]))
        .expect("row matches schema");
    builder
        .push_row(Row::new(vec![
            Value::Integer(2),
            Value::Text("Grace".into()),
            Value::Float(250.0),
        ]))
        .expect("row matches schema");
    builder.build(SourceMetadata::new(SourceFormat::InMemory, "well_formed"))
}

#[test]
fn well_formed_dataset_raises_no_failures_with_no_constraints() {
    let dataset = well_formed_dataset();
    let report = validate(&dataset, "well_formed", &[], &ValidationOptions::default());
    assert!(report.is_structurally_valid());
    assert_eq!(report.failures().count(), 0);
}

#[test]
#[allow(clippy::expect_used)]
fn duplicate_row_is_detected_and_absence_is_not_false_positive() {
    let clean = well_formed_dataset();
    let clean_report = validate(&clean, "clean", &[], &ValidationOptions::default());
    assert_eq!(
        clean_report.findings_of_kind(rasica_validation::finding::FindingKind::Failure).count(),
        0
    );

    let schema =
        Schema::new(vec![Column::new("id", ColumnType::Integer)]).expect("schema is well-formed");
    let mut builder = DatasetBuilder::new(schema);
    builder.push_row(Row::new(vec![Value::Integer(7)])).expect("row matches schema");
    builder.push_row(Row::new(vec![Value::Integer(7)])).expect("row matches schema");
    let duplicated = builder.build(SourceMetadata::new(SourceFormat::InMemory, "duplicated"));

    let report = validate(&duplicated, "duplicated", &[], &ValidationOptions::default());
    assert!(!report.is_structurally_valid());
    assert!(report.failures().any(|f| f.category() == ValidationCategory::Duplicate));
}

#[test]
#[allow(clippy::expect_used)]
fn high_null_ratio_warns_and_low_ratio_does_not() {
    let schema = Schema::new(vec![Column::new("value", ColumnType::Integer)])
        .expect("schema is well-formed");

    let mut mostly_null = DatasetBuilder::new(schema.clone());
    mostly_null.push_row(Row::new(vec![Value::Null])).expect("row matches schema");
    mostly_null.push_row(Row::new(vec![Value::Null])).expect("row matches schema");
    mostly_null.push_row(Row::new(vec![Value::Integer(1)])).expect("row matches schema");
    let mostly_null_dataset =
        mostly_null.build(SourceMetadata::new(SourceFormat::InMemory, "mostly_null"));

    let report = validate(
        &mostly_null_dataset,
        "mostly_null",
        &[],
        &ValidationOptions {
            null: NullAnalysisOptions::new(0.5).expect("0.5 is a valid threshold"),
        },
    );
    assert!(report.warnings().any(|f| f.category() == ValidationCategory::NullAnalysis));

    let mut no_nulls = DatasetBuilder::new(schema);
    no_nulls.push_row(Row::new(vec![Value::Integer(1)])).expect("row matches schema");
    let no_nulls_dataset = no_nulls.build(SourceMetadata::new(SourceFormat::InMemory, "no_nulls"));

    let clean_report = validate(&no_nulls_dataset, "no_nulls", &[], &ValidationOptions::default());
    assert_eq!(
        clean_report
            .findings()
            .iter()
            .filter(|f| f.category() == ValidationCategory::NullAnalysis
                && f.kind() == rasica_validation::finding::FindingKind::Warning)
            .count(),
        0
    );
}

#[test]
#[allow(clippy::expect_used)]
fn not_null_constraint_violation_is_detected() {
    let schema =
        Schema::new(vec![Column::new("name", ColumnType::Text)]).expect("schema is well-formed");
    let mut builder = DatasetBuilder::new(schema);
    builder.push_row(Row::new(vec![Value::Null])).expect("row matches schema");
    let dataset = builder.build(SourceMetadata::new(SourceFormat::InMemory, "nullable_name"));

    let report = validate(
        &dataset,
        "nullable_name",
        &[ValidationConstraint::NotNull { column: "name".into() }],
        &ValidationOptions::default(),
    );
    assert!(report.failures().any(|f| f.code() == "constraint::not_null_violated"));
}

#[test]
#[allow(clippy::expect_used)]
fn unique_constraint_violation_is_detected() {
    let schema =
        Schema::new(vec![Column::new("id", ColumnType::Integer)]).expect("schema is well-formed");
    let mut builder = DatasetBuilder::new(schema);
    builder.push_row(Row::new(vec![Value::Integer(1)])).expect("row matches schema");
    builder.push_row(Row::new(vec![Value::Integer(1)])).expect("row matches schema");
    let dataset = builder.build(SourceMetadata::new(SourceFormat::InMemory, "duplicate_ids"));

    let report = validate(
        &dataset,
        "duplicate_ids",
        &[ValidationConstraint::Unique { column: "id".into() }],
        &ValidationOptions::default(),
    );
    assert!(report.failures().any(|f| f.code() == "constraint::unique_violated"));
}

#[test]
#[allow(clippy::expect_used)]
fn range_constraint_violation_is_detected_and_valid_data_is_not_a_false_positive() {
    let dataset = well_formed_dataset(); // "revenue" column: 100.0, 250.0.

    let clean_report = validate(
        &dataset,
        "well_formed",
        &[ValidationConstraint::Range { column: "revenue".into(), min: Some(0.0), max: None }],
        &ValidationOptions::default(),
    );
    assert!(!clean_report.failures().any(|f| f.code() == "constraint::range_violated"));

    let schema = Schema::new(vec![Column::new("revenue", ColumnType::Float)])
        .expect("schema is well-formed");
    let mut builder = DatasetBuilder::new(schema);
    builder.push_row(Row::new(vec![Value::Float(-5.0)])).expect("row matches schema");
    let negative_dataset =
        builder.build(SourceMetadata::new(SourceFormat::InMemory, "negative_revenue"));

    let report = validate(
        &negative_dataset,
        "negative_revenue",
        &[ValidationConstraint::Range { column: "revenue".into(), min: Some(0.0), max: None }],
        &ValidationOptions::default(),
    );
    assert!(report.failures().any(|f| f.code() == "constraint::range_violated"));
}

#[test]
#[allow(clippy::expect_used)]
fn constraint_on_absent_column_warns_rather_than_fails() {
    let dataset = well_formed_dataset();
    let report = validate(
        &dataset,
        "well_formed",
        &[ValidationConstraint::NotNull { column: "does_not_exist".into() }],
        &ValidationOptions::default(),
    );
    assert!(report.is_structurally_valid());
    assert!(report.warnings().any(|f| f.code() == "constraint::column_not_found"));
}

#[test]
#[allow(clippy::expect_used)]
fn repeated_validation_of_the_same_dataset_is_deterministic() {
    let dataset = well_formed_dataset();
    let first = validate(&dataset, "well_formed", &[], &ValidationOptions::default());
    for _ in 0..3 {
        let repeat = validate(&dataset, "well_formed", &[], &ValidationOptions::default());
        assert_eq!(first, repeat);
    }
}

#[test]
fn validation_report_is_immutable_tier_1() {
    fn assert_immutable<T: rasica_core::prelude::Immutable>(_: &T) {}
    let dataset = well_formed_dataset();
    let report = validate(&dataset, "well_formed", &[], &ValidationOptions::default());
    assert_immutable(&report);
}
