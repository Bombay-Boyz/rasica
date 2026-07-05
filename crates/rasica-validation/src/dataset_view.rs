//! Isolates the exact read-only accessor names this crate assumes
//! `rasica-dataset` exposes on `Dataset`, `Row`, and `Column`, beyond the
//! `schema()`, `row_count()`, `Schema::arity()`, `Schema::columns()`, and
//! `Column::column_type()` already exercised by `rasica-ingestion`
//! (Phase 3).
//!
//! Every other module in this crate calls through here rather than
//! calling `rasica_dataset` directly for row/value/name access, so that
//! a future rename in `rasica-dataset`'s public surface requires editing
//! exactly one file.

use rasica_dataset::{row::Row, schema::Column, value::Value};

/// This crate's own Dataset accessors, isolated from every check module.
pub(crate) trait DatasetView {
    /// Every row currently held by the Dataset, in a stable, deterministic
    /// order (the order established at construction — §12.10's
    /// deterministic reduction strategy governs how *computation* over
    /// this order may be parallelised, not the order's existence).
    fn validation_rows(&self) -> &[Row];
}

impl DatasetView for rasica_dataset::dataset::Dataset {
    fn validation_rows(&self) -> &[Row] {
        self.rows()
    }
}

/// This crate's own Row accessor.
pub(crate) fn row_values(row: &Row) -> &[Value] {
    row.values()
}

/// This crate's own Column accessor.
pub(crate) fn column_name(column: &Column) -> &str {
    column.name()
}
