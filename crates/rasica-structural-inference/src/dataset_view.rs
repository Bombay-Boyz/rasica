//! Isolates the exact read-only accessor names this crate assumes
//! `rasica-dataset` exposes on `Dataset`, `Row`, `Schema`, and `Column` —
//! the same isolation convention `rasica-validation` established for
//! Phase 4, and the same four accessor names it already assumes
//! (`Dataset::rows()`, `Row::values()`, `Column::name()`, plus
//! `Column::column_type()`, exercised there by `constraint.rs`).
//!
//! Every other module in this crate calls through here rather than
//! calling `rasica_dataset` directly for row/value/name/type access, so
//! that a future rename in `rasica-dataset`'s public surface requires
//! editing exactly one file.

use rasica_dataset::{
    row::Row,
    schema::{Column, ColumnType},
    value::Value,
};

/// This crate's own Dataset accessor, isolated from every other module.
pub(crate) trait InferenceView {
    /// Every row currently held by the Dataset, in a stable, deterministic
    /// order (the order established at construction).
    fn inference_rows(&self) -> &[Row];
}

impl InferenceView for rasica_dataset::dataset::Dataset {
    fn inference_rows(&self) -> &[Row] {
        self.rows()
    }
}

/// This crate's own Row accessor.
pub(crate) fn row_values(row: &Row) -> &[Value] {
    row.values()
}

/// This crate's own Column name accessor. Currently unused by any
/// heuristic (§4.1: names are deliberately excluded from classification)
/// but kept here, not deleted, so this module's isolation surface stays
/// symmetric with `rasica-validation`'s identical four accessors — a
/// future consumer of `dataset_view` gains this for free without
/// reopening the isolation boundary.
#[allow(dead_code)]
pub(crate) fn column_name(column: &Column) -> &str {
    column.name()
}

/// This crate's own Column type accessor.
pub(crate) fn column_type(column: &Column) -> ColumnType {
    column.column_type()
}
