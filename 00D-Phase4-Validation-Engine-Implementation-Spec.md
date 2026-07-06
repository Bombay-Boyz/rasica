# 00D — Phase 4: Validation Engine — Implementation Specification

> **Provenance note (not present in Documents 00A/00B/00C).** Unlike Documents 00A/00B/00C, this document was reconstructed *after* `rasica-validation`'s scaffold script (`setup_rasica_phase4.sh`) was already written and reviewed, rather than authored first and used to generate the script. It documents, in the same prose-plus-source style as 00A/00B/00C, the design that script already implements — reviewed in full against Architecture Specification §6.6, §8.9, §9.2, §11.15, and §15.7, and found consistent with every convention Documents 00A/00B/00C established. Where this document and the script it describes ever appear to differ, the script (and the working code it produces) is authoritative; this document exists to give Phase 4 the same citable, standalone specification Phases 1–3 have, and to serve as the basis for Document 00E (Phase 5)'s own citations of it.

---

## 1. Objective

Per §15.7:

> Verify structural correctness.

Per §6.6:

> A Validation Report records every validation activity performed on a Dataset. Validation is considered an independent architectural concern.

The second sentence is the phase's central design constraint. Validation is not a gate that ingestion or any other subsystem must pass through to proceed — it is an independent activity that can be run against **any** `Dataset`, regardless of how that `Dataset` was constructed, and it produces a durable record of what it found rather than an accept/reject verdict. Every design decision in this document traces back to that one sentence.

### 1.1 Deliverables (§15.7)

- datatype validation,
- schema validation,
- constraint validation,
- duplicate detection,
- null analysis.

(§9.2 additionally names "integrity" as a sixth responsibility — row-count and per-row-arity consistency — folded into this document's deliverable list as `integrity_check`, since it is the same kind of structural, non-semantic check as the other five and §9.2 is the more detailed of the two source sections.)

### 1.2 Exit criteria (§15.7)

> Inject known faults into benchmark datasets. Confirm: every fault detected, no false positives, deterministic diagnostics. ... Validation accuracy confirmed across all benchmark datasets.

Unlike Document 00E's equivalent exit criterion (Phase 5's "expected accuracy," which had no available quantification and required a **[DRAFT DECISION]**), §15.7's criterion is already exact enough to test directly: every fault a benchmark dataset is deliberately constructed with **shall** produce a corresponding `Failure` finding, no clean dataset **shall** produce a spurious `Failure`, and running the same validation twice **shall** produce byte-identical reports. §7 below specifies the fault-injection test suite that checks all three directly.

---

## 2. Scope

### 2.1 In scope

- A new crate, `rasica-validation`, whose single public entry point, `validate`, consumes an existing `rasica_dataset::dataset::Dataset` and produces an immutable `ValidationReport`.
- Six independent structural checks, each producing zero or more findings: schema, datatype, integrity, null analysis, duplicate detection, and domain-contributed constraints.
- `ValidationConstraint` — a small, closed vocabulary of structural constraints (`NotNull`, `Unique`, `Range`) that a Domain Module will, in a later phase, contribute against a Dataset's columns (§11.15's worked examples — "Revenue shall not be negative," "Machine identifier shall be unique" — map directly onto `Range` and `Unique` respectively).
- A fault-injection test suite verifying §15.7's exit criteria directly.

### 2.2 Out of scope

- **Any semantic judgement about the data.** §6.6 is explicit: the Validation Report "never contains analytical conclusions." A finding that a column is 80% null is a structural fact; whether that is *acceptable* for the analysis a user intends is not this crate's concern.
- **Fixing or modifying the Dataset.** §6.6: "never modifies the Dataset." Every check in this crate is read-only.
- **Discovering what constraints to apply.** `ValidationConstraint` values are supplied by the caller (in a later phase, by the Domain Manager after Domain Module registration, per §11.15); this crate only evaluates constraints it is given, and never invents one from a Dataset's shape (that would be a Structural Inference concern, §6.7, Document 00E — a deliberate, if subtle, boundary: "this column looks like it should be non-null" is an inference, "this column violates the NotNull constraint you gave me" is a check).
- **Consulting any Domain Module directly.** Per §8.9's Forbidden Dependencies table: `Validation → Domain` is explicitly listed as prohibited, with the stated reason "Validation is structural, not semantic." `ValidationConstraint` is therefore *authored* in this crate (§4.6 below), and a Domain Module will, in a later phase, produce `Vec<ValidationConstraint>` values to hand to `validate` — the dependency runs from Domain Module to this crate's type, never the reverse.

---

## 3. Crate layout

```
crates/rasica-validation/
├── Cargo.toml
├── src/
│   ├── lib.rs
│   ├── dataset_view.rs        # isolates this crate's exact Dataset/Row/Column accessor assumptions
│   ├── value_key.rs           # Hash + Eq view of Value, for set/map-based checks
│   ├── finding.rs             # FindingKind, ValidationCategory, Location, ValidationFinding
│   ├── schema_check.rs
│   ├── datatype_check.rs
│   ├── integrity_check.rs
│   ├── null_analysis.rs
│   ├── duplicate_detection.rs
│   ├── constraint.rs          # ValidationConstraint and its evaluation
│   ├── report.rs              # ValidationReport (Tier 1) and ValidationReportBuilder
│   ├── validate.rs            # the validate() entry point and ValidationOptions
│   ├── error.rs
│   └── prelude.rs
├── benches/
│   └── validation.rs
└── tests/
    └── fault_injection.rs
```

`dataset_view.rs` is this document's one deliberate departure from Documents 00A/00B/00C's own convention of calling `rasica_dataset` directly wherever needed: every other check module calls through a narrow, three-function `DatasetView`/`row_values`/`column_name` indirection rather than `rasica_dataset` directly, so that if that crate's public accessor names ever drift, exactly one file needs updating rather than six.

---

## 4. Core types

### 4.1 `FindingKind`, `ValidationCategory`, `Location`

```rust
//! crates/rasica-validation/src/finding.rs

/// Which of §6.6's five recorded outcome categories a single
/// `ValidationFinding` belongs to.
///
/// `Success` and `Failure` are the two outcomes of a strict pass/fail
/// structural check. `Warning` flags a condition that is structurally
/// valid but worth surfacing (a high null ratio). This crate's checks
/// are all deterministic pass/fail/warn checks, so `Recommendation` and
/// `Assumption` are defined here as part of the shared vocabulary §6.6
/// requires, but are not emitted by any Phase 4 check; they exist for
/// later phases (e.g. Structural Inference, Document 00E, which must
/// make genuine inferential judgement calls) to record findings into the
/// same report structure without a vocabulary change.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum FindingKind {
    Success,
    Failure,
    Warning,
    Recommendation,
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
/// still precise enough to act on: the whole Dataset, a single column
/// (by both index and name), a single row, or a single cell.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Location {
    Dataset,
    Column { index: usize, name: String },
    Row { index: usize },
    Cell { row: usize, column: usize },
}
```

### 4.2 `ValidationFinding`

```rust
/// One recorded outcome of a single validation activity (§6.6).
///
/// Constructible only within this crate (`pub(crate) fn new`): every
/// finding a caller observes was produced by one of this crate's own
/// checks, never fabricated by a consumer — a consumer synthesising its
/// own findings would defeat §6.6's "never contains analytical
/// conclusions" guarantee, since a report's trustworthiness rests on
/// every entry in it having actually been checked.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidationFinding {
    kind: FindingKind,
    category: ValidationCategory,
    /// A stable, machine-matchable identifier for this finding's specific
    /// check (e.g. `"duplicate::row"`), independent of the human-readable
    /// message.
    code: &'static str,
    message: String,
    location: Location,
}
```

### 4.3 `ValidationReport`

```rust
//! crates/rasica-validation/src/report.rs

use rasica_core::prelude::Immutable;

/// Immutable record of every validation activity performed on a Dataset
/// (§6.6). Constructed exclusively via `ValidationReportBuilder`; once
/// built, offers no API capable of mutating its contents, satisfying the
/// Tier 1 (§6.2A) `Immutable` marker.
///
/// Per §6.6's architectural rules: a `ValidationReport` never modifies
/// the Dataset it was built from (this type holds no reference to one,
/// only its `origin` string and shape), and never contains an analytical
/// conclusion — `is_structurally_valid` reports only whether every
/// structural check passed, not any judgement about what the data means.
#[derive(Debug, Clone, PartialEq)]
pub struct ValidationReport {
    origin: String,
    row_count: usize,
    column_count: usize,
    findings: Vec<ValidationFinding>,
}

impl Immutable for ValidationReport {}

impl ValidationReport {
    pub fn origin(&self) -> &str { &self.origin }
    pub fn row_count(&self) -> usize { self.row_count }
    pub fn column_count(&self) -> usize { self.column_count }

    /// Every finding recorded, in the fixed check order `validate`
    /// documents (schema, datatype, integrity, null analysis, duplicate
    /// detection, then constraints) — the same order on every run for
    /// the same inputs (§15.7, "deterministic diagnostics").
    pub fn findings(&self) -> &[ValidationFinding] { &self.findings }

    pub fn findings_of_kind(&self, kind: FindingKind) -> impl Iterator<Item = &ValidationFinding>;
    pub fn successes(&self) -> impl Iterator<Item = &ValidationFinding>;
    pub fn failures(&self) -> impl Iterator<Item = &ValidationFinding>;
    pub fn warnings(&self) -> impl Iterator<Item = &ValidationFinding>;
    pub fn recommendations(&self) -> impl Iterator<Item = &ValidationFinding>;
    pub fn assumptions(&self) -> impl Iterator<Item = &ValidationFinding>;

    /// Whether every structural check recorded zero `Failure` findings.
    /// A purely structural signal (§6.6) — no judgement about the
    /// Dataset's analytical suitability.
    pub fn is_structurally_valid(&self) -> bool { self.failures().next().is_none() }
}
```

`ValidationReportBuilder` is the mutable scratch type behind construction, mirroring `DatasetBuilder`'s (Document 00B §4.7) exact split: mutable until `.build()` consumes it, never exposed as a public mutation path on the finished `ValidationReport`.

### 4.4 `NullAnalysisOptions` and `ValidationOptions`

```rust
//! crates/rasica-validation/src/null_analysis.rs

/// Configuration for the null-analysis check.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct NullAnalysisOptions {
    /// A column whose null ratio meets or exceeds this fraction (in
    /// `[0.0, 1.0]`) is recorded as a `Warning` rather than a `Success`.
    warning_threshold: f64,
}
```

`NullAnalysisOptions::new` rejects a threshold outside `[0.0, 1.0]` via `ValidationError::InvalidThreshold` (§4.7). `Default` sets `warning_threshold` to `0.5` — a stated baseline, not a claim that 50% is universally correct, matching the same "baseline to be refined by ADR" stance Appendix H (line 5556 of `rasica-v2.md`) takes toward its own numeric targets.

```rust
//! crates/rasica-validation/src/validate.rs

/// Runtime configuration for `validate`.
#[derive(Debug, Clone, Default)]
pub struct ValidationOptions {
    pub null: NullAnalysisOptions,
}
```

### 4.5 `ValueKey`

```rust
//! crates/rasica-validation/src/value_key.rs

/// A `Hash + Eq` view of `rasica_dataset::value::Value`, used wherever a
/// check needs set/map membership over cell values (duplicate row
/// detection, `Unique` constraint checking) at better than O(n²).
///
/// `Value::Float`'s `f64` is not itself `Hash + Eq` (NaN's reflexivity
/// failure); this hashes the bit pattern instead — exactly as
/// discriminating as the platform's own `f64` equality for every
/// non-NaN value, and treating all NaN payloads as one equivalence
/// class, an acceptable, documented narrowing since duplicate/uniqueness
/// checking needs *an* equivalence relation, not IEEE-754 comparison
/// semantics.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) enum ValueKey {
    Null,
    Boolean(bool),
    Integer(i64),
    Float(u64),
    Text(String),
}
```

### 4.6 `ValidationConstraint`

```rust
//! crates/rasica-validation/src/constraint.rs

/// One structural constraint checked against a single named column.
///
/// Authored in this crate, not in a later Domain SDK phase: the
/// Validation Engine depends only on `rasica-common`/`rasica-core`/
/// `rasica-dataset` and never on any Domain Module (§8.9's Forbidden
/// Dependencies table: "Validation → Domain: Validation is structural,
/// not semantic"), so the dependency must run the other way — a future
/// `DomainModule::contribute_validation` (Appendix G) will return
/// `Vec<ValidationConstraint>` defined *here*. This crate is this type's
/// authority under Appendix G's Type Authority Policy ("promotion is the
/// default path": a later module specification adopts this signature
/// verbatim rather than re-deriving it).
///
/// §11.15's own examples map directly onto the three variants below:
/// "Revenue shall not be negative" is `Range { min: Some(0.0), max: None }`;
/// "Patient age shall be non-negative" is the same shape; "Machine
/// identifier shall be unique" is `Unique`.
///
/// A constraint naming a column absent from the Dataset in hand is not
/// treated as a Dataset defect — Domain Modules are written independent
/// of any one Dataset's shape — so it is recorded as a `Warning`
/// ("not applicable"), never a `Failure`.
#[derive(Debug, Clone, PartialEq)]
pub enum ValidationConstraint {
    NotNull { column: String },
    Unique { column: String },
    Range { column: String, min: Option<f64>, max: Option<f64> },
}
```

### 4.7 `ValidationError`

```rust
//! crates/rasica-validation/src/error.rs

/// Errors from configuring a validation run.
///
/// Running `validate` itself is infallible by design — a Dataset always
/// yields a Validation Report, recording whatever it found (§6.6);
/// failure here means a caller misconfigured the run itself, before any
/// check touched a Dataset.
#[derive(Debug, thiserror::Error, Clone, Copy, PartialEq)]
pub enum ValidationError {
    #[error("threshold {value} is not within [0.0, 1.0]")]
    InvalidThreshold { value: f64 },
}
```

`ValidationError::severity()` returns `ErrorSeverity::Recoverable` unconditionally: the one error condition is caught before any check runs against a Dataset, i.e. before any `ValidationReport` exists — matching `IngestionError`'s identical rationale (Document 00C §4.4).

---

## 5. The six checks

Every check below is a pure function of the `Dataset` (plus, for `check_constraints`, the caller-supplied constraint list); none consult a Domain Module, none mutate the Dataset, and each produces a `Vec<ValidationFinding>` — either exactly one `Success` finding (or, for per-column checks, one per column) when clean, or one `Failure`/`Warning` per violation found, following a "record every occurrence, not just the first" policy consistent with §15.7's "every fault detected."

### 5.1 Schema (`schema_check.rs`)

Checks that the schema is non-empty and every column has a non-empty, unique name.

`rasica-dataset`'s own `Schema::new` (Document 00B §4.2) already rejects a malformed schema at construction time for any Dataset built through the normal `DatasetBuilder` path. This check re-verifies the same invariants independently against whatever `Schema` the Dataset in hand actually reports, because §6.6 declares Validation "an independent architectural concern" — this crate must not assume every Dataset it validates was necessarily built through `rasica-dataset`'s own builder.

### 5.2 Datatype (`datatype_check.rs`)

Checks that every cell's runtime `Value` variant agrees with its column's declared `ColumnType` (a null cell agrees with every column type, matching `rasica-dataset`'s own treatment of `Value::Null`, Document 00B §4.6). For any Dataset built through `DatasetBuilder` this can never fail — the same "independent second verification" rationale as §5.1 applies.

### 5.3 Integrity (`integrity_check.rs`)

Checks that `dataset.row_count()` agrees with the actual number of rows held, and that every row's arity agrees with the schema's arity. Same independent-re-verification rationale as §5.1/§5.2.

### 5.4 Null analysis (`null_analysis.rs`)

Records, per column, its null count and ratio, warning when the ratio meets or exceeds `NullAnalysisOptions::warning_threshold`. A zero-row Dataset records a `Success` per column rather than dividing by zero — the same "resolve absence of evidence to the safe case" stance `rasica-ingestion`'s `ColumnTypeAccumulator` takes for an all-null column (Document 00C §4.3).

### 5.5 Duplicate detection (`duplicate_detection.rs`)

Flags each row that is a content-identical duplicate of an earlier row, using one forward pass with a `HashMap<Vec<ValueKey>, usize>` keyed by first-seen row index — O(n) in row count rather than an O(n²) pairwise comparison, required by Appendix H's stated scale target (up to 10,000,000 rows). A duplicate-of-a-duplicate is always flagged against the *original* first-seen row, not the nearest preceding duplicate, so that grouping duplicates by code/message is unambiguous regardless of how many repeats exist.

### 5.6 Constraints (`constraint.rs`)

For each `ValidationConstraint` in the caller-supplied list: if the named column doesn't exist in the Dataset's schema, record one `Warning` ("not applicable") and move on; otherwise dispatch to `check_not_null`, `check_unique`, or `check_range` as appropriate.

- `check_not_null` — one `Failure` per null value in the column, or one `Success` if none.
- `check_unique` — same forward-pass, first-seen-index pattern as §5.5's duplicate detection, applied to a single column's non-null values (nulls do not participate in uniqueness, matching Document 00C's typing convention for nulls generally).
- `check_range` — for a non-numeric column, one `Warning` ("not applicable") rather than a `Failure`, since a `Range` constraint on a `Text` column is a constraint-authoring mismatch, not a data defect; for a numeric column, one `Failure` per value outside `[min, max]` (either bound optional), or one `Success` if none.

---

## 6. The `validate` entry point

```rust
//! crates/rasica-validation/src/validate.rs

/// Runs every structural check this crate defines against `dataset`,
/// plus each constraint in `constraints`, and returns the resulting
/// immutable `ValidationReport`.
///
/// Check order is fixed, not merely "current": schema, then datatype,
/// then integrity, then null analysis, then duplicate detection, then
/// constraints. Findings are appended to the report in this order and
/// never reordered afterward, so a given Dataset, origin, and constraint
/// set always produce byte-identical report contents run over run —
/// §15.7's "deterministic diagnostics" exit criterion.
///
/// `origin` is recorded on the report for traceability (e.g. the same
/// origin string `rasica-ingestion` recorded when it produced this
/// Dataset); it is supplied by the caller rather than read off the
/// Dataset, since Validation depends on `rasica-dataset` alone and must
/// not assume any particular provenance-recording convention beyond it.
///
/// This function never fails: every check records what it found — pass,
/// fail, or warning — rather than returning an error, matching §6.6's
/// description of the Validation Report as an unconditional record of
/// validation *activity*, not a gate that can itself be rejected.
#[must_use]
pub fn validate(
    dataset: &rasica_dataset::dataset::Dataset,
    origin: impl Into<String>,
    constraints: &[ValidationConstraint],
    options: &ValidationOptions,
) -> ValidationReport {
    // schema → datatype → integrity → null analysis → duplicate detection → constraints,
    // each check's findings appended to one ValidationReportBuilder in that fixed order.
}
```

---

## 7. Testing: fault injection

Per §15.7's Verification clause ("Inject known faults into benchmark datasets. Confirm: every fault detected, no false positives, deterministic diagnostics"), `tests/fault_injection.rs` covers, at minimum:

- **Duplicate rows** — a hand-built Dataset with one deliberately repeated row; assert exactly one `Duplicate`-category `Failure` fires, and that a clean Dataset with no repeated rows produces zero.
- **High null ratio** — a Dataset with a column exceeding the configured `NullAnalysisOptions` threshold; assert a `NullAnalysis`-category `Warning` fires, and a clean, low-null-ratio Dataset produces none.
- **`NotNull` constraint violation** — assert the corresponding `constraint::not_null_violated` failure fires only when a genuinely null value is present under that constraint.
- **`Unique` constraint violation** — same pattern, for duplicate non-null values in a constrained column.
- **`Range` constraint violation, both directions** — assert a value inside `[min, max]` produces no failure (no false positive) and a value outside it does (fault detected) — a single test exercising both halves of §15.7's "every fault detected, no false positives" pair directly against the same constraint.
- **Constraint on an absent column** — assert this produces a `Warning`, not a `Failure`, and that `is_structurally_valid()` remains `true`.
- **Determinism** — running `validate` three times against the same Dataset, origin, and constraints produces three `ValidationReport` values that are all `==` to each other (report equality is possible here because `ValidationReport` derives `PartialEq` directly, unlike `Dataset`, which relies on `DeterministicFingerprint` — a report contains no identity field analogous to `Dataset`'s `Id`, so structural equality is already the right comparison).
- **Tier 1 compliance** — `assert_immutable::<ValidationReport>()`, the same pattern Document 00B's smoke test established.

---

## 8. Workspace integration

Following the same additive pattern as the Phase 2/Phase 3 scaffold scripts:

- New workspace member: `crates/rasica-validation`.
- No new `[workspace.dependencies]` entries required — `thiserror`, `proptest`, `rstest`, and `criterion` are already present from Phases 1–3.
- `tests/workspace_smoke` extension: one new smoke test (`validates_a_hand_built_dataset_and_flags_a_duplicate_row`) building a two-row Dataset with a deliberate duplicate, asserting `validate` flags it and that the resulting `ValidationReport` is `Immutable`.

---

## 9. Exit criteria checklist (§15.7)

- [ ] Every fault type in §7's list is detected when present.
- [ ] None of §7's clean-data cases produce a false-positive `Failure`.
- [ ] `validate` run repeatedly against the same inputs produces `==` reports (§7's determinism test).
- [ ] `ValidationReport` is `Tier 1 — Immutable` per §6.2A, verified by `assert_immutable::<ValidationReport>()`.
- [ ] `#![forbid(unsafe_code)]` present; `cargo clippy --workspace --all-targets -- -D warnings`, `cargo fmt --all -- --check`, `cargo deny check` all pass, matching every prior phase's bar.
- [ ] No dependency from `rasica-validation` on any Domain Module crate (there are none yet to depend on, but the crate's `Cargo.toml` dependency list — `rasica-common`, `rasica-core`, `rasica-dataset`, `thiserror` only — is itself evidence §8.9's Forbidden Dependency is respected structurally, not just by absence of opportunity).

---

## 10. Relationship to Document 00E (Phase 5)

Document 00E (Structural Inference) depends on this document only for pipeline sequencing (§8.3's dependency graph), not for any Rust-level data: `ValidationReport` (§4.3 above) carries findings, row/column counts, and an origin string — nothing Structural Inference's heuristics need to consume. Document 00E's `rasica-structural-inference` crate therefore depends on `rasica-dataset` directly, not on `rasica-validation`, and can be implemented independently of whether this document's crate has been built and merged first.
