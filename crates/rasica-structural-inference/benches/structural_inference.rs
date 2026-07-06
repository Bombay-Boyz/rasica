//! Benchmarks a full `infer` pass over a synthetic, deterministically
//! generated Dataset with a representative mix of column shapes (an
//! Identifier, a Continuous, and a Categorical column), isolating
//! inference cost from ingestion cost — the same isolation rationale
//! `rasica-validation`'s own `validation` benchmark documents (Phase 4).

#![allow(
    missing_docs,
    clippy::expect_used,
    clippy::unwrap_used,
    clippy::cast_possible_wrap,
    clippy::cast_precision_loss
)]

use criterion::{criterion_group, criterion_main, Criterion};
use rasica_dataset::{
    dataset::{Dataset, DatasetBuilder},
    row::Row,
    schema::{Column, ColumnType, Schema},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};
use rasica_structural_inference::infer;

fn synthetic_dataset(rows: usize) -> Dataset {
    let schema = Schema::new(vec![
        Column::new("id", ColumnType::Integer),
        Column::new("amount", ColumnType::Float),
        Column::new("tier", ColumnType::Text),
    ])
    .expect("synthetic schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    let tiers = ["bronze", "silver", "gold"];
    for r in 0..rows {
        let values = vec![
            Value::Integer(r as i64),
            Value::Float((r % 97) as f64 * 1.5),
            Value::Text(tiers[r % tiers.len()].to_string()),
        ];
        builder.push_row(Row::new(values)).expect("synthetic row matches synthetic schema");
    }
    builder.build(SourceMetadata::new(SourceFormat::InMemory, "synthetic"))
}

fn bench_infer(c: &mut Criterion) {
    let dataset = synthetic_dataset(10_000);
    c.bench_function("infer_10k_rows_3_cols", |b| {
        b.iter(|| infer(&dataset, "synthetic").expect("synthetic dataset is non-empty"));
    });
}

criterion_group!(benches, bench_infer);
criterion_main!(benches);
