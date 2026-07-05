//! `validate`: this crate's single entry point (§15.7), running every
//! check this crate defines, in a fixed order, and assembling their
//! findings into one [`crate::report::ValidationReport`] (§6.6).
//!
//! Check order is fixed, not merely "current": schema, then datatype,
//! then integrity, then null analysis, then duplicate detection, then
//! constraints. Findings are appended to the report in this order and
//! never reordered afterward, so a given Dataset, origin, and constraint
//! set always produce byte-identical report contents run over run —
//! §15.7's "deterministic diagnostics" exit criterion.

use rasica_dataset::dataset::Dataset;

use crate::{
    constraint::{check_constraints, ValidationConstraint},
    datatype_check::check_datatypes,
    duplicate_detection::check_duplicates,
    integrity_check::check_integrity,
    null_analysis::{check_nulls, NullAnalysisOptions},
    report::{ValidationReport, ValidationReportBuilder},
    schema_check::check_schema,
};

/// Runtime configuration for [`validate`].
#[derive(Debug, Clone, Default)]
pub struct ValidationOptions {
    /// Configuration for the null-analysis check.
    pub null: NullAnalysisOptions,
}

/// Runs every structural check this crate defines against `dataset`,
/// plus each constraint in `constraints`, and returns the resulting
/// immutable [`ValidationReport`].
///
/// `origin` is recorded on the report for traceability (e.g. the same
/// origin string `rasica-ingestion` recorded when it produced this
/// Dataset); it is supplied by the caller rather than read off the
/// Dataset, since Validation depends on `rasica-dataset` alone and must
/// not assume any particular provenance-recording convention beyond it
/// (§6.6, "an independent architectural concern").
///
/// This function never fails: every check records what it found — pass,
/// fail, or warning — rather than returning an error, matching §6.6's
/// description of the Validation Report as an unconditional record of
/// validation *activity*, not a gate that can itself be rejected.
#[must_use]
pub fn validate(
    dataset: &Dataset,
    origin: impl Into<String>,
    constraints: &[ValidationConstraint],
    options: &ValidationOptions,
) -> ValidationReport {
    let schema = dataset.schema();
    let mut builder = ValidationReportBuilder::new(origin, dataset.row_count(), schema.arity());

    builder.extend(check_schema(schema));
    builder.extend(check_datatypes(dataset));
    builder.extend(check_integrity(dataset));
    builder.extend(check_nulls(dataset, options.null));
    builder.extend(check_duplicates(dataset));
    builder.extend(check_constraints(dataset, constraints));

    builder.build()
}
