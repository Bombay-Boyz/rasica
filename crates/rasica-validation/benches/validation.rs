//! Benchmarks a full `validate` pass (every check, no constraints) over a
//! synthetic, deterministically generated Dataset, isolating validation
//! cost from ingestion cost — the same isolation rationale
//! `rasica-ingestion`'s own `csv_ingestion` benchmark documents (Phase 3).

#![allow(missing_docs, clippy::expect_used, clippy::unwrap_used, clippy::cast_possible_wrap)]

use criterion::{criterion_group, criterion_main, Criterion};
use rasica_dataset::{
    dataset::DatasetBuilder,
    row::Row,
    schema::{Column, ColumnType, Schema},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};
use rasica_validation::{validate, ValidationOptions};

fn synthetic_dataset(rows: usize, columns: usize) -> rasica_dataset::dataset::Dataset {
    let schema = Schema::new(
        (0..columns).map(|c| Column::new(format!("col{c}"), ColumnType::Integer)).collect(),
    )
    .expect("synthetic schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    for r in 0..rows {
        let values =
            (0..columns).map(|c| Value::Integer(((r * columns + c) % 97) as i64)).collect();
        builder.push_row(Row::new(values)).expect("synthetic row matches synthetic schema");
    }
    builder.build(SourceMetadata::new(SourceFormat::InMemory, "synthetic"))
}

fn bench_validate(c: &mut Criterion) {
    let dataset = synthetic_dataset(10_000, 20);
    c.bench_function("validate_10k_rows_20_cols_no_constraints", |b| {
        b.iter(|| validate(&dataset, "synthetic", &[], &ValidationOptions::default()));
    });
}

criterion_group!(benches, bench_validate);
criterion_main!(benches);
