//! Benchmarks parsing and type-resolution cost in isolation from filesystem
//! variance, by feeding an in-memory, deterministically generated CSV byte
//! buffer through `csv::read` via a `Cursor` — see §5.5 of the Phase 3
//! Implementation Specification.

#![allow(missing_docs, clippy::expect_used, clippy::unwrap_used)]

use std::io::Cursor;

use criterion::{criterion_group, criterion_main, Criterion};
use rasica_ingestion::csv::{read, CsvOptions};

fn synthetic_csv(rows: usize, columns: usize) -> Vec<u8> {
    let mut buffer = String::new();
    let header: Vec<String> = (0..columns).map(|c| format!("col{c}")).collect();
    buffer.push_str(&header.join(","));
    buffer.push('\n');
    for r in 0..rows {
        let row: Vec<String> = (0..columns).map(|c| ((r * columns + c) % 97).to_string()).collect();
        buffer.push_str(&row.join(","));
        buffer.push('\n');
    }
    buffer.into_bytes()
}

fn bench_csv_ingestion(c: &mut Criterion) {
    let bytes = synthetic_csv(10_000, 20);
    c.bench_function("csv_ingest_10k_rows_20_cols", |b| {
        b.iter(|| read(Cursor::new(bytes.clone()), "synthetic", CsvOptions::default()).unwrap());
    });
}

criterion_group!(benches, bench_csv_ingestion);
criterion_main!(benches);
