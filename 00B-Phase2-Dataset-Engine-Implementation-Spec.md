# RASICA Implementation Specification

## Document 00B — Phase 2: Dataset Engine

**Version:** 1.0
**Status:** Draft — for implementation
**Conforms to:** RASICA Architecture Specification v2.1 ("the Architecture Spec")
**Position in documentation hierarchy:** Implements Appendix E item *04 Dataset Specification*. Builds directly on Document 00A (Phase 1 — Core Foundation), which this document treats as a hard prerequisite rather than re-deriving.

---

## Document Control

| Item | Value |
|---|---|
| Project | RASICA |
| Document | Phase 2 Implementation Specification — Dataset Engine |
| Roadmap Source | Architecture Spec §15.5 ("Phase 2 — Dataset Engine") |
| Depends On | Document 00A (`rasica-common`, `rasica-core`); Architecture Spec §6.4 (Dataset), §6.5 (Metadata), §6.2A (Mutability Tiers, Tier 1), §4.1 (Determinism), §9.1 (Dataset Engine layer), §14 (Engineering Principles), Appendix D (Repository Structure), Appendix G (Canonical Trait Signatures), Appendix H (NFR Baseline) |
| Produces Crates | `rasica-dataset` |
| Produces Infrastructure | Workspace member addition, benchmark harness activation (first real body for the Phase 1 `benchmark-regression` CI placeholder) |
| Consumed By | Phase 3 — Data Ingestion (§15.6), Phase 4 — Validation Engine (§15.7), Phase 5 — Structural Inference (§15.8), and every phase downstream of a constructed Dataset |
| Intended Audience | Implementers (human or AI) building on the Phase 1 foundation |
| Deviation Policy | Unchanged from Document 00A §Document Control: a deviation from a signature or invariant that also appears in the Architecture Spec is an architectural change requiring an ADR (§16.5/§14.18); a deviation confined to this document (e.g. an internal field name) may be made freely provided intent is preserved. |

---

## 1. Purpose and Scope

### 1.1 Purpose

This document is the authoritative, implementable specification for **Phase 2 — Dataset Engine**, the second entry in the RASICA development roadmap (Architecture Spec §15.5). It translates that phase's five-line deliverable list — Dataset, Row, Column, Schema, Metadata containers — into concrete Rust types built on the vocabulary Document 00A established (`Immutable`, `Identifiable`, `DeterministicFingerprint`), plus the crate-local error framework and test harness those types require.

Nothing in this document introduces new architecture. Every design decision below is a direct implementation of a rule already stated in the Architecture Spec or in Document 00A; each subsection cites the section it implements.

### 1.2 Scope

**In scope for Phase 2:**

- `rasica-dataset`: `Schema`, `Column`, `Value`, `Row`, `Dataset`, `DatasetBuilder`, `SourceMetadata`, and the `Metadata` container introduced by Architecture Spec §6.5.
- The crate-local `DatasetError` type, per the error contract established in Document 00A §4.4.
- Extension of the Phase 1 test harness: property tests specific to Dataset invariants, and an extension of `workspace_smoke` so it exercises a real Core Architectural Object rather than the hypothetical stand-in introduced in Document 00A §6.3.
- Giving the Phase 1 CI pipeline's `benchmark-regression` job (Document 00A §7.2, introduced as an explicit placeholder) its first real body, since Phase 2 is the first phase with anything to benchmark.

**Explicitly out of scope for Phase 2** (deferred to their own phase specifications):

- Parsing or reading any external format (CSV, Excel, JSON, SQL, Arrow, Parquet) — Phase 3, Data Ingestion (Architecture Spec §15.6). Phase 2 defines `SourceFormat` as a closed vocabulary of *which* formats a `Dataset` may claim provenance from; it implements no reader for any of them.
- Semantic or business-rule validation of any kind — Phase 4, Validation Engine (Architecture Spec §15.7, §9.2). §6.4 is explicit that the Dataset "is **not** responsible for validation," and §9.1 states the Dataset Engine "performs no validation."
- Datatype inference, identification of categorical/continuous/temporal variables, distribution characterisation, and relationship discovery — Phase 5, Structural Inference (Architecture Spec §15.8, §9.3, §6.7 Structural Knowledge). §1.4 below draws the exact line between what Phase 2's `Metadata` container computes now and what it leaves for Phase 5.
- Any chunked, paged, or out-of-core Dataset backing (Architecture Spec Appendix F, referenced by the §6.4 [2.1] editorial note). Phase 2 delivers a single, wholly in-memory backing only; §1.4 records this as a deliberate narrowing of an already-permitted implementation choice, not a violation of §6.4.
- Everything downstream of a constructed Dataset (Knowledge, Rules, Execution, Reporting, etc. — Architecture Spec §15.9–§15.23).

Per Architecture Spec §15.1, implementers shall not begin Phase 3 work (or any later phase's work) inside `rasica-dataset`.

### 1.3 Relationship to the Architecture Spec

| Phase 2 deliverable (§15.5) | Implemented in this document as |
|---|---|
| Dataset | §4.6 (`src/dataset.rs`) |
| Row | §4.4 (`src/row.rs`) |
| Column | §4.3 (`src/schema.rs`) |
| Schema | §4.3 (`src/schema.rs`) |
| Metadata containers | §4.5 (`src/metadata.rs`) |

Exit criteria in §15.5 ("every supported dataset structure can be represented without ambiguity") and its verification requirement ("demonstrate representation of datasets entirely in memory") are made concrete and checkable in §8 of this document.

### 1.4 Interpretation Notes

Two points in §15.5's four-word deliverable list ("Metadata containers") and in §6.4's permitted implementation latitude are underspecified enough at the phase-roadmap level that they must be resolved here, explicitly, before any code is justified against them.

**[Note 1 — Metadata container scope.** Architecture Spec §6.5 defines Metadata's subject matter as datatype, nullability, uniqueness, cardinality, distribution, scale, and temporal properties, and states Metadata "is derived solely from the Dataset" and "becomes immutable after creation." Separately, §9.3 and §15.8 (Phase 5, Structural Inference) assign *distribution* and *temporal variable identification* to a later phase, and §6.7 gives that later phase's output a distinct object (Structural Knowledge) from Metadata. Read together, this places Metadata's fields into two groups:

- **Structural facts, computable now, deterministically, by inspection alone:** a column's declared type, whether any value in it is null, whether all its values are distinct, and its distinct-value count. None of these require statistical or semantic interpretation; they are exact properties of the data already sitting in a constructed `Dataset`.
- **Interpretive facts, not computable without inference logic that does not exist until Phase 5:** distribution shape, unit/scale, and temporal semantics (e.g. "this integer column is actually a Unix timestamp").

Phase 2 therefore delivers the `Metadata` **container** — its full shape, per §6.5 — with the first group populated at construction time and the second group present as `Option`-typed fields left `None`, to be populated by the Structural Inference Engine (Phase 5) without changing `Metadata`'s public shape. This is the same pattern Document 00A used for the Mutability Tier traits: define the vocabulary a later phase needs before that phase exists, rather than let it invent its own.

**[Note 2 — Dataset backing.** The Architecture Spec's own [2.1] annotation on §6.4 states immutability is a *logical* guarantee and permits (but does not require) "a chunked/paged representation that materialises rows lazily from an external source" as a future, additive backing (Appendix F). Phase 2 implements only the simplest conforming backing — a single in-memory `Vec<Row>` — because Phase 2 has no external source to page from (that arrives in Phase 3) and Appendix H's in-memory baseline (10,000,000 rows × 200 columns) is stated as a target for the in-memory profile specifically. Choosing the paged backing now would be speculative generality against a requirement that does not yet exist. This narrowing is confined to this document (an implementation choice, not a loosening of §6.4's own logical-immutability contract) and is freely revisable per the Deviation Policy.

---

## 2. Engineering Baseline for This Phase

Everything in Document 00A §2 continues to apply unchanged. The following restates only what is newly load-bearing in Phase 2:

- **§4.1 Determinism / §6.2A Mutability Tiers:** `Dataset` and `Metadata` are both Tier 1 (Immutable) per §6.2A's explicit list. Both implement `rasica_core::mutability::Immutable` with no public method capable of mutating `self` post-construction — construction itself happens through a separate, non-`Immutable` builder type, exactly as Document 00A §5.3 anticipated ("None of these types exist yet in Phase 1; this trait is defined now so their specifications... have it available from their first line of code").
- **§14.9 Error Handling:** `rasica-dataset` defines one crate-local `DatasetError` implementing Document 00A's `RasicaError` contract (§4.4.1), following the worked example (`ConfigError`) verbatim in structure.
- **§14.5 / `unsafe`:** `rasica-dataset` sets `#![forbid(unsafe_code)]`, inherited from `[workspace.lints]` (Document 00A §3.2); no code in this document requires an exception.
- **§14.8 Public APIs:** `#![warn(missing_docs)]`, promoted to `deny` in CI, applies identically (Document 00A §7.2).
- **Appendix G Type Authority Policy:** `rasica-dataset` is the first crate that implements Document 00A's traits on a real type rather than a hypothetical one. Every `impl` below is checked against Document 00A §5's trait documentation, not re-derived.

---

## 3. Repository & Workspace Layout Update

### 3.1 Directory Structure (Phase 2 additions)

This is additive to Document 00A §3.1. No previously created path is renamed or moved.

```text
rasica/
├── crates/
│   ├── rasica-common/                # unchanged, Phase 1
│   ├── rasica-core/                  # unchanged, Phase 1
│   └── rasica-dataset/               # new
│       ├── Cargo.toml
│       ├── benches/
│       │   └── dataset_construction.rs
│       └── src/
│           ├── lib.rs
│           ├── error.rs
│           ├── schema.rs
│           ├── value.rs
│           ├── row.rs
│           ├── source.rs
│           ├── metadata.rs
│           ├── dataset.rs
│           └── prelude.rs
├── tests/
│   └── workspace_smoke/
│       └── tests/
│           └── smoke.rs              # extended, not replaced (§5.2)
```

`domains/`, `datasets/`, and the remaining `crates/rasica-*` from Architecture Spec Appendix D remain out of scope, created by the phase specification that first needs them.

### 3.2 Workspace Root `Cargo.toml` — Diff

```toml
[workspace]
members = [
    "crates/rasica-common",
    "crates/rasica-core",
    "crates/rasica-dataset",          # new
    "tests/workspace_smoke",
]

[workspace.dependencies]
# ... Phase 1 entries unchanged ...

# --- benchmarking (§14.15; first real consumer, see §6 of this document) ---
criterion = { version = "0.5", features = ["html_reports"] }
```

`[workspace.lints]` (Document 00A §3.2), `rustfmt.toml`, `clippy.toml`, `deny.toml`, and `nextest.toml` are unchanged; `rasica-dataset` inherits them via `[lints] workspace = true` exactly as the Phase 1 crates do.

---

## 4. Crate: `rasica-dataset`

### 4.1 Responsibilities

`rasica-dataset` owns the one Core Architectural Object Phase 2 is responsible for (`Dataset`, Architecture Spec §6.4) and its two direct supporting objects (`Schema`/`Column` as the Dataset's internal structure, and `Metadata`, Architecture Spec §6.5, as a distinct Tier 1 object derived from it). It depends on `rasica-common` (for `Id<T>`, `RasicaError`) and `rasica-core` (for `Immutable`, `Identifiable`, `DeterministicFingerprint`), and on nothing else internal, preserving the acyclic dependency graph Document 00A §5.1 established.

`rasica-dataset` shall contain no format-reading code (Phase 3), no validation logic (Phase 4), and no statistical inference (Phase 5). It represents data; it does not interpret it.

### 4.2 `Cargo.toml`

```toml
[package]
name = "rasica-dataset"
description = "The immutable internal Dataset representation and its supporting Schema, Row, and Metadata types."
version.workspace = true
edition.workspace = true
rust-version.workspace = true
authors.workspace = true
license.workspace = true
repository.workspace = true
publish.workspace = true

[lints]
workspace = true

[dependencies]
rasica-common = { path = "../rasica-common" }
rasica-core = { path = "../rasica-core" }
thiserror = { workspace = true }

[dev-dependencies]
proptest = { workspace = true }
rstest = { workspace = true }
criterion = { workspace = true }

[[bench]]
name = "dataset_construction"
harness = false
```

### 4.3 Schema and Column — `src/schema.rs`

A `Schema` is the closed, ordered list of columns a `Dataset` conforms to. It exists so a `Row` can be a plain, homogeneous sequence of `Value`s (§4.4) rather than repeating column names and types on every row — Architecture Spec §6.4 lists "columns" as a Dataset responsibility distinct from "values," which this split makes literal.

```rust
//! The closed, ordered column list a `Dataset` conforms to
//! (Architecture Spec §6.4, "columns").

use std::collections::HashSet;

use thiserror::Error;

/// The declared type of every value in a [`Column`].
///
/// This is a closed, structural vocabulary — the exact type a value is
/// *represented as* — and carries no semantic interpretation. Whether an
/// `Integer` column is actually a categorical code, or a `Text` column is
/// actually a date, is a Structural Inference concern (Architecture Spec
/// §6.7, Phase 5), not a Schema concern.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ColumnType {
    /// A 64-bit signed integer value.
    Integer,
    /// A 64-bit floating-point value.
    Float,
    /// A boolean value.
    Boolean,
    /// A UTF-8 text value.
    Text,
}

/// One column's name and declared type.
///
/// `Column` does not carry a value; it describes a position in every
/// [`crate::row::Row`] belonging to a [`Schema`] that includes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Column {
    name: String,
    column_type: ColumnType,
}

impl Column {
    /// Declares a new column with the given name and type.
    #[must_use]
    pub fn new(name: impl Into<String>, column_type: ColumnType) -> Self {
        Self {
            name: name.into(),
            column_type,
        }
    }

    /// Returns the column's name.
    #[must_use]
    pub fn name(&self) -> &str {
        &self.name
    }

    /// Returns the column's declared type.
    #[must_use]
    pub const fn column_type(&self) -> ColumnType {
        self.column_type
    }
}

/// Errors that can occur while constructing a [`Schema`].
#[derive(Debug, Error, PartialEq, Eq)]
pub enum SchemaError {
    /// Two or more columns were declared with the same name.
    #[error("duplicate column name '{name}'")]
    DuplicateColumnName {
        /// The name that appeared more than once.
        name: String,
    },
    /// A schema with zero columns was constructed.
    ///
    /// A `Dataset` "represents rows, columns, [and] values" (Architecture
    /// Spec §6.4); a schema with no columns can represent no values, so it
    /// is rejected as a structural malformation rather than as a valid
    /// zero-column dataset.
    #[error("a schema must declare at least one column")]
    Empty,
}

/// The closed, ordered list of [`Column`]s every [`crate::row::Row`] in a
/// [`Dataset`](crate::dataset::Dataset) conforms to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Schema {
    columns: Vec<Column>,
}

impl Schema {
    /// Constructs a `Schema` from an ordered list of columns.
    ///
    /// # Errors
    ///
    /// Returns [`SchemaError::Empty`] if `columns` is empty, or
    /// [`SchemaError::DuplicateColumnName`] if any two columns share a name.
    pub fn new(columns: Vec<Column>) -> Result<Self, SchemaError> {
        if columns.is_empty() {
            return Err(SchemaError::Empty);
        }

        let mut seen = HashSet::with_capacity(columns.len());
        for column in &columns {
            if !seen.insert(column.name()) {
                return Err(SchemaError::DuplicateColumnName {
                    name: column.name().to_owned(),
                });
            }
        }

        Ok(Self { columns })
    }

    /// Returns the number of columns in this schema.
    #[must_use]
    pub fn arity(&self) -> usize {
        self.columns.len()
    }

    /// Returns the columns in declaration order.
    #[must_use]
    pub fn columns(&self) -> &[Column] {
        &self.columns
    }

    /// Returns the ordinal position of the column named `name`, if present.
    #[must_use]
    pub fn position_of(&self, name: &str) -> Option<usize> {
        self.columns.iter().position(|c| c.name() == name)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_empty_schema() {
        assert_eq!(Schema::new(vec![]), Err(SchemaError::Empty));
    }

    #[test]
    fn rejects_duplicate_column_names() {
        let result = Schema::new(vec![
            Column::new("a", ColumnType::Integer),
            Column::new("a", ColumnType::Text),
        ]);
        assert_eq!(
            result,
            Err(SchemaError::DuplicateColumnName { name: "a".into() })
        );
    }

    #[test]
    fn accepts_well_formed_schema() {
        let schema = Schema::new(vec![
            Column::new("id", ColumnType::Integer),
            Column::new("label", ColumnType::Text),
        ])
        .expect("two distinctly named columns is a well-formed schema");
        assert_eq!(schema.arity(), 2);
        assert_eq!(schema.position_of("label"), Some(1));
    }
}
```

### 4.4 Values and Rows — `src/value.rs`, `src/row.rs`

```rust
// src/value.rs
//! A single cell value, typed according to `ColumnType` (§4.3 of this
//! document).

use rasica_core::prelude::DeterministicFingerprint;

/// One value in one cell of a [`crate::row::Row`].
///
/// `Value::Null` is a distinct variant, not the absence of a `Value`,
/// because nullability itself is a fact `Metadata` (§4.5) records per
/// column — a `Row` must therefore be able to represent "this cell is
/// null" explicitly rather than by omission.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    /// No value is present.
    Null,
    /// A 64-bit signed integer.
    Integer(i64),
    /// A 64-bit floating-point number.
    ///
    /// Equality on this variant follows `PartialEq` on `f64`, including
    /// `NaN != NaN`; no domain semantics (e.g. "treat NaN as missing") are
    /// applied here (Architecture Spec §6.4: the Dataset is not responsible
    /// for semantic interpretation).
    Float(f64),
    /// A boolean.
    Boolean(bool),
    /// UTF-8 text.
    Text(String),
}

impl DeterministicFingerprint for Value {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        // Each variant is prefixed with a distinct tag byte so that, e.g.,
        // `Integer(0)` and `Boolean(false)` — which could otherwise collide
        // on their payload bytes alone — fingerprint differently. This is
        // the same "injective with respect to logical equality" contract
        // Document 00A §5.4 places on every `DeterministicFingerprint`
        // implementation.
        match self {
            Self::Null => vec![0u8],
            Self::Integer(v) => [&[1u8][..], &v.to_le_bytes()].concat(),
            Self::Float(v) => [&[2u8][..], &v.to_le_bytes()].concat(),
            Self::Boolean(v) => vec![3u8, u8::from(*v)],
            Self::Text(v) => [&[4u8][..], v.as_bytes()].concat(),
        }
    }
}
```

```rust
// src/row.rs
//! A single row: one [`Value`] per column of the [`crate::schema::Schema`]
//! it was constructed against.

use rasica_core::prelude::DeterministicFingerprint;

use crate::value::Value;

/// One row of a [`Dataset`](crate::dataset::Dataset).
///
/// A `Row` does not carry its own copy of the [`crate::schema::Schema`] it
/// belongs to (that would duplicate the schema once per row, contradicting
/// Architecture Spec §6.4's "columns" being a Dataset-level, not row-level,
/// responsibility). Arity is checked once, at
/// [`DatasetBuilder::push_row`](crate::dataset::DatasetBuilder::push_row)
/// time, against the `Dataset`'s single `Schema`.
#[derive(Debug, Clone, PartialEq)]
pub struct Row(Vec<Value>);

impl Row {
    /// Constructs a row from an ordered list of values.
    ///
    /// This constructor performs no arity or type checking against any
    /// schema; that check is the responsibility of
    /// [`DatasetBuilder::push_row`](crate::dataset::DatasetBuilder::push_row),
    /// the single point at which a `Row` and a `Schema` are brought
    /// together.
    #[must_use]
    pub fn new(values: Vec<Value>) -> Self {
        Self(values)
    }

    /// Returns the number of values in this row.
    #[must_use]
    pub fn arity(&self) -> usize {
        self.0.len()
    }

    /// Returns the value at `position`, if present.
    #[must_use]
    pub fn get(&self, position: usize) -> Option<&Value> {
        self.0.get(position)
    }

    /// Returns the row's values in order.
    #[must_use]
    pub fn values(&self) -> &[Value] {
        &self.0
    }
}

impl DeterministicFingerprint for Row {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        self.0
            .iter()
            .flat_map(DeterministicFingerprint::fingerprint_bytes)
            .collect()
    }
}
```

### 4.5 Source Metadata and the `Metadata` Container — `src/source.rs`, `src/metadata.rs`

`SourceMetadata` implements the "source metadata" item in §6.4's Dataset responsibilities list. `Metadata` implements the distinct §6.5 object, scoped per §1.4 Note 1 above.

```rust
// src/source.rs
//! Provenance information about where a Dataset's content came from
//! (Architecture Spec §6.4, "source metadata").

/// The external format a `Dataset`'s content was constructed from, or
/// [`SourceFormat::InMemory`] if it was constructed directly.
///
/// This is a closed enumeration matching Architecture Spec §6.4's example
/// list of supported external sources exactly. Phase 2 defines the
/// vocabulary; Phase 3 (Data Ingestion, §15.6) implements a reader for each
/// variant other than `InMemory`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SourceFormat {
    /// Comma-separated values.
    Csv,
    /// A Microsoft Excel workbook.
    Excel,
    /// JSON.
    Json,
    /// A SQL query result set.
    Sql,
    /// Apache Arrow.
    Arrow,
    /// Apache Parquet.
    Parquet,
    /// Constructed directly in-process, with no external source.
    InMemory,
}

/// Provenance information attached to a [`Dataset`](crate::dataset::Dataset).
///
/// `SourceMetadata` is deliberately excluded from `Dataset`'s
/// `DeterministicFingerprint` (§4.6): two datasets with byte-identical
/// schema and rows are the same *content* regardless of which format they
/// happened to be read from, and a Tier 3 cache keyed on that fingerprint
/// (Architecture Spec §6.2A) should treat them as the same cache key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceMetadata {
    format: SourceFormat,
    origin: String,
}

impl SourceMetadata {
    /// Records that a `Dataset` came from `format`, originating at
    /// `origin` (a file path, URI, connection descriptor, or `"in-memory"`
    /// — the exact convention is owned by whichever Phase 3 reader
    /// populates it; Phase 2 imposes no structure on the string itself).
    #[must_use]
    pub fn new(format: SourceFormat, origin: impl Into<String>) -> Self {
        Self {
            format,
            origin: origin.into(),
        }
    }

    /// Returns the source format.
    #[must_use]
    pub const fn format(&self) -> SourceFormat {
        self.format
    }

    /// Returns the origin descriptor.
    #[must_use]
    pub fn origin(&self) -> &str {
        &self.origin
    }
}
```

```rust
// src/metadata.rs
//! The Metadata Core Architectural Object (Architecture Spec §6.5): the
//! structural description of a Dataset, derived solely from it.

use rasica_core::prelude::Immutable;

use crate::dataset::Dataset;

/// The per-column portion of [`Metadata`].
///
/// `distribution`, `scale`, and `temporal_properties` are `None` in every
/// `Metadata` produced by Phase 2 (see this document's §1.4 Note 1); they
/// exist on this type now so Phase 5 (Structural Inference) populates them
/// without changing `ColumnMetadata`'s public shape.
#[derive(Debug, Clone, PartialEq)]
pub struct ColumnMetadata {
    nullable: bool,
    unique: bool,
    distinct_count: u64,
    /// Populated by Phase 5. Always `None` in Phase 2.
    distribution: Option<()>,
    /// Populated by a future phase (not yet assigned a phase number in the
    /// roadmap). Always `None` in Phase 2.
    scale: Option<()>,
    /// Populated by a future phase (not yet assigned a phase number in the
    /// roadmap). Always `None` in Phase 2.
    temporal_properties: Option<()>,
}

impl ColumnMetadata {
    /// Returns whether the column contains at least one [`crate::value::Value::Null`].
    #[must_use]
    pub const fn nullable(&self) -> bool {
        self.nullable
    }

    /// Returns whether every non-null value in the column is distinct.
    #[must_use]
    pub const fn unique(&self) -> bool {
        self.unique
    }

    /// Returns the number of distinct non-null values in the column.
    #[must_use]
    pub const fn distinct_count(&self) -> u64 {
        self.distinct_count
    }
}

/// The structural description of a [`Dataset`] (Architecture Spec §6.5).
///
/// `Metadata` is Tier 1 (Immutable, §6.2A): once derived, it is never
/// updated in place. A later phase that learns more about a Dataset's
/// structure (e.g. Phase 5 filling in `ColumnMetadata::distribution`)
/// constructs a new `Metadata` value; it does not mutate this one, per
/// §6.2A's "any change requires constructing a new object with a new
/// identity."
#[derive(Debug, Clone, PartialEq)]
pub struct Metadata {
    columns: Vec<ColumnMetadata>,
}

impl Immutable for Metadata {}

impl Metadata {
    /// Derives `Metadata` from `dataset` by inspection alone (§6.5:
    /// "derived solely from the Dataset").
    ///
    /// This performs a single pass over every row for every column;
    /// callers processing very wide or very tall datasets against
    /// Appendix H's baseline should treat this as an O(rows × columns)
    /// operation with no shortcut in Phase 2 (Phase 5's inference logic is
    /// the appropriate place to introduce sampling or incremental
    /// strategies, should that become necessary).
    #[must_use]
    pub fn derive(dataset: &Dataset) -> Self {
        let columns = (0..dataset.schema().arity())
            .map(|position| {
                let mut seen = std::collections::HashSet::new();
                let mut nullable = false;

                for row in dataset.rows() {
                    match row.get(position) {
                        Some(crate::value::Value::Null) | None => nullable = true,
                        Some(other) => {
                            // `Value` is not `Eq`/`Hash` (it wraps `f64`),
                            // so distinctness is tracked via each value's
                            // deterministic fingerprint bytes rather than
                            // via `HashSet<Value>` directly. This reuses
                            // the same fingerprinting contract Document 00A
                            // §5.4 established, rather than inventing a
                            // second notion of "distinct."
                            use rasica_core::prelude::DeterministicFingerprint;
                            seen.insert(other.fingerprint());
                        }
                    }
                }

                let distinct_count = seen.len() as u64;
                let non_null_count = dataset
                    .rows()
                    .iter()
                    .filter(|r| !matches!(r.get(position), Some(crate::value::Value::Null) | None))
                    .count() as u64;

                ColumnMetadata {
                    nullable,
                    unique: distinct_count == non_null_count,
                    distinct_count,
                    distribution: None,
                    scale: None,
                    temporal_properties: None,
                }
            })
            .collect();

        Self { columns }
    }

    /// Returns per-column metadata, in schema column order.
    #[must_use]
    pub fn columns(&self) -> &[ColumnMetadata] {
        &self.columns
    }
}
```

### 4.6 Dataset and `DatasetBuilder` — `src/dataset.rs`

```rust
//! The Dataset Core Architectural Object (Architecture Spec §6.4): the
//! immutable internal representation of ingested data.

use rasica_common::Id;
use rasica_core::prelude::{DeterministicFingerprint, Identifiable, Immutable};

use crate::{
    error::DatasetError,
    row::Row,
    schema::Schema,
    source::SourceMetadata,
};

/// Marker type for [`Id<DatasetMarker>`], per Document 00A §4.3.1's phantom-typed
/// identifier pattern.
pub struct DatasetMarker;

/// The immutable internal representation of ingested data (Architecture
/// Spec §6.4).
///
/// A `Dataset` is constructed exclusively via [`DatasetBuilder`]; once
/// built, it exposes no method capable of mutating its rows or schema,
/// satisfying its Tier 1 (Immutable, §6.2A) classification.
#[derive(Debug, Clone)]
pub struct Dataset {
    id: Id<DatasetMarker>,
    schema: Schema,
    rows: Vec<Row>,
    source: SourceMetadata,
}

impl Immutable for Dataset {}

impl Identifiable for Dataset {
    type Marker = DatasetMarker;

    fn id(&self) -> Id<Self::Marker> {
        self.id
    }
}

impl DeterministicFingerprint for Dataset {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        // Excludes `id` (identity, not content — see Document 00A §5.4's
        // `ExampleImmutableObject`) and `source` (provenance, not content
        // — see §4.5 of this document). Two datasets with identical schema
        // and rows fingerprint identically regardless of identity or
        // origin, so a Tier 3 cache keyed on this fingerprint (§6.2A) is
        // correctly shared between them.
        let mut bytes = self.schema.fingerprint_bytes();
        bytes.extend(
            self.rows
                .iter()
                .flat_map(DeterministicFingerprint::fingerprint_bytes),
        );
        bytes
    }
}

impl Dataset {
    /// Returns the dataset's schema.
    #[must_use]
    pub const fn schema(&self) -> &Schema {
        &self.schema
    }

    /// Returns the dataset's rows, in insertion order.
    #[must_use]
    pub fn rows(&self) -> &[Row] {
        &self.rows
    }

    /// Returns the dataset's source provenance.
    #[must_use]
    pub const fn source(&self) -> &SourceMetadata {
        &self.source
    }

    /// Returns the number of rows in the dataset.
    #[must_use]
    pub fn row_count(&self) -> usize {
        self.rows.len()
    }
}

/// Constructs a [`Dataset`] one row at a time, enforcing structural
/// well-formedness (row arity and per-value type agreement with the
/// [`Schema`]) as each row is added.
///
/// This is a structural check, not validation in the Architecture Spec
/// §6.4/§9.1 sense: it enforces that a `Dataset` can only ever represent
/// rows that are *well-formed with respect to its own declared schema* —
/// the same kind of invariant [`Schema::new`] enforces on column names.
/// It makes no judgement about whether the *content* of a well-formed row
/// is meaningful, permitted, or expected; that judgement belongs to the
/// Validation Engine (Phase 4, Architecture Spec §9.2).
///
/// `DatasetBuilder` itself implements none of `rasica-core`'s Tier
/// traits: it is not a Core Architectural Object, only the mutable scratch
/// space used to construct one. Architecture Spec §6.2A's tiers apply to
/// `Dataset` from the moment [`DatasetBuilder::build`] returns it, not
/// before.
#[derive(Debug)]
pub struct DatasetBuilder {
    schema: Schema,
    rows: Vec<Row>,
}

impl DatasetBuilder {
    /// Starts building a dataset conforming to `schema`.
    #[must_use]
    pub fn new(schema: Schema) -> Self {
        Self {
            schema,
            rows: Vec::new(),
        }
    }

    /// Appends `row`, after checking its arity and per-value types agree
    /// with the schema.
    ///
    /// # Errors
    ///
    /// Returns [`DatasetError::RowArityMismatch`] if `row`'s length does
    /// not equal [`Schema::arity`], or [`DatasetError::RowTypeMismatch`]
    /// if any non-null value's type disagrees with its column's declared
    /// [`crate::schema::ColumnType`].
    pub fn push_row(&mut self, row: Row) -> Result<&mut Self, DatasetError> {
        if row.arity() != self.schema.arity() {
            return Err(DatasetError::RowArityMismatch {
                expected: self.schema.arity(),
                actual: row.arity(),
            });
        }

        for (position, column) in self.schema.columns().iter().enumerate() {
            let value = row
                .get(position)
                .expect("arity was checked equal to schema.columns().len() above");
            if !crate::value_matches_type(value, column.column_type()) {
                return Err(DatasetError::RowTypeMismatch {
                    column: column.name().to_owned(),
                    position,
                });
            }
        }

        self.rows.push(row);
        Ok(self)
    }

    /// Freezes the builder into an immutable [`Dataset`], attaching
    /// `source` as its provenance.
    #[must_use]
    pub fn build(self, source: SourceMetadata) -> Dataset {
        Dataset {
            id: Id::new(),
            schema: self.schema,
            rows: self.rows,
            source,
        }
    }
}
```

The type-agreement helper referenced above lives at the crate root so both `dataset.rs` and any future Phase 3 reader can reuse it without a circular `mod` reference:

```rust
// src/lib.rs (excerpt — full lib.rs in §4.8)
use crate::{schema::ColumnType, value::Value};

/// Returns whether `value` agrees with `column_type`, treating
/// [`Value::Null`] as agreeing with every type (nullability is a
/// per-column fact recorded by [`crate::metadata::Metadata`], not a
/// per-value type violation).
pub(crate) fn value_matches_type(value: &Value, column_type: ColumnType) -> bool {
    matches!(
        (value, column_type),
        (Value::Null, _)
            | (Value::Integer(_), ColumnType::Integer)
            | (Value::Float(_), ColumnType::Float)
            | (Value::Boolean(_), ColumnType::Boolean)
            | (Value::Text(_), ColumnType::Text)
    )
}
```

### 4.7 Error Framework — `src/error.rs`

Follows Document 00A §4.4.2's worked example exactly.

```rust
//! Errors produced while constructing a `Dataset` (Architecture Spec
//! §14.9; Document 00A §4.4).

use thiserror::Error;

use rasica_common::error::{ErrorCode, ErrorSeverity, RasicaError};

/// Errors from [`crate::dataset::DatasetBuilder`].
#[derive(Debug, Error, PartialEq, Eq)]
pub enum DatasetError {
    /// A row was pushed whose length did not match the schema's arity.
    #[error("row has {actual} values but the schema declares {expected} columns")]
    RowArityMismatch {
        /// The schema's declared arity.
        expected: usize,
        /// The row's actual length.
        actual: usize,
    },

    /// A row was pushed with a value whose type disagreed with its
    /// column's declared type.
    #[error("value at column '{column}' (position {position}) does not match its declared type")]
    RowTypeMismatch {
        /// The offending column's name.
        column: String,
        /// The offending column's ordinal position.
        position: usize,
    },
}

impl RasicaError for DatasetError {
    fn error_code(&self) -> ErrorCode {
        match self {
            Self::RowArityMismatch { .. } => ErrorCode("dataset::row_arity_mismatch"),
            Self::RowTypeMismatch { .. } => ErrorCode("dataset::row_type_mismatch"),
        }
    }

    fn severity(&self) -> ErrorSeverity {
        // Both conditions are caught before `DatasetBuilder::build` is
        // called, i.e. before any Tier 1 `Dataset` exists — no
        // already-constructed Core Architectural Object is put at risk,
        // matching `ConfigError`'s rationale in Document 00A §4.4.2.
        ErrorSeverity::Recoverable
    }
}
```

### 4.8 `src/lib.rs` and `src/prelude.rs`

```rust
// src/lib.rs
//! `rasica-dataset`: the immutable internal Dataset representation
//! (Architecture Spec §6.4) and its supporting Schema, Row, Value, Source,
//! and Metadata types.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod dataset;
pub mod error;
pub mod metadata;
pub mod prelude;
pub mod row;
pub mod schema;
pub mod source;
pub mod value;

use crate::{schema::ColumnType, value::Value};

pub(crate) fn value_matches_type(value: &Value, column_type: ColumnType) -> bool {
    matches!(
        (value, column_type),
        (Value::Null, _)
            | (Value::Integer(_), ColumnType::Integer)
            | (Value::Float(_), ColumnType::Float)
            | (Value::Boolean(_), ColumnType::Boolean)
            | (Value::Text(_), ColumnType::Text)
    )
}
```

```rust
// src/prelude.rs
//! Convenience re-export of the types most consumers of `rasica-dataset`
//! need, following the same convention as `rasica_core::prelude`
//! (Document 00A §5.6).

pub use crate::{
    dataset::{Dataset, DatasetBuilder, DatasetMarker},
    error::DatasetError,
    metadata::{ColumnMetadata, Metadata},
    row::Row,
    schema::{Column, ColumnType, Schema, SchemaError},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};
```

---

## 5. Testing Framework Extension

### 5.1 Policy

Document 00A §6.1's harness (inline unit tests, `proptest`, `workspace_smoke`) is reused without modification to its mechanics. Phase 2 adds test *content* specific to Dataset invariants and, per §1.2, gives the Phase 1 benchmark placeholder its first real body.

### 5.2 `workspace_smoke` — Extension, Not Replacement

Document 00A §6.3 closed with a hypothetical `ExampleImmutableObject` "existing only to prove the Phase 1 vocabulary is sufficient to build one." Phase 2 adds a second test module proving the same vocabulary composes on the real object it was built for:

```rust
// tests/workspace_smoke/tests/smoke.rs (addition; the Phase 1 module above
// this point is unchanged)

mod dataset_composes_with_core_vocabulary {
    use rasica_core::prelude::*;
    use rasica_dataset::prelude::*;

    fn sample_dataset() -> Dataset {
        let schema = Schema::new(vec![
            Column::new("id", ColumnType::Integer),
            Column::new("label", ColumnType::Text),
        ])
        .expect("well-formed schema in test fixture");

        let mut builder = DatasetBuilder::new(schema);
        builder
            .push_row(Row::new(vec![Value::Integer(1), Value::Text("a".into())]))
            .expect("well-formed row in test fixture");

        builder.build(SourceMetadata::new(SourceFormat::InMemory, "test-fixture"))
    }

    #[test]
    fn dataset_is_identifiable_and_fingerprintable() {
        let dataset = sample_dataset();
        let _ = dataset.id();
        let _ = dataset.fingerprint();
    }

    #[test]
    fn metadata_derives_from_dataset_without_mutating_it() {
        let dataset = sample_dataset();
        let metadata = Metadata::derive(&dataset);
        assert_eq!(metadata.columns().len(), dataset.schema().arity());
        // Deriving Metadata does not require, and cannot obtain, `&mut
        // Dataset` — this is checked by the type signature of
        // `Metadata::derive(&Dataset)` compiling at all, not by an
        // assertion here.
    }
}
```

Add `rasica-dataset = { path = "../../crates/rasica-dataset" }` to `tests/workspace_smoke/Cargo.toml`'s `[dependencies]`.

### 5.3 Property Tests (in `rasica-dataset`, per-module)

In addition to the unit tests embedded in §4.3–§4.7:

```rust
// src/dataset.rs, #[cfg(test)] mod tests (excerpt)
proptest::proptest! {
    #[test]
    fn datasets_with_equal_content_fingerprint_equally_regardless_of_identity(
        a in 0i64..1000, b in 0i64..1000
    ) {
        let build = |v: i64| {
            let schema = Schema::new(vec![Column::new("n", ColumnType::Integer)]).unwrap();
            let mut builder = DatasetBuilder::new(schema);
            builder.push_row(Row::new(vec![Value::Integer(v)])).unwrap();
            builder.build(SourceMetadata::new(SourceFormat::InMemory, "prop-test"))
        };

        if a == b {
            proptest::prop_assert_eq!(build(a).fingerprint(), build(b).fingerprint());
        } else {
            proptest::prop_assert_ne!(build(a).fingerprint(), build(b).fingerprint());
        }
    }
}
```

```rust
// src/metadata.rs, #[cfg(test)] mod tests (excerpt)
#[test]
fn distinct_count_matches_actual_distinct_non_null_values() {
    let schema = Schema::new(vec![Column::new("n", ColumnType::Integer)]).unwrap();
    let mut builder = DatasetBuilder::new(schema);
    for v in [Value::Integer(1), Value::Integer(1), Value::Null, Value::Integer(2)] {
        builder.push_row(Row::new(vec![v])).unwrap();
    }
    let dataset = builder.build(SourceMetadata::new(SourceFormat::InMemory, "test"));

    let metadata = Metadata::derive(&dataset);
    let column = &metadata.columns()[0];
    assert!(column.nullable());
    assert_eq!(column.distinct_count(), 2);
    assert!(!column.unique()); // "1" appears twice
}
```

### 5.4 Benchmark Harness — `benches/dataset_construction.rs`

Document 00A §7.2 introduced `benchmark-regression` as an explicit no-op, "so the pipeline's job list already matches the full required set and no later phase needs to restructure `ci.yml`... only to give it a real body." Phase 2 is that later phase.

Appendix H's in-memory baseline (10,000,000 rows × 200 columns) is a target for a defined reference machine that the Benchmarking Specification (Appendix E item 24) has not yet been written to specify. Rather than assert against an undefined reference machine, Phase 2's benchmark exercises a smaller, fixed, documented shape and records its result as a regression baseline via `criterion`; scaling this benchmark to Appendix H's full target, on a defined reference machine, is Appendix E item 24's responsibility, not this document's.

```rust
//! Benchmarks `Dataset` construction and fingerprinting at a fixed,
//! documented shape (1,000 rows × 10 columns). This is a regression
//! baseline, not a validation of Appendix H's full target — see §5.4 of
//! the Phase 2 Implementation Specification.

use criterion::{black_box, criterion_group, criterion_main, Criterion};
use rasica_core::prelude::DeterministicFingerprint;
use rasica_dataset::prelude::*;

const ROWS: usize = 1_000;
const COLUMNS: usize = 10;

fn build_dataset() -> Dataset {
    let columns = (0..COLUMNS)
        .map(|i| Column::new(format!("c{i}"), ColumnType::Integer))
        .collect();
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
```

---

## 6. Build Pipeline (CI) Updates

### 6.1 Workspace Membership

`.github/workflows/ci.yml` requires no structural change: every job in Document 00A §7.2 already runs `--workspace`, so `rasica-dataset`'s addition to `[workspace] members` (§3.2) is picked up automatically by `fmt`, `clippy`, `test`, `doc`, `audit`, and `msrv`.

### 6.2 `benchmark-regression` — First Real Body

```yaml
  benchmark-regression:
    name: Benchmark Regression Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
      # Phase 2 gives this job its first real body (Document 00A §7.2's
      # placeholder). It runs the fixed-shape benchmark defined in §5.4 of
      # the Phase 2 Implementation Specification and stores the result as
      # this job's artifact; comparing successive runs for regression
      # (rather than only recording them) is deferred to the Benchmarking
      # Specification (Appendix E item 24), which is expected to define the
      # reference machine and comparison policy this job will enforce.
      - run: cargo bench --workspace
      - uses: actions/upload-artifact@v4
        with:
          name: criterion-results
          path: target/criterion
```

### 6.3 `deny.toml`

No change: `criterion` is a `dev-dependency` only (§4.2), so it does not ship in any release artifact and introduces no new licence or advisory surface beyond what `cargo deny check` already screens.

---

## 7. Documentation Framework

Unchanged from Document 00A §8: `#![warn(missing_docs)]` promoted to `deny` in CI applies identically to `rasica-dataset`; every public item in §4 above carries a doc comment stating its purpose and, where non-obvious, the Architecture Spec section it implements.

---

## 8. Exit Criteria (Checkable)

Architecture Spec §15.5 states Phase 2's exit criterion and verification requirement in prose. This section makes each one a specific, automatable check.

| §15.5 Requirement | Concrete Check |
|---|---|
| "Every supported dataset structure can be represented without ambiguity." | `Schema::new` (§4.3) rejects the two ways a schema could be ambiguous — no columns, duplicate names — at construction time, not later; `DatasetBuilder::push_row` (§4.6) rejects every row that would make a `Dataset` internally inconsistent with its own schema (arity or type mismatch). No `Dataset` value can exist in an ambiguous state. |
| "Demonstrate representation of datasets entirely in memory." | `benches/dataset_construction.rs` (§5.4) constructs and fingerprints a `Dataset` wholly in memory, with no I/O of any kind, and runs in CI (§6.2). |

Additional Phase-2-specific verification, implied by §6.2A and §6.5 being load-bearing for later phases:

| Requirement | Concrete Check |
|---|---|
| `Dataset` and `Metadata` are Tier 1 | `rasica_dataset::dataset::Dataset` and `rasica_dataset::metadata::Metadata` both implement `rasica_core::mutability::Immutable`; neither exposes a `&mut self` method in its public API (checked by review, per Document 00A §5.3's documented limitation of the trait). |
| Fingerprinting excludes identity and provenance | `datasets_with_equal_content_fingerprint_equally_regardless_of_identity` (§5.3) passes: two `Dataset`s built with equal schema and rows but distinct `Id`s and equal `SourceMetadata` fingerprint identically; distinct content fingerprints differently. |
| `Metadata` is derived solely from the `Dataset` | `Metadata::derive`'s only parameter is `&Dataset` (§4.5); it takes no other input. |
| No crate depends on an unimplemented crate | `cargo metadata` shows `rasica-common`, `rasica-core`, `rasica-dataset`, and `workspace-smoke` as the only workspace members; `rasica-dataset`'s only internal path dependencies are `rasica-common` and `rasica-core` (§4.2). |
| `unsafe` is absent | `#![forbid(unsafe_code)]` present in `rasica-dataset`'s crate root (§4.8). |

Phase 2 is complete when every row above is true on a single commit of `main`, in addition to every Phase 1 exit criterion (Document 00A §9) continuing to hold.

---

## 9. Traceability Matrix

| This Document | Architecture Spec / Document 00A Source |
|---|---|
| §1.4 Note 1 (Metadata scope) | §6.5, §6.7, §9.3, §15.8 |
| §1.4 Note 2 (Dataset backing) | §6.4 [2.1] editorial note, Appendix F |
| §2 (Engineering Baseline) | Document 00A §2; §4.1, §6.2A |
| §3 (Repository & Workspace) | §15.5, Appendix D |
| §4.3 (Schema, Column) | §6.4 ("columns") |
| §4.4 (Value, Row) | §6.4 ("values", "rows") |
| §4.5 (SourceMetadata, Metadata) | §6.4 ("source metadata"), §6.5 |
| §4.6 (Dataset, DatasetBuilder) | §6.4, §6.2A (Tier 1) |
| §4.7 (DatasetError) | Document 00A §4.4 (Error Framework contract) |
| §5 (Testing Framework Extension) | Document 00A §6; §14.13 |
| §5.4 (Benchmark) | §14.15, Appendix H |
| §6 (CI Updates) | Document 00A §7; §14.14 |
| §8 (Exit Criteria) | §15.5 |

---

## 10. Non-Goals and Forward Pointers

- **Reading any external format** (CSV, Excel, JSON, SQL, Arrow, Parquet) is Phase 3's responsibility (Architecture Spec §15.6, Appendix E item 04's ingestion counterpart). Phase 3 will implement one reader per `SourceFormat` variant defined in §4.5, each producing a `Dataset` via the same `DatasetBuilder` defined here — no new construction API is expected.
- **Validation** — nullability rules, referential checks, business-rule enforcement — is Phase 4's responsibility (Architecture Spec §15.7, §9.2, §6.6 Validation Report). `DatasetBuilder`'s structural checks (§4.6) are a distinct, narrower concern and shall not be extended with semantic rules; doing so would violate §6.4's "not responsible for validation."
- **`ColumnMetadata::distribution`, `::scale`, and `::temporal_properties`** remain `None` until Phase 5 (Structural Inference, §15.8) and, for scale/temporal properties specifically, until whichever future phase the roadmap assigns them to — the Architecture Spec does not currently name one explicitly beyond §6.5's definition. This document's `ColumnMetadata` shape (§4.5) is fixed now so that phase does not need to redesign the type, only populate it.
- **Chunked, paged, or out-of-core `Dataset` backings** (Architecture Spec Appendix F) are not implemented. `Dataset`'s public API (§4.6) exposes no method whose behaviour depends on the backing being a `Vec<Row>` specifically, so a future ADR (per §16.5/§14.18) could introduce an alternative backing behind the same API without breaking this phase's consumers — but no such ADR exists yet, and none is anticipated before Appendix H's in-memory baseline is actually exceeded by a real workload.
- **Benchmark comparison against Appendix H's full baseline** (10,000,000 rows × 200 columns, on a defined reference machine) awaits the Benchmarking Specification (Appendix E item 24). Phase 2's benchmark (§5.4) is a regression baseline at a smaller, fixed shape, not a validation of the full target.

---

*End of Document 00B. The next document in sequence is the Phase 3 Implementation Specification — Data Ingestion, which is the first consumer of `rasica_dataset::dataset::DatasetBuilder` and `rasica_dataset::source::SourceFormat` for a real external reader (Architecture Spec §15.6).*
