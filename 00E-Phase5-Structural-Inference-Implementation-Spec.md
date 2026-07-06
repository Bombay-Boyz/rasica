# 00E — Phase 5: Structural Inference — Implementation Specification

> **Status note (not present in Documents 00A/00B/00C).** This document was drafted by an AI assistant at the user's request, directly from Architecture Specification `rasica-v2.md` §6.7 ("Structural Knowledge"), §8.3 ("Core Dependency Graph"), §9.3 ("Structural Inference Engine"), and §15.8 ("Phase 5 — Structural Inference"). Unlike Documents 00A/00B/00C, no human-authored companion "06 Structural Inference Specification" (referenced in the Architecture Specification's own document index, Appendix, but not supplied to the assistant) was available as a source. Every design decision below that goes beyond what the Architecture Specification states outright — heuristic thresholds, the exact shape of `StructuralKnowledge`, the accuracy metric used for the exit criterion — is flagged inline as a **[DRAFT DECISION]** and should be reviewed and either ratified or revised before treating this document as authoritative in the same sense as 00A/00B/00C.

---

## 0. Prerequisite: Phase 4's status

Per §8.3's Core Dependency Graph, the pipeline order is:

```
Dataset Engine → Validation Engine → Structural Inference Engine → Structural Knowledge → Knowledge Graph
```

Structural Inference sits **downstream of the Validation Engine** in the authoritative dependency graph — not because Structural Knowledge is computed *from* the Validation Report's contents (§6.7 defines Structural Knowledge as derived from the Dataset alone: "everything the Core Engine can determine about a Dataset without consulting Domain Modules"), but because §7.4/§8.3 fix Validation as the pipeline stage that runs immediately before it.

At the time of writing, a Phase 4 scaffold script (`setup_rasica_phase4.sh`, producing `rasica-validation`) exists but had not yet been reviewed or run against this workspace when this document was drafted. That script was reviewed separately and found consistent with the conventions established by Documents 00A/00B/00C — in particular, its `crates/rasica-validation/src/report.rs` defines `ValidationReport` as a plain record of findings, row count, column count, and origin string, with no field this crate's algorithms would need to consume. This document specifies Phase 5 on the basis that:

- **[DRAFT DECISION]** `rasica-structural-inference`'s only compile-time dependency is `rasica-dataset` (plus `rasica-common`/`rasica-core`), matching §6.7's stated data dependency exactly. It does **not** depend on a `rasica-validation` crate, since no Rust-level data from the Validation Report is consumed by any type or algorithm defined here.
- Implementing this phase's code today does not violate the dependency graph — the graph constrains what depends on what, and `rasica-structural-inference → rasica-dataset` is a valid, permitted edge regardless of whether `rasica-validation` exists yet.
- It **does** mean the full pipeline (§8.3) is not yet assemblable end-to-end, since the Validation Engine stage between them is missing. If sequencing fidelity to the roadmap matters more than unblocking Structural Inference's own implementation, **Phase 4 should be built first**; this document does not depend on that being done, but the roadmap's own numbering (§15.7 before §15.8) suggests it.

The rest of this document proceeds as though Phase 4 exists in the pipeline sense but is irrelevant to Phase 5's implementation.

---

## 1. Objective

Per §15.8:

> Construct Structural Knowledge.

Per §6.7:

> Structural Knowledge represents everything the Core Engine can determine about a Dataset without consulting Domain Modules. ... Structural Knowledge provides the factual basis upon which semantic reasoning later operates. It contains no interpretation.

The last sentence is the load-bearing constraint on this entire phase: every fact this crate produces must be a **structural, mechanically verifiable observation** (e.g. "this column's values are drawn from a finite, small set, repeated across rows" → categorical), never a **semantic claim** (e.g. "this column represents customer age" is a Domain Fact, §6.9, out of scope here).

### 1.1 Deliverables (§15.8)

Automatic identification of:

- identifiers,
- continuous variables,
- categorical variables,
- temporal variables,
- distributions,
- relationships.

### 1.2 Exit criterion (§15.8)

> Structural inference achieves expected accuracy [against] benchmark[s of] manually classified datasets.

**[DRAFT DECISION]** "Expected accuracy" is not quantified in the Architecture Specification. This document adopts, as a concrete and testable substitute pending ratification:

> On the benchmark corpus defined in §7 below, `infer` classifies at least **95%** of columns into the same `VariableRole` a human reviewer assigned by manual inspection, and produces zero `VariableRole::Identifier` false positives (a non-identifier column classified as an identifier is considered a more costly error than the reverse, since downstream consumers — e.g. a future Rule Engine — are expected to treat identifiers specially, such as excluding them from statistical aggregation).

This numeric threshold, and the asymmetric treatment of identifier false positives, are this document's own proposal, not a restatement of anything in `rasica-v2.md`.

---

## 2. Scope

### 2.1 In scope

- A new crate, `rasica-structural-inference`, that consumes an existing `rasica_dataset::dataset::Dataset` (and, incidentally, the `Metadata` Phase 2 already knows how to derive from one) and produces a `StructuralKnowledge` value.
- Deterministic classification of each column into exactly one `VariableRole`: `Identifier`, `Continuous`, `Categorical`, `Temporal`, or `Unclassified` (the last covering columns that fail every heuristic below — see §5.6; **[DRAFT DECISION]**, since §6.7 does not enumerate an explicit "none of the above" case, but every classification function must be total).
- A `DistributionSummary` for every column classified `Continuous`.
- A `CategorySummary` for every column classified `Categorical`.
- **Pairwise relationship evidence** between columns: at minimum, identifier-to-identifier candidate key/foreign-key evidence (§6.8's example graph — `Revenue → generated_by → Customer` — is exactly the kind of edge a later Knowledge Engine phase would build from this evidence, but constructing the Knowledge Graph itself is Phase 6's job, not this one).
- A benchmark harness comparing `infer`'s output against a small, hand-labelled corpus of fixture datasets, per the exit criterion in §1.2.

### 2.2 Out of scope (deferred to later phases or explicitly excluded by §6.7)

- **Any semantic interpretation** ("this looks like a revenue column") — Domain Facts, §6.9, Phase 7+.
- **The Knowledge Graph itself** — Phase 6.
- **Validation** (schema/datatype/constraint checking) — Phase 4; `rasica-structural-inference` assumes its input `Dataset` is already well-formed at the `rasica-dataset` level (i.e. every `Row` already agrees with its `Schema`, which `DatasetBuilder` already guarantees unconditionally — see Document 00B §4.7), and performs no additional correctness checking of its own.
- **Learned or probabilistic classification.** Per Architecture Specification Principle 1/Principle 2 (referenced at line 2727 of `rasica-v2.md` in the context of Applicability Predicates, but stated as a document-wide principle), RASICA's analytical decisions are deterministic, explicit, auditable formulas — never trained models, heuristics with hidden randomness, or anything whose output could differ between two runs on the same input. Every heuristic in §5 is a **closed-form, deterministic function** of the column's values; none of them involve sampling, hashing-with-random-seed, or floating-point operations sensitive to summation order (see §5.1's determinism note).
- **Full statistical distribution fitting** (e.g. testing for normality, fitting a parametric family). §6.7 lists "distributions" as a Structural Knowledge concern, but doing this rigorously is properly the Statistics Engine's job (§9.10, much later in the roadmap). This document produces a **`DistributionSummary`** of simple, deterministic descriptive statistics (min/max/mean/quartiles) sufficient to be a useful structural fact, without claiming to identify a distribution family.

---

## 3. Crate layout

```
crates/rasica-structural-inference/
├── Cargo.toml
├── src/
│   ├── lib.rs
│   ├── role.rs              # VariableRole and the per-role classification heuristics
│   ├── distribution.rs      # DistributionSummary and its derivation
│   ├── category.rs          # CategorySummary and its derivation
│   ├── relationship.rs      # RelationshipEvidence and pairwise candidate-key detection
│   ├── knowledge.rs         # StructuralKnowledge (the Tier 1 object) and infer()
│   ├── error.rs
│   └── prelude.rs
├── benches/
│   └── structural_inference.rs
└── tests/
    ├── fixtures/
    │   ├── customers_ground_truth.csv   # hand-labelled: id, name, signup_date, tier, lifetime_value
    │   ├── sensor_readings_ground_truth.csv
    │   └── ground_truth.json            # column_name -> expected VariableRole, per fixture
    └── accuracy.rs
```

This mirrors Documents 00A/00B/00C's convention: one crate per phase, a `prelude.rs` re-exporting the consumer-facing surface, and a `tests/fixtures/` + accuracy-style integration test analogous to Document 00C's `round_trip.rs`.

---

## 4. Core types

### 4.1 `VariableRole`

```rust
//! crates/rasica-structural-inference/src/role.rs

/// The structural role §6.7/§9.3 assigns to a single column, determined
/// solely from the column's own values — never from its name, and never
/// from any Domain Module (§6.7: "without consulting Domain Modules").
///
/// Column *names* are deliberately excluded from every heuristic in this
/// crate, even though a name like `"customer_id"` is a strong informal
/// signal: using it would make classification depend on naming
/// convention rather than on structure, which is exactly the
/// structural/semantic boundary §6.7 draws. A column named `"x"` and a
/// column named `"customer_id"` containing identical values must
/// classify identically.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum VariableRole {
    /// Every non-null value is unique across the column, and the column's
    /// declared type ([`rasica_dataset::schema::ColumnType`]) is
    /// [`ColumnType::Integer`] or [`ColumnType::Text`] (§5.2).
    Identifier,
    /// Numeric values spanning a range wide enough, relative to the row
    /// count, that treating each distinct value as its own category would
    /// not be informative (§5.3).
    Continuous,
    /// A small, repeated set of distinct values relative to the row count
    /// (§5.4).
    Categorical,
    /// Text values that parse as one of a fixed set of recognised
    /// date/time textual formats (§5.5). Phase 3 (Document 00C, §1.4
    /// Note 4) deliberately stores all temporal values as
    /// [`ColumnType::Text`] rather than a dedicated timestamp type, so
    /// this role exists precisely to recover that fact structurally.
    Temporal,
    /// No heuristic below claimed the column. This is a legitimate,
    /// non-error outcome (e.g. a free-text comments column, or a
    /// constant column with only one non-null value) — see §5.6.
    Unclassified,
}
```

### 4.2 `DistributionSummary`

```rust
//! crates/rasica-structural-inference/src/distribution.rs

/// A deterministic, closed-form descriptive summary of a `Continuous`
/// column's values (§6.7's "distributions" deliverable, scoped per §2.2 to
/// descriptive statistics rather than distribution-family fitting).
///
/// All five fields are computed from the column's non-null values only;
/// nulls are excluded from every statistic, consistent with
/// `rasica_dataset::metadata::Metadata`'s own treatment of nullability
/// as a separate, per-column fact (Document 00B §4.5) rather than a value
/// participating in numeric summaries.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DistributionSummary {
    minimum: f64,
    maximum: f64,
    mean: f64,
    median: f64,
    /// The population standard deviation (divisor `n`, not `n - 1`):
    /// Structural Knowledge describes the dataset's *own* observed
    /// spread, not an inference about a hypothetical larger population,
    /// so the population (not sample) formula is the structurally
    /// correct one here.
    standard_deviation: f64,
}
```

**[DRAFT DECISION] Determinism note.** Computing `mean` and `standard_deviation` by naive sequential summation over `Vec<f64>` is technically summation-order-dependent at the level of floating-point rounding (though not at any level a human or a `95%`-accuracy benchmark would notice). To make this crate's fingerprints byte-for-byte reproducible in the same strong sense Document 00A §5.4 requires of `DeterministicFingerprint`, `distribution.rs` **shall** sort the column's non-null values before summing (an `O(n log n)` cost already paid for `median`), rather than summing in row order. This is a stricter interpretation of determinism than strictly required for a *statistic* (row order does not change the population's mean), but it is required for the *fingerprint* of the resulting `DistributionSummary` to be reproducible across two runs whose only difference is an irrelevant upstream row-ordering change (e.g. a different but logically-equivalent CSV reader implementation) — matching the same principle Document 00B §4.3's `join` operation relies on (commutative, order-independent folding).

### 4.3 `CategorySummary`

```rust
//! crates/rasica-structural-inference/src/category.rs

/// A deterministic summary of a `Categorical` column (§6.7's "categorical
/// variables" deliverable).
#[derive(Debug, Clone, PartialEq)]
pub struct CategorySummary {
    /// Each distinct non-null value observed, together with its
    /// occurrence count, sorted by the value's own `Ord`-comparable
    /// canonical text rendering (not by frequency) — frequency-sorting
    /// would make the field order depend on the data's row-count
    /// distribution, which is a fingerprint-determinism hazard of
    /// exactly the kind described in §4.2 above.
    categories: Vec<CategoryCount>,
}

/// One distinct value's occurrence count within a `Categorical` column.
#[derive(Debug, Clone, PartialEq)]
pub struct CategoryCount {
    /// The category's canonical text rendering (via
    /// [`rasica_dataset::value::Value`]'s own `Display`-equivalent
    /// rendering — §5.4 specifies exactly how each `ColumnType` is
    /// rendered).
    label: String,
    /// The number of rows in which this value occurred.
    count: u64,
}
```

### 4.4 `RelationshipEvidence`

```rust
//! crates/rasica-structural-inference/src/relationship.rs

/// A single piece of deterministic, mechanically-observed evidence that
/// two columns (possibly in different `Dataset`s) may be related —
/// §6.7's "relationships" deliverable, scoped deliberately to *evidence*
/// rather than a resolved semantic relationship: interpreting
/// `RelationshipEvidence` into an actual graph edge (§6.8's
/// `Revenue --generated_by--> Customer` example) is the Knowledge
/// Engine's job (Phase 6, §9.4), not this crate's.
#[derive(Debug, Clone, PartialEq)]
pub struct RelationshipEvidence {
    left: ColumnRef,
    right: ColumnRef,
    kind: RelationshipKind,
}

/// Identifies one column within one `Dataset` by position, since
/// `rasica_dataset::schema::Column` does not itself carry a stable
/// identity (Document 00B defines `Dataset`, not individual columns, as
/// `Identifiable` — see Document 00B §4.6).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ColumnRef {
    dataset_id: rasica_common::Id<rasica_dataset::dataset::DatasetMarker>,
    column_position: usize,
}

/// The specific, mechanically-checkable relationship a piece of evidence
/// asserts. Each variant names the exact check performed, so that two
/// independent implementations of the same check (per the Applicability
/// Predicate determinism requirement quoted in §2.2) are guaranteed to
/// agree.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RelationshipKind {
    /// Both columns are classified `Identifier`, and every non-null value
    /// in `right` also appears as a value in `left` (§5.7's candidate
    /// foreign-key check). This does not distinguish which side is the
    /// "parent" — that is a semantic judgement out of scope here — it
    /// only records that the subset relationship holds in this direction.
    ValueSubset,
}
```

### 4.5 `StructuralKnowledge`

```rust
//! crates/rasica-structural-inference/src/knowledge.rs

use rasica_core::prelude::Immutable;

/// The Structural Knowledge Core Architectural Object (Architecture
/// Specification §6.7): everything the Core Engine can determine about a
/// `Dataset` without consulting Domain Modules.
///
/// `StructuralKnowledge` is Tier 1 (Immutable, §6.2A/rasica-v2.md line
/// 458): constructed exclusively by [`infer`], never mutated afterward.
/// A later phase that learns more about a `Dataset`'s structure (there is
/// none currently planned — Structural Inference is the terminal producer
/// of this object per §8.3) would construct a new `StructuralKnowledge`,
/// mirroring Document 00B §4.5's `Metadata::derive` precedent exactly.
#[derive(Debug, Clone, PartialEq)]
pub struct StructuralKnowledge {
    dataset_id: rasica_common::Id<rasica_dataset::dataset::DatasetMarker>,
    columns: Vec<ColumnKnowledge>,
    relationships: Vec<crate::relationship::RelationshipEvidence>,
}

impl Immutable for StructuralKnowledge {}

/// The per-column portion of `StructuralKnowledge`.
#[derive(Debug, Clone, PartialEq)]
pub struct ColumnKnowledge {
    role: crate::role::VariableRole,
    /// `Some` if and only if `role` is [`VariableRole::Continuous`].
    distribution: Option<crate::distribution::DistributionSummary>,
    /// `Some` if and only if `role` is [`VariableRole::Categorical`].
    categories: Option<crate::category::CategorySummary>,
}
```

**[DRAFT DECISION]** Representing `distribution`/`categories` as `Option` fields that are conditionally `Some` based on `role`, rather than folding `role` and its associated data into a single enum (`VariableRoleData::Continuous(DistributionSummary)`, etc.), is a deliberate choice to keep `VariableRole` a plain, `Copy`, comparison-friendly enum usable on its own (e.g. as a `RelationshipEvidence` precondition check, §4.4) without always dragging a `DistributionSummary`/`CategorySummary` along. The invariant "exactly one of these two fields is `Some`, and which one is determined by `role`" is not encoded in the type system as a result, and **shall** be enforced by a single private constructor (`ColumnKnowledge::new`, not shown) that every code path in `knowledge.rs` goes through — the same "one door in" convention `rasica_dataset::dataset::Dataset` uses via `DatasetBuilder`.

---

## 5. Classification heuristics

Each heuristic below is stated as a **total, deterministic function of one column's values and declared `ColumnType`** (never of the column's name, per §4.1's rationale). `infer` (§6) evaluates them in the fixed order given, and a column receives the role of the **first** heuristic that claims it — i.e. this is a decision list, not a scoring competition, which keeps the classification auditable as a simple, explicit precedence rule rather than a weighted formula (consistent with the Applicability Predicate style of determinism quoted in §2.2: "an explicit, auditable formula," not a black box).

### 5.1 Ordering and determinism

1. Identifier (§5.2)
2. Temporal (§5.5)
3. Categorical (§5.4)
4. Continuous (§5.3)
5. Unclassified (§5.6, the default)

**[DRAFT DECISION]** Temporal is checked *before* Categorical deliberately: a column of 3 distinct date strings repeated many times (e.g. a `"report_month"` column with only three possible values in the dataset) would otherwise satisfy the Categorical heuristic's low-cardinality test first and never be recognised as Temporal. Checking type-shape heuristics (Identifier, Temporal) before count-shape heuristics (Categorical, Continuous) avoids this class of false negative.

### 5.2 Identifier

A column is `Identifier` if and only if:
- its declared [`ColumnType`] is `Integer` or `Text` (never `Boolean` or `Float` — a boolean or float column with all-unique values, e.g. a float column that happens to have no duplicates in a small sample, is not what "identifier" structurally means), **and**
- every non-null value is distinct (i.e. `distinct_count == non_null_count`, exactly [`rasica_dataset::metadata::ColumnMetadata::unique`] as already computed by Document 00B §4.5 — this heuristic reuses that computation rather than re-deriving it), **and**
- the column is not entirely null (an all-null column is vacuously "unique" and must not be classified `Identifier`).

### 5.3 Continuous

A column is `Continuous` if and only if:
- its declared `ColumnType` is `Integer` or `Float`, **and**
- it was not already claimed by Identifier or Temporal, **and**
- its distinct-value count (excluding nulls) is greater than **[DRAFT DECISION]** `max(20, row_count / 20)` — i.e. either at least 20 distinct values in absolute terms, or the values are at least 5% distinct relative to row count, whichever bound is larger. This dual threshold avoids two failure modes of a single fixed cutoff: a small dataset (50 rows) with 15 distinct integer values would fail a fixed "distinct_count > 20" rule despite clearly being continuous in nature, while a huge dataset (10,000,000 rows) with exactly 20 distinct values is clearly categorical despite passing a fixed "distinct_count > 20" rule.

### 5.4 Categorical

A column is `Categorical` if and only if it was not already claimed by Identifier, Temporal, or Continuous, and its distinct-value count (excluding nulls) is at least 1 (i.e. the column is not entirely null) — in other words, **Categorical is the residual claim for any non-null, non-identifier, non-temporal, non-widely-varying column**, covering `Boolean` columns unconditionally (a boolean column can never satisfy §5.3's threshold, since it has at most 2 distinct values) as well as low-cardinality `Integer`/`Float`/`Text` columns.

### 5.5 Temporal

A column is `Temporal` if and only if:
- its declared `ColumnType` is `Text` (per Document 00C §1.4 Note 4, a genuinely date-valued Excel cell is already resolved to `ColumnType::Text` at ingestion time — see Document 00C §4.6 — so no separate date `ColumnType` exists for this heuristic to check against), **and**
- at least **[DRAFT DECISION]** 90% of the column's non-null values parse successfully against at least one member of a fixed, documented set of recognised formats: `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM:SS` (RFC 3339-style, without requiring a timezone offset), and `MM/DD/YYYY`. This is deliberately a small, closed, and explicitly enumerated format list — **not** an attempt at general-purpose date parsing — matching the "closed enumeration" style Document 00C's own `SourceFormat` and `ColumnType` use. The 90% threshold (rather than 100%) tolerates a small number of genuinely malformed entries in an otherwise-temporal column without demanding Phase 4's validation machinery run first (§0's prerequisite note).

### 5.6 Unclassified

Any column not claimed above (in practice: an entirely-null column, or a `Text` column with high cardinality that isn't recognisably temporal — e.g. free-text comments) is `Unclassified`. This is a legitimate terminal state, not an error: `infer` (§6) never fails because a column is `Unclassified`.

### 5.7 Relationship evidence

For every pair of columns (across the single `Dataset` being inferred over — cross-`Dataset` relationship evidence is a **[DRAFT DECISION] deferred capability**, not implemented in this phase, since it requires holding multiple `Dataset`s' `StructuralKnowledge` simultaneously, which has no defined entry point yet) both classified `Identifier`:

- compute the set of `left`'s non-null values and the set of `right`'s non-null values,
- if `right`'s value set is a non-empty subset of `left`'s, record one `RelationshipEvidence` with `kind: ValueSubset`.

This is deliberately the simplest possible mechanically-checkable relationship signal (plain set inclusion, no fuzzy matching, no name similarity), consistent with §2.2's exclusion of anything semantic or probabilistic from this phase.

---

## 6. The `infer` entry point

```rust
//! crates/rasica-structural-inference/src/knowledge.rs (continued)

/// Constructs [`StructuralKnowledge`] for `dataset`, by inspection alone
/// (§6.7: "without consulting Domain Modules").
///
/// This performs one pass per column to resolve its [`VariableRole`]
/// (§5), plus a second pass to derive that role's associated summary
/// (§4.2/§4.3), plus one pairwise comparison per `(Identifier, Identifier)`
/// column pair (§5.7) — the same "resolve type/role first, then build
/// the typed representation in a second pass" structure Document 00C's
/// `csv::read`/`json::read` already use for column-type resolution
/// (Document 00C §4.5/§4.7), applied here one level up.
///
/// # Errors
///
/// This function is infallible in the sense that matters architecturally
/// — every column receives *some* `VariableRole`, including the
/// catch-all `Unclassified` (§5.6) — but returns
/// [`InferenceError::EmptyDataset`] for a zero-row `Dataset`, since no
/// heuristic in §5 is meaningful without at least one row to observe.
pub fn infer(dataset: &rasica_dataset::dataset::Dataset) -> Result<StructuralKnowledge, crate::error::InferenceError> {
    // Implementation: see §5 for the per-column decision list, §5.7 for
    // relationship evidence. Full source intentionally omitted from this
    // specification document — Documents 00A/00B/00C include full source
    // because their assistant-driven scaffolding step (this same
    // conversation) generates working code directly from them; this
    // document is a design specification to review before that same
    // scaffolding step is run for Phase 5, so the heuristics in §5 are
    // specified precisely enough to implement from, without pre-committing
    // to exact code the reviewer has not yet seen.
    todo!()
}
```

**[DRAFT DECISION]** Unlike Documents 00A/00B/00C (which were scaffolded directly, with full source, in the same sitting they were specified), this document stops short of providing complete `.rs` file contents. This is a deliberate choice given this document's own provisional status (see the header note) — several **[DRAFT DECISION]** thresholds above (the `20`/`row_count / 20` continuous cutoff, the `90%` temporal-parse threshold, the `95%` accuracy exit criterion) are exactly the kind of number that should be reviewed, and likely adjusted, before code is generated against them. If you approve this document's decisions as-is, say so and the next step is generating the crate exactly as Documents 00A/00B/00C's scaffold scripts did.

---

## 7. Testing: the accuracy benchmark

Per §15.8's Verification clause ("Benchmark against manually classified datasets"):

### 7.1 Fixture corpus

**[DRAFT DECISION]** Two hand-labelled fixture datasets, matching the "small, realistic, deliberately varied" style of Document 00C's fixtures:

- `customers_ground_truth.csv` — columns: `id` (Identifier), `name` (Unclassified — free text), `signup_date` (Temporal), `tier` (Categorical — e.g. `"bronze"/"silver"/"gold"`), `lifetime_value` (Continuous).
- `sensor_readings_ground_truth.csv` — columns: `reading_id` (Identifier), `sensor_status` (Categorical — a boolean-like `"ok"/"fault"`), `temperature_celsius` (Continuous), `recorded_at` (Temporal).

Each fixture's expected `VariableRole` per column is recorded in a companion `ground_truth.json` (`{"customers_ground_truth.csv": {"id": "Identifier", ...}}`), read directly by `tests/accuracy.rs` rather than hand-duplicated as Rust literals — this avoids the ground truth and the test assertion silently drifting apart across edits, and mirrors why Document 00C's fixtures are files rather than inline byte literals.

### 7.2 `tests/accuracy.rs`

For each fixture: ingest it (reusing `rasica-ingestion`'s `csv::read`, since this crate has no ingestion logic of its own), run `infer`, and assert that the resulting `VariableRole` for every column matches `ground_truth.json`'s recorded expectation. Aggregate the pass rate across every column in every fixture and assert it meets the §1.2 threshold — with a large enough fixture corpus this would be a genuine percentage; with only two small fixtures as specified here, **[DRAFT DECISION]** the practical initial assertion is exact agreement on every single column (a 100% pass rate on a 9-column corpus), with the 95% threshold intended to apply once the corpus is grown large enough for a percentage to be statistically meaningful rather than an artifact of a tiny sample.

### 7.3 Unit tests

Each heuristic in §5 additionally gets isolated unit tests in its own module (`role.rs`, `distribution.rs`, etc.), following the same pattern as Document 00C's `typing.rs` — e.g. a property test asserting the Continuous/Categorical boundary in §5.3 is respected at both sides of the `max(20, row_count / 20)` threshold, and a determinism property test asserting `infer` run twice on the same `Dataset` produces `StructuralKnowledge` values with equal fingerprints (once `StructuralKnowledge` implements `DeterministicFingerprint` — **[DRAFT DECISION]**: not shown above, but should follow exactly the pattern Document 00B §4.6 established for `Dataset`, excluding `dataset_id` from the fingerprinted bytes for the same identity-vs-content reason).

---

## 8. Workspace integration

Following the same additive pattern as the Phase 2/Phase 3 scaffold scripts:

- New workspace member: `crates/rasica-structural-inference`.
- New `[workspace.dependencies]` entries: none required beyond what Phases 1–3 already added (`thiserror`, `proptest`, `rstest`, `criterion` are all already present; this crate needs no new external dependency, since all classification logic is pure Rust over types already defined in `rasica-dataset`).
- `tests/workspace_smoke` extension: one new smoke test asserting `StructuralKnowledge` composes with `rasica_core::prelude::Immutable`, matching Documents 00A/00B/00C's own smoke-test convention exactly.

---

## 9. Exit criteria checklist (§15.8, expanded per §1.2)

- [ ] Every `VariableRole` variant (§4.1) is reachable by at least one fixture column in §7.1's corpus.
- [ ] `tests/accuracy.rs` passes at the threshold defined in §1.2.
- [ ] `infer` is total (never panics) on every fixture, including a zero-column-impossible/zero-row `Dataset` (returns `InferenceError::EmptyDataset`, not a panic).
- [ ] `StructuralKnowledge`, `DistributionSummary`, and `CategorySummary` are all `Tier 1 — Immutable` per §6.2A, verified by the same `assert_immutable::<T>()` pattern the workspace smoke test already uses.
- [ ] Determinism: `infer` run twice on a byte-identical `Dataset` (constructed independently, e.g. once from CSV and once from JSON per Document 00C's own round-trip pattern) produces `StructuralKnowledge` with equal `DeterministicFingerprint` output.
- [ ] `#![forbid(unsafe_code)]` present; `cargo clippy --workspace --all-targets -- -D warnings`, `cargo fmt --all -- --check`, `cargo deny check` all pass, matching every prior phase's bar.

---

## 10. Summary of every [DRAFT DECISION] in this document, for review

1. §1.2 — 95% column-classification accuracy, zero identifier false positives, as the concrete exit-criterion metric.
2. §2.1 — `VariableRole::Unclassified` as an explicit catch-all variant.
3. §4.2 — sorting values before summation, for fingerprint determinism.
4. §4.3 — sorting categories by value rather than frequency, for the same reason.
5. §4.5 — `Option`-field representation of role-specific data, with an unenforced-by-the-type-system invariant.
6. §5.1 — the five-step precedence order, and specifically Temporal-before-Categorical.
7. §5.3 — the `max(20, row_count / 20)` continuous/categorical distinct-count threshold.
8. §5.5 — the three-format closed temporal format list, and the 90% parse-success threshold.
9. §5.7 — restricting relationship evidence to `Identifier`×`Identifier` pairs within a single `Dataset`, with `ValueSubset` as the only `RelationshipKind`.
10. §7.1/§7.2 — the specific fixture corpus and the "100% on this small corpus, 95% once grown" interim interpretation of the accuracy threshold.

Please review these ten points specifically. Once you're satisfied with them (or have told me how to change them), the next step is the same as Phases 1–3: I generate a scaffold script that creates `crates/rasica-structural-inference` in full, working Rust, exactly as specified above.
