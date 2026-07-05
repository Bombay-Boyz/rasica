//! Structured outcomes recorded by every check in this crate, matching
//! the Validation Report's five recorded categories (§6.6): successful
//! validations, failed validations, warnings, recommendations, and
//! assumptions.

use std::fmt;

/// Which of §6.6's five recorded outcome categories a single
/// [`ValidationFinding`] belongs to.
///
/// `Success` and `Failure` are the two outcomes of a strict pass/fail
/// structural check (schema, datatype, integrity, and — per constraint —
/// constraint checking). `Warning` flags a condition that is
/// structurally valid but worth surfacing (a high null ratio). This
/// crate's checks are all deterministic pass/fail/warn checks, so
/// `Recommendation` and `Assumption` are defined here as part of the
/// shared vocabulary §6.6 requires, but are not emitted by any Phase 4
/// check; they exist for later phases (e.g. Structural Inference, §15.8,
/// which must make genuine inferential judgement calls) to record
/// findings into the same report structure without a vocabulary change.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FindingKind {
    /// A check ran and found no violation.
    Success,
    /// A check ran and found a definite structural violation.
    Failure,
    /// A check ran and found a condition worth surfacing, short of a
    /// definite violation.
    Warning,
    /// A non-binding suggestion about the Dataset, distinct from a
    /// pass/fail outcome (§6.6). Not emitted by any Phase 4 check.
    Recommendation,
    /// An inferential judgement call a check had to make, recorded so it
    /// is visible rather than silent (§6.6). Not emitted by any Phase 4
    /// check.
    Assumption,
}

/// Which validation activity (§15.7 deliverable) produced a finding.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ValidationCategory {
    /// §9.2 "schema validation".
    Schema,
    /// §9.2 "datatype validation".
    Datatype,
    /// §9.2 "integrity".
    Integrity,
    /// §9.2 "missing values".
    NullAnalysis,
    /// §9.2 "duplicate detection".
    Duplicate,
    /// §11.15 Domain-contributed structural constraints, evaluated here.
    Constraint,
}

/// Where in the Dataset a finding applies, at the coarsest level that is
/// still precise enough to act on.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Location {
    /// The Dataset as a whole (e.g. "schema declares zero columns").
    Dataset,
    /// A single column, identified by both its 0-based index and name
    /// (both are kept: the index is stable under column renaming
    /// mid-report, the name is what a person reads).
    Column {
        /// 0-based column index within the schema.
        index: usize,
        /// The column's declared name.
        name: String,
    },
    /// A single row, identified by its 0-based index.
    Row {
        /// 0-based row index within the Dataset.
        index: usize,
    },
    /// A single cell, identified by 0-based row and column index.
    Cell {
        /// 0-based row index within the Dataset.
        row: usize,
        /// 0-based column index within the schema.
        column: usize,
    },
}

impl fmt::Display for Location {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Dataset => write!(f, "dataset"),
            Self::Column { index, name } => write!(f, "column {index} ('{name}')"),
            Self::Row { index } => write!(f, "row {index}"),
            Self::Cell { row, column } => write!(f, "row {row}, column {column}"),
        }
    }
}

/// One recorded outcome of a single validation activity (§6.6).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidationFinding {
    kind: FindingKind,
    category: ValidationCategory,
    code: &'static str,
    message: String,
    location: Location,
}

impl ValidationFinding {
    /// Constructs a finding. Not exposed outside this crate: every
    /// finding a caller sees was produced by one of this crate's own
    /// checks, never fabricated by a consumer (§6.6, "never contains
    /// analytical conclusions" — a consumer synthesising its own
    /// findings would defeat that guarantee).
    pub(crate) fn new(
        kind: FindingKind,
        category: ValidationCategory,
        code: &'static str,
        message: impl Into<String>,
        location: Location,
    ) -> Self {
        Self { kind, category, code, message: message.into(), location }
    }

    /// The outcome category (§6.6) this finding belongs to.
    #[must_use]
    pub fn kind(&self) -> FindingKind {
        self.kind
    }

    /// Which validation activity (§15.7) produced this finding.
    #[must_use]
    pub fn category(&self) -> ValidationCategory {
        self.category
    }

    /// A stable, machine-matchable identifier for this finding's specific
    /// check (e.g. `"duplicate::row"`), independent of `message`'s
    /// human-readable wording.
    #[must_use]
    pub fn code(&self) -> &'static str {
        self.code
    }

    /// A human-readable description of this finding.
    #[must_use]
    pub fn message(&self) -> &str {
        &self.message
    }

    /// Where in the Dataset this finding applies.
    #[must_use]
    pub fn location(&self) -> &Location {
        &self.location
    }
}

impl fmt::Display for ValidationFinding {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "[{:?}/{}] {} ({})", self.kind, self.code, self.message, self.location)
    }
}
