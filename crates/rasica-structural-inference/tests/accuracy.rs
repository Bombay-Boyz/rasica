//! The accuracy benchmark (Document 00E §7.2, implementing §15.8's own
//! Verification clause: "Benchmark against manually classified
//! datasets").
//!
//! For each fixture in `tests/fixtures/`, ingests it, runs `infer`, and
//! compares the resulting `VariableRole` for every column against
//! `tests/fixtures/ground_truth.json`'s recorded expectation — read
//! directly from the file rather than hand-duplicated as Rust literals,
//! so the ground truth and this test's assertions cannot silently drift
//! apart across edits (§7.1).
//!
//! Per §7.2: with only two small fixtures as specified here (nine columns
//! total), the practical initial assertion is exact agreement on every
//! single column, a 100% pass rate — the 95% threshold from §1.2 is
//! intended to apply once the corpus is grown large enough for a
//! percentage to be statistically meaningful rather than an artifact of
//! a tiny sample.

use std::collections::HashMap;
use std::fs::File;
use std::io::BufReader;
use std::path::Path;

use rasica_ingestion::csv::{self, CsvOptions};
use rasica_structural_inference::VariableRole;

/// Parses the JSON string form of a `VariableRole` recorded in
/// `ground_truth.json` back into the enum, for comparison against
/// `infer`'s actual output.
fn parse_role(name: &str) -> VariableRole {
    match name {
        "Identifier" => VariableRole::Identifier,
        "Continuous" => VariableRole::Continuous,
        "Categorical" => VariableRole::Categorical,
        "Temporal" => VariableRole::Temporal,
        "Unclassified" => VariableRole::Unclassified,
        other => panic!("ground_truth.json contains an unrecognised VariableRole name: {other:?}"),
    }
}

#[test]
#[allow(clippy::expect_used)]
fn infer_matches_manually_classified_ground_truth() {
    let fixtures_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");

    let ground_truth_raw = std::fs::read_to_string(fixtures_dir.join("ground_truth.json"))
        .expect("ground_truth.json is present");
    let ground_truth: HashMap<String, HashMap<String, String>> =
        serde_json::from_str(&ground_truth_raw).expect("ground_truth.json is well-formed");

    let mut total_columns = 0usize;
    let mut matching_columns = 0usize;
    let mut mismatches = Vec::new();

    // Sorted for a deterministic test-failure message order, independent
    // of filesystem directory-listing order.
    let mut fixture_names: Vec<&String> = ground_truth.keys().collect();
    fixture_names.sort();

    for fixture_name in fixture_names {
        let expected_roles = &ground_truth[fixture_name];
        let fixture_path = fixtures_dir.join(fixture_name);

        // rasica_ingestion::csv::read takes (impl Read, origin, CsvOptions),
        // matching Document 00C's actual signature exactly.
        let file = File::open(&fixture_path)
            .unwrap_or_else(|error| panic!("failed to open fixture {fixture_name:?}: {error}"));
        let dataset = csv::read(BufReader::new(file), fixture_name.clone(), CsvOptions::default())
            .unwrap_or_else(|error| panic!("failed to ingest fixture {fixture_name:?}: {error}"));

        let knowledge = rasica_structural_inference::infer(&dataset, fixture_name.clone())
            .expect("every fixture has at least one row");

        let schema = dataset.schema();
        for (index, column) in schema.columns().iter().enumerate() {
            let column_name = column.name();
            let Some(expected_name) = expected_roles.get(column_name) else {
                panic!("ground_truth.json has no entry for {fixture_name}::{column_name}");
            };
            let expected = parse_role(expected_name);
            let actual = knowledge.column(index).expect("column index is in range").role();

            total_columns += 1;
            if actual == expected {
                matching_columns += 1;
            } else {
                mismatches.push(format!(
                    "{fixture_name}::{column_name}: expected {expected:?}, got {actual:?}"
                ));
            }
        }
    }

    assert!(
        mismatches.is_empty(),
        "structural inference disagreed with manually classified ground truth on {} of {} column(s):\n{}",
        mismatches.len(),
        total_columns,
        mismatches.join("\n")
    );

    // Document 00E §1.2's exit criterion, restated as the interim
    // "100% on this small corpus" reading (§7.2) that the 95% threshold is
    // meant to generalise once the fixture corpus grows.
    #[allow(clippy::cast_precision_loss)]
    let accuracy = matching_columns as f64 / total_columns as f64;
    assert!(
        accuracy >= 0.95,
        "classification accuracy {accuracy:.1}% is below the 95% exit criterion (§1.2)"
    );
}
