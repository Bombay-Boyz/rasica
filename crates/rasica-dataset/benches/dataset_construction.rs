//! Benchmarks `Dataset` construction and fingerprinting at a fixed,
//! documented shape (1,000 rows × 10 columns). This is a regression
//! baseline, not a validation of Appendix H's full target — see §5.4 of
//! the Phase 2 Implementation Specification.
#![allow(missing_docs, clippy::expect_used, clippy::cast_possible_wrap)]

use criterion::{black_box, criterion_group, criterion_main, Criterion};
use rasica_core::prelude::DeterministicFingerprint;
use rasica_dataset::prelude::*;

const ROWS: usize = 1_000;
const COLUMNS: usize = 10;

fn build_dataset() -> Dataset {
    let columns = (0..COLUMNS).map(|i| Column::new(format!("c{i}"), ColumnType::Integer)).collect();
    let schema = Schema::new(columns).expect("fixed benchmark shape is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    for r in 0..ROWS {
        let row = Row::new((0..COLUMNS).map(|c| Value::Integer((r * c) as i64)).collect());
        builder.push_row(row).expect("fixed benchmark shape is well-formed");
    }
    builder.build(SourceMetadata::new(SourceFormat::InMemory, "benchmark"))
}

fn bench_construction(c: &mut Criterion) {
    c.bench_function("dataset_construction_1000x10", |b| {
        b.iter(|| black_box(build_dataset()));
    });
}

fn bench_fingerprint(c: &mut Criterion) {
    let dataset = build_dataset();
    c.bench_function("dataset_fingerprint_1000x10", |b| {
        b.iter(|| black_box(dataset.fingerprint()));
    });
}

criterion_group!(benches, bench_construction, bench_fingerprint);
criterion_main!(benches);
