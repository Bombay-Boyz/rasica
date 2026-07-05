//! The Validation Report (§6.6): the Tier 1 — Immutable (§6.2A) record of
//! every validation activity performed on a Dataset.

use rasica_core::prelude::Immutable;

use crate::finding::{FindingKind, ValidationFinding};

/// Immutable record of every validation activity performed on a Dataset
/// (§6.6). Constructed exclusively via [`ValidationReportBuilder`]; once
/// built, offers no API capable of mutating its contents, satisfying the
/// Tier 1 (§6.2A) `Immutable` marker implemented below.
///
/// Per §6.6's architectural rules: a `ValidationReport` never modifies
/// the Dataset it was built from (this type holds no reference to one,
/// only its `origin` string and shape), and never contains an analytical
/// conclusion — [`ValidationReport::is_structurally_valid`] reports only
/// whether every structural check passed, not any judgement about what
/// the data means.
#[derive(Debug, Clone, PartialEq)]
pub struct ValidationReport {
    origin: String,
    row_count: usize,
    column_count: usize,
    findings: Vec<ValidationFinding>,
}

impl ValidationReport {
    /// The origin (e.g. source path or in-memory tag) of the Dataset this
    /// report was built from.
    #[must_use]
    pub fn origin(&self) -> &str {
        &self.origin
    }

    /// The row count of the Dataset this report was built from.
    #[must_use]
    pub fn row_count(&self) -> usize {
        self.row_count
    }

    /// The column count (schema arity) of the Dataset this report was
    /// built from.
    #[must_use]
    pub fn column_count(&self) -> usize {
        self.column_count
    }

    /// Every finding recorded, in the fixed check order `validate`
    /// documents (schema, datatype, integrity, null analysis, duplicate
    /// detection, then constraints) — the same order on every run for
    /// the same inputs (§15.7, "deterministic diagnostics").
    #[must_use]
    pub fn findings(&self) -> &[ValidationFinding] {
        &self.findings
    }

    /// Findings of exactly `kind`, in recorded order.
    pub fn findings_of_kind(&self, kind: FindingKind) -> impl Iterator<Item = &ValidationFinding> {
        self.findings.iter().filter(move |finding| finding.kind() == kind)
    }

    /// Every recorded [`FindingKind::Success`].
    pub fn successes(&self) -> impl Iterator<Item = &ValidationFinding> {
        self.findings_of_kind(FindingKind::Success)
    }

    /// Every recorded [`FindingKind::Failure`].
    pub fn failures(&self) -> impl Iterator<Item = &ValidationFinding> {
        self.findings_of_kind(FindingKind::Failure)
    }

    /// Every recorded [`FindingKind::Warning`].
    pub fn warnings(&self) -> impl Iterator<Item = &ValidationFinding> {
        self.findings_of_kind(FindingKind::Warning)
    }

    /// Every recorded [`FindingKind::Recommendation`].
    pub fn recommendations(&self) -> impl Iterator<Item = &ValidationFinding> {
        self.findings_of_kind(FindingKind::Recommendation)
    }

    /// Every recorded [`FindingKind::Assumption`].
    pub fn assumptions(&self) -> impl Iterator<Item = &ValidationFinding> {
        self.findings_of_kind(FindingKind::Assumption)
    }

    /// Whether every structural check recorded zero [`FindingKind::Failure`]
    /// findings. This is a purely structural signal (§6.6) — it carries no
    /// judgement about the Dataset's analytical suitability.
    #[must_use]
    pub fn is_structurally_valid(&self) -> bool {
        self.failures().next().is_none()
    }
}

impl Immutable for ValidationReport {}

/// Builder for [`ValidationReport`], mutable only until [`Self::build`]
/// consumes it — the same construction pattern `rasica-dataset`'s own
/// `DatasetBuilder` uses for its Tier 1 object (Document 00B).
pub(crate) struct ValidationReportBuilder {
    origin: String,
    row_count: usize,
    column_count: usize,
    findings: Vec<ValidationFinding>,
}

impl ValidationReportBuilder {
    pub(crate) fn new(origin: impl Into<String>, row_count: usize, column_count: usize) -> Self {
        Self { origin: origin.into(), row_count, column_count, findings: Vec::new() }
    }

    pub(crate) fn extend(&mut self, findings: impl IntoIterator<Item = ValidationFinding>) {
        self.findings.extend(findings);
    }

    pub(crate) fn build(self) -> ValidationReport {
        ValidationReport {
            origin: self.origin,
            row_count: self.row_count,
            column_count: self.column_count,
            findings: self.findings,
        }
    }
}
