//! Verifies that `rasica-core` and `rasica-common` compose as intended:
//! the tier markers and fingerprinting contract are usable together to
//! define a minimal, hypothetical Tier 1 object, exactly as a real Core
//! Architectural Object will do starting in Phase 2.

use rasica_common::Id;
use rasica_core::prelude::*;

struct ExampleMarker;

/// A minimal stand-in for a future Tier 1 Core Architectural Object,
/// existing only to prove the Phase 1 vocabulary is sufficient to build one.
struct ExampleImmutableObject {
    id: Id<ExampleMarker>,
    payload: String,
}

impl Immutable for ExampleImmutableObject {}

impl Identifiable for ExampleImmutableObject {
    type Marker = ExampleMarker;

    fn id(&self) -> Id<Self::Marker> {
        self.id
    }
}

impl DeterministicFingerprint for ExampleImmutableObject {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        // Deliberately excludes `self.id`: identity is not content, and two
        // objects with different identities but identical payloads should
        // fingerprint identically (§6.2A's caching rule keys on *inputs*,
        // i.e. content, not on identity).
        self.payload.fingerprint_bytes()
    }
}

#[test]
fn tier_and_identity_traits_compose_on_a_real_type() {
    let object = ExampleImmutableObject { id: Id::new(), payload: "example".to_owned() };

    let _ = object.id();
    let _ = object.fingerprint();
}

#[test]
fn objects_with_equal_content_fingerprint_equally_regardless_of_identity() {
    let a = ExampleImmutableObject { id: Id::new(), payload: "same".to_owned() };
    let b = ExampleImmutableObject { id: Id::new(), payload: "same".to_owned() };

    assert_ne!(a.id(), b.id());
    assert_eq!(a.fingerprint(), b.fingerprint());
}

mod dataset_composes_with_core_vocabulary {
    use rasica_core::prelude::*;
    use rasica_dataset::prelude::*;

    #[allow(clippy::expect_used)]
    fn sample_dataset() -> Dataset {
        let schema = Schema::new(vec![
            Column::new("id", ColumnType::Integer),
            Column::new("label", ColumnType::Text),
        ])
        .expect("well-formed schema in test fixture");

        let mut builder = DatasetBuilder::new(schema);
        builder
            .push_row(Row::new(vec![Value::Integer(1), Value::Text("a".into())]))
            .expect("well-formed row in test fixture");

        builder.build(SourceMetadata::new(SourceFormat::InMemory, "test-fixture"))
    }

    #[test]
    fn dataset_is_identifiable_and_fingerprintable() {
        let dataset = sample_dataset();
        let _ = dataset.id();
        let _ = dataset.fingerprint();
    }

    #[test]
    fn metadata_derives_from_dataset_without_mutating_it() {
        let dataset = sample_dataset();
        let metadata = Metadata::derive(&dataset);
        assert_eq!(metadata.columns().len(), dataset.schema().arity());
        // Deriving Metadata does not require, and cannot obtain, `&mut
        // Dataset` — this is checked by the type signature of
        // `Metadata::derive(&Dataset)` compiling at all, not by an
        // assertion here.
    }
}

#[test]
#[allow(clippy::expect_used)]
fn ingests_a_csv_fixture_into_an_immutable_dataset() {
    fn assert_immutable<T: rasica_core::prelude::Immutable>(_: &T) {} // ← move this line up here

    let csv_bytes = b"id,label\n1,alpha\n2,beta\n".as_slice();
    let dataset = rasica_ingestion::csv::read(
        csv_bytes,
        "inline-fixture",
        rasica_ingestion::csv::CsvOptions::default(),
    )
    .expect("inline CSV literal is well-formed");

    assert_eq!(dataset.row_count(), 2);
    assert_eq!(dataset.schema().arity(), 2);
    assert_immutable(&dataset);
}

#[test]
#[allow(clippy::expect_used, clippy::items_after_statements)]
fn validates_a_hand_built_dataset_and_flags_a_duplicate_row() {
    use rasica_dataset::{
        dataset::DatasetBuilder,
        row::Row,
        schema::{Column, ColumnType, Schema},
        source::{SourceFormat, SourceMetadata},
        value::Value,
    };
    use rasica_validation::{validate, ValidationOptions};

    let schema = Schema::new(vec![
        Column::new("id", ColumnType::Integer),
        Column::new("label", ColumnType::Text),
    ])
    .expect("hand-written schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    builder
        .push_row(Row::new(vec![Value::Integer(1), Value::Text("alpha".into())]))
        .expect("hand-written row matches hand-written schema");
    builder
        .push_row(Row::new(vec![Value::Integer(1), Value::Text("alpha".into())]))
        .expect("hand-written row matches hand-written schema");
    let dataset = builder.build(SourceMetadata::new(SourceFormat::InMemory, "smoke"));

    let report = validate(&dataset, "smoke", &[], &ValidationOptions::default());

    assert!(!report.is_structurally_valid());
    assert!(report
        .failures()
        .any(|f| f.category() == rasica_validation::finding::ValidationCategory::Duplicate));

    // Reuses Document 00B's own smoke assertion pattern: Validation Report is Tier 1.
    fn assert_immutable<T: rasica_core::prelude::Immutable>(_: &T) {}
    assert_immutable(&report);
}

#[test]
#[allow(clippy::expect_used, clippy::items_after_statements)]
fn infers_structural_knowledge_from_a_hand_built_dataset() {
    use rasica_dataset::{
        dataset::DatasetBuilder,
        row::Row,
        schema::{Column, ColumnType, Schema},
        source::{SourceFormat, SourceMetadata},
        value::Value,
    };
    use rasica_structural_inference::{infer, VariableRole};

    let schema = Schema::new(vec![
        Column::new("id", ColumnType::Integer),
        Column::new("tier", ColumnType::Text),
    ])
    .expect("hand-written schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    let tiers = ["bronze", "silver", "gold", "bronze", "silver"];
    for (i, tier) in tiers.iter().enumerate() {
        builder
            .push_row(Row::new(vec![
                Value::Integer(i64::try_from(i).unwrap_or(i64::MAX)),
                Value::Text((*tier).into()),
            ]))
            .expect("hand-written row matches hand-written schema");
    }
    let dataset = builder.build(SourceMetadata::new(SourceFormat::InMemory, "smoke"));

    let knowledge = infer(&dataset, "smoke").expect("hand-built dataset has rows");

    assert_eq!(knowledge.column(0).expect("column 0 exists").role(), VariableRole::Identifier);
    assert_eq!(knowledge.column(1).expect("column 1 exists").role(), VariableRole::Categorical);

    // Reuses rasica-validation's own smoke assertion pattern (Phase 4):
    // Structural Knowledge is Tier 1.
    fn assert_immutable<T: rasica_core::prelude::Immutable>(_: &T) {}
    assert_immutable(&knowledge);
}
