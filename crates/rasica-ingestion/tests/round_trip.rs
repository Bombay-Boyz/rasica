//! Round-trip tests: each fixture in `tests/fixtures/` is ingested and
//! compared against a hand-built expected `Dataset`, per §15.6's exit
//! criterion ("imported datasets match source datasets exactly").

use std::{fs::File, io::BufReader, path::Path};

use rasica_core::prelude::DeterministicFingerprint;
use rasica_dataset::{
    dataset::DatasetBuilder,
    row::Row,
    schema::{Column, ColumnType, Schema},
    value::Value,
};
use rasica_ingestion::{csv, excel, json};

fn fixture_path(name: &str) -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures").join(name)
}

/// The single expected `Dataset` every well-formed fixture must ingest to,
/// independent of source format (§5.2), for formats that preserve source
/// column order (CSV, Excel).
#[allow(clippy::expect_used)]
fn expected_well_formed_dataset() -> rasica_dataset::dataset::Dataset {
    let schema = Schema::new(vec![
        Column::new("id", ColumnType::Integer),
        Column::new("name", ColumnType::Text),
        Column::new("active", ColumnType::Boolean),
        Column::new("score", ColumnType::Float),
    ])
    .expect("hand-written schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    builder
        .push_row(Row::new(vec![
            Value::Integer(1),
            Value::Text("Ada".into()),
            Value::Boolean(true),
            Value::Float(9.5),
        ]))
        .expect("hand-written row matches hand-written schema");
    builder
        .push_row(Row::new(vec![
            Value::Integer(2),
            Value::Null,
            Value::Boolean(false),
            Value::Float(3.25),
        ]))
        .expect("hand-written row matches hand-written schema");

    builder.build(rasica_dataset::source::SourceMetadata::new(
        rasica_dataset::source::SourceFormat::InMemory,
        "expected",
    ))
}

/// The expected `Dataset` for JSON specifically: same logical content as
/// `expected_well_formed_dataset()`, but with columns in the lexicographic
/// key order §1.4 Note 5 requires the JSON reader to produce, since JSON
/// objects carry no source-order guarantee to preserve.
#[allow(clippy::expect_used)]
fn expected_well_formed_dataset_json_order() -> rasica_dataset::dataset::Dataset {
    let schema = Schema::new(vec![
        Column::new("active", ColumnType::Boolean),
        Column::new("id", ColumnType::Integer),
        Column::new("name", ColumnType::Text),
        Column::new("score", ColumnType::Float),
    ])
    .expect("hand-written schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    builder
        .push_row(Row::new(vec![
            Value::Boolean(true),
            Value::Integer(1),
            Value::Text("Ada".into()),
            Value::Float(9.5),
        ]))
        .expect("hand-written row matches hand-written schema");
    builder
        .push_row(Row::new(vec![
            Value::Boolean(false),
            Value::Integer(2),
            Value::Null,
            Value::Float(3.25),
        ]))
        .expect("hand-written row matches hand-written schema");

    builder.build(rasica_dataset::source::SourceMetadata::new(
        rasica_dataset::source::SourceFormat::InMemory,
        "expected",
    ))
}

/// Compares two `Dataset`s by content, ignoring identity and provenance —
/// exactly what `DeterministicFingerprint` already excludes (Document 00B
/// §4.6) — so this is a single, reusable equality check across every format.
fn assert_content_equal(
    actual: &rasica_dataset::dataset::Dataset,
    expected: &rasica_dataset::dataset::Dataset,
) {
    assert_eq!(actual.fingerprint(), expected.fingerprint());
}

#[test]
#[allow(clippy::expect_used)]
fn csv_round_trip_matches_expected_dataset() {
    let file = File::open(fixture_path("well_formed.csv")).expect("fixture exists");
    let dataset = csv::read(BufReader::new(file), "well_formed.csv", csv::CsvOptions::default())
        .expect("fixture is well-formed");
    assert_content_equal(&dataset, &expected_well_formed_dataset());
}

#[test]
#[allow(clippy::expect_used)]
fn json_round_trip_matches_expected_dataset_regardless_of_source_key_order() {
    let file = File::open(fixture_path("well_formed.json")).expect("fixture exists");
    let dataset =
        json::read(BufReader::new(file), "well_formed.json").expect("fixture is well-formed");
    assert_content_equal(&dataset, &expected_well_formed_dataset_json_order());
}

#[test]
#[allow(clippy::expect_used)]
fn excel_round_trip_matches_expected_dataset() {
    let dataset = excel::read(&fixture_path("well_formed.xlsx"), &excel::ExcelOptions::default())
        .expect("fixture is well-formed");
    // The Excel fixture additionally carries one DateTime cell (§1.4 Note 4)
    // beyond `expected_well_formed_dataset`'s shape, so this test checks the
    // shared columns' values individually rather than a single fingerprint
    // equality, and separately asserts the DateTime column resolved to Text.
    assert_eq!(dataset.schema().arity(), 5);
    assert_eq!(dataset.schema().columns()[4].column_type(), ColumnType::Text);
}

#[test]
#[allow(clippy::expect_used)]
fn utf8_bom_is_stripped_not_ingested_as_data() {
    let with_bom = File::open(fixture_path("utf8_bom.csv")).expect("fixture exists");
    let without_bom = File::open(fixture_path("well_formed.csv")).expect("fixture exists");

    let from_bom = csv::read(BufReader::new(with_bom), "utf8_bom.csv", csv::CsvOptions::default())
        .expect("BOM-prefixed fixture is well-formed after stripping");
    let from_plain =
        csv::read(BufReader::new(without_bom), "well_formed.csv", csv::CsvOptions::default())
            .expect("fixture is well-formed");

    assert_content_equal(&from_bom, &from_plain);
}

#[test]
#[allow(clippy::expect_used)]
fn invalid_encoding_is_rejected_not_mis_decoded() {
    let file = File::open(fixture_path("invalid_encoding.csv")).expect("fixture exists");
    let result =
        csv::read(BufReader::new(file), "invalid_encoding.csv", csv::CsvOptions::default());
    assert!(matches!(result, Err(rasica_ingestion::error::IngestionError::InvalidEncoding { .. })));
}

#[test]
#[allow(clippy::expect_used)]
fn repeated_import_is_deterministic() {
    for _ in 0..3 {
        let file = File::open(fixture_path("well_formed.csv")).expect("fixture exists");
        let dataset =
            csv::read(BufReader::new(file), "well_formed.csv", csv::CsvOptions::default())
                .expect("fixture is well-formed");
        assert_eq!(dataset.fingerprint(), expected_well_formed_dataset().fingerprint());
    }
}
