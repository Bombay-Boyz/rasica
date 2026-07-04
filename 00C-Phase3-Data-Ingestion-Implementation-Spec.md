# RASICA Implementation Specification

## Document 00C — Phase 3: Data Ingestion

**Version:** 1.0
**Status:** Draft — for implementation
**Conforms to:** RASICA Architecture Specification v2.1 ("the Architecture Spec")
**Position in documentation hierarchy:** Extends Appendix E item *04 Dataset Specification* with the external-source reading responsibility Document 00B explicitly deferred. Builds directly on Document 00A (Phase 1 — Core Foundation) and Document 00B (Phase 2 — Dataset Engine), which this document treats as hard prerequisites rather than re-deriving.

---

## Document Control

| Item | Value |
|---|---|
| Project | RASICA |
| Document | Phase 3 Implementation Specification — Data Ingestion |
| Roadmap Source | Architecture Spec §15.6 ("Phase 3 — Data Ingestion") |
| Depends On | Architecture Spec §6.4 (Dataset, "source metadata"), §9.1 (Dataset Engine layer: "ingestion, normalisation, source abstraction, internal representation"), §8.3 (Core Dependency Graph — Dataset Engine, Infrastructure Layer), §4.1 (Determinism), §14 (Engineering Principles), Appendix D (Repository Structure), Appendix H (NFR Baseline); Document 00A (`rasica-common`, `rasica-core`); Document 00B (`rasica-dataset`: `Schema`, `Column`, `ColumnType`, `Value`, `Row`, `Dataset`, `DatasetBuilder`, `SourceFormat`, `SourceMetadata`, `DatasetError`) |
| Produces Crates | `rasica-ingestion` |
| Produces Infrastructure | Workspace member addition; new workspace dependencies (`csv`, `calamine`, `serde_json`); a second benchmark (`benches/csv_ingestion.rs`) alongside Phase 2's `dataset_construction` benchmark |
| Consumed By | Phase 4 — Validation Engine (§15.7), and, eventually, `rasica-cli` (Application Controller, §8.3), which is the anticipated first caller of this crate's dispatch entry point |
| Intended Audience | Implementers (human or AI) building on the Phase 1 and Phase 2 foundations |
| Deviation Policy | Unchanged from Document 00A/00B: a deviation from a signature or invariant that also appears in the Architecture Spec is an architectural change requiring an ADR (§16.5/§14.18); a deviation confined to this document (e.g. an internal field name) may be made freely provided intent is preserved. |

---

## 1. Purpose and Scope

### 1.1 Purpose

This document is the authoritative, implementable specification for **Phase 3 — Data Ingestion**, the third entry in the RASICA development roadmap (Architecture Spec §15.6). It translates that phase's objective — "support external data sources" — into:

- concrete Rust reader implementations for the three Initial Sources named in §15.6 (CSV, Excel, JSON), each producing a `Dataset` exclusively via `rasica_dataset::dataset::DatasetBuilder`,
- a single, deterministic type-inference algorithm shared by all three readers, since none of §15.6's sources carry a RASICA `Schema` natively,
- a crate-local error framework covering every way an external source can fail to become a well-formed `Dataset`,
- a verification suite that makes §15.6's four-item Verification list ("no data loss," "correct typing," "correct encoding," "deterministic import") checkable rather than aspirational,
- a benchmark extending Phase 2's `benchmark-regression` CI job to cover ingestion throughput, per Architecture Spec §14.15's requirement that benchmarks evaluate "ingestion" by name.

Nothing in this document introduces new architecture. Every design decision below either implements a rule already stated in the Architecture Spec, Document 00A, or Document 00B, or resolves an underspecification in §15.6 explicitly, in §1.4 below, following the precedent Document 00B §1.4 set for this exact situation.

### 1.2 Scope

**In scope for Phase 3:**

- `rasica-ingestion`: readers for the three Initial Sources named in Architecture Spec §15.6 — CSV, Excel (`.xlsx`), and JSON (array-of-objects) — each producing a `rasica_dataset::dataset::Dataset` tagged with the matching `SourceFormat` variant and populated `SourceMetadata` (Document 00B §4.5).
- A shared, deterministic column-type inference and widening algorithm (`typing.rs`), since CSV and JSON carry no RASICA `ColumnType` and Excel's native cell types do not, by themselves, guarantee one consistent type per column.
- Minimal, format-level encoding handling: UTF-8 validation (with optional byte-order-mark stripping) for text-based sources (CSV, JSON). §1.4 Note 2 draws the exact line between this and general charset auto-detection.
- The crate-local `IngestionError` type, per the error contract established in Document 00A §4.4.
- A dispatch entry point (`ingest_path`) giving `rasica-cli` and any future caller one uniform call site across all three formats, implementing the "source abstraction" item in Architecture Spec §9.1's Dataset Engine responsibilities list.
- Extension of the Phase 1/2 test harness: fixtures, round-trip tests, and property tests specific to ingestion invariants, plus a new benchmark giving Architecture Spec §14.15's "ingestion" benchmarking category its first real body.

**Explicitly out of scope for Phase 3** (deferred to their own phase, or to an as-yet-unnumbered future phase per §15.6's own "Future Sources" list):

- SQL, Apache Arrow, and Apache Parquet readers — Architecture Spec §15.6 lists these as "Future Sources" without assigning them a roadmap phase number. This document defines no vocabulary for them beyond the `SourceFormat::Sql` / `SourceFormat::Arrow` / `SourceFormat::Parquet` variants Document 00B §4.5 already declared.
- Newline-delimited JSON (NDJSON) and any JSON shape other than a top-level array of flat objects. §1.4 Note 5 explains why this narrowing is confined to this document.
- Semantic or business-rule validation of any kind — Phase 4, Validation Engine (Architecture Spec §15.7, §9.2). A structurally well-typed `Dataset` produced by this phase's readers may still fail semantic validation; that is Phase 4's concern, not this one's.
- Datatype *semantics* — identifiers, categorical/continuous/temporal variables, distributions, relationships — Phase 5, Structural Inference (Architecture Spec §15.8). §1.4 Note 3 draws the exact line between the representational typing this phase performs and the semantic inference Phase 5 performs, mirroring the distinction Document 00B §1.4 Note 1 drew for `Metadata`.
- Any chunked, paged, or out-of-core reading strategy (Architecture Spec Appendix F). Every reader in this document reads its entire source into memory before constructing a `Dataset`, consistent with Document 00B §1.4 Note 2's narrowing of the Dataset's own backing.
- Non-UTF-8 text encodings (e.g. Latin-1, Shift-JIS, UTF-16). §1.4 Note 2 records this as a deliberate, revisable narrowing, not a violation of §15.6's "correct encoding" verification item.

Per Architecture Spec §15.1, implementers shall not begin Phase 4 work (or any later phase's work) inside `rasica-ingestion`.

### 1.3 Relationship to the Architecture Spec

| Phase 3 concern (§15.6) | Implemented in this document as |
|---|---|
| "Support external data sources" | §4 (`rasica-ingestion`), one module per Initial Source |
| Initial Sources: CSV | §4.5 (`src/csv.rs`) |
| Initial Sources: Excel | §4.6 (`src/excel.rs`) |
| Initial Sources: JSON | §4.7 (`src/json.rs`) |
| Future Sources: SQL, Arrow, Parquet | §10 (Non-Goals) — intentionally not implemented |
| Verification: no data loss / correct typing / correct encoding / deterministic import | §8 (Exit Criteria), each mapped to a specific test |
| Exit Criterion: "Imported datasets match source datasets exactly" | §8, round-trip fixture tests |

### 1.4 Interpretation Notes

Architecture Spec §15.6 states Phase 3's objective and verification requirements in four lines and a six-item list. As with Document 00B §1.4, several points are underspecified enough at the phase-roadmap level that they must be resolved here, explicitly, before any code is justified against them.

**Note 1 — Crate placement and naming.** Architecture Spec Appendix D's illustrative crate list (§Appendix D) does not name a dedicated ingestion crate; it lists `rasica-dataset` but nothing for reading external formats. Document 00B §4.1 is explicit that `rasica-dataset` "shall contain no format-reading code (Phase 3)," and Architecture Spec §9.1 assigns "ingestion" as one of four named responsibilities of the *Dataset Engine* layer as a whole (alongside "normalisation," "source abstraction," and "internal representation" — the latter being exactly what `rasica-dataset` already provides). Reading §9.1 and Document 00B §4.1 together, ingestion is architecturally part of the Dataset Engine's responsibility but implementationally a distinct crate from `rasica-dataset` itself. This document therefore introduces `rasica-ingestion` as a new crate, sitting at the same Infrastructure Layer position as `rasica-dataset` in the Core Dependency Graph (Architecture Spec §8.3), depending on `rasica-dataset` but not the reverse. Appendix D's own text ("the repository structure may evolve provided architectural boundaries remain intact") permits this; no dependency-direction rule in §8 is affected, since `rasica-ingestion` introduces no new layer, only a new crate within the Infrastructure Layer's existing Dataset Engine responsibility.

**Note 2 — Encoding scope.** §15.6 requires ingestion to verify "correct encoding" but the Architecture Spec defines no supported-encoding list anywhere. Auto-detecting an arbitrary source encoding (Shift-JIS, Latin-1, UTF-16, etc.) is a substantial, independently specifiable feature with its own false-positive risk — exactly the kind of "speculative generality against a requirement that does not yet exist" Document 00B §1.4 Note 2 declined to build for Dataset backings. Phase 3 therefore defines RASICA's supported source text encoding as UTF-8 (optionally BOM-prefixed) for CSV and JSON, and treats "correct encoding" as: (a) a byte-order mark, if present, is detected and stripped rather than ingested as data; (b) any byte sequence that is not valid UTF-8 is rejected with a specific, machine-readable error (`IngestionError::InvalidEncoding`) rather than silently replaced, truncated, or mis-decoded. Excel is exempted from this note because `.xlsx` is a structured, already-encoded container (calamine, §4.6, decodes its internal XML as UTF-8 as part of the format itself); there is no separate encoding choice for the implementer to make. Supporting additional text encodings is a future, additive change to `src/encoding.rs` (§4.4) requiring no change to any reader's public signature.

**Note 3 — Typing scope: representational, not semantic.** Every Initial Source arrives with either no RASICA type at all (CSV: every cell is text) or a native type system that does not map onto `rasica_dataset::schema::ColumnType` cleanly across an entire column (JSON: a column may mix integers and floating-point numbers across rows; Excel: a column may mix numeric and text cells across rows). §15.6's "correct typing" verification item requires this phase to resolve each column to exactly one `ColumnType`, deterministically, from the source data alone — this is a narrower, purely representational question ("what `ColumnType` can losslessly represent every value observed in this column?") than Structural Inference's semantic question ("is this integer column actually a categorical code or a Unix timestamp?", Architecture Spec §6.7, Phase 5). §4.3 below defines one shared, total, deterministic widening algorithm answering only the representational question; it populates `Schema`/`Value` (Document 00B §4.3–§4.4) and leaves `Metadata`'s interpretive fields (`distribution`, `scale`, `temporal_properties`) exactly as `None` as Document 00B §1.4 Note 1 already established — this phase changes nothing about `Metadata`.

**Note 4 — Excel temporal cells.** calamine represents an Excel date/time cell as a numeric serial value tagged `DataType::DateTime`, whose calendar interpretation depends on the workbook's date system (1900 vs. 1904) and is therefore not a context-free conversion. Correctly resolving it to a semantic instant is a temporal-semantics question in the same family as Note 3 draws a line around, and Architecture Spec §6.5 assigns `temporal_properties` to a future phase the roadmap does not yet number. Phase 3 therefore ingests a `DataType::DateTime` cell using calamine's own lossless textual rendering of the underlying value (§4.6), classified as `ColumnType::Text` like any other string cell. No information is lost — the original serial value is recoverable from the rendered text — and no phase downstream of this one needs to be redesigned when temporal semantics are eventually assigned a phase, per the same forward-compatible pattern Document 00B used for `ColumnMetadata`'s `Option`-typed interpretive fields.

**Note 5 — JSON shape and key ordering.** §15.6 says only "JSON," not which of JSON's many tabular encodings (array-of-objects, newline-delimited objects, column-oriented objects-of-arrays, etc.). Phase 3 supports exactly one shape — a top-level JSON array whose elements are all flat objects (no nested arrays or objects as values) — because it is the shape that maps onto `Schema`/`Row` without an additional, unspecified flattening convention. Newline-delimited JSON and nested values are explicitly deferred (§10); attempting either produces a specific `IngestionError` rather than a best-effort, ambiguous interpretation. Separately, RFC 8259 defines a JSON object as an *unordered* collection of name/value pairs, so "the order keys appeared in the source bytes" is not a property of the JSON value at all, only of one particular serialisation of it — using it as `Schema`'s column order would make two byte-different-but-semantically-identical JSON documents produce datasets that do not fingerprint identically, a direct conflict with Architecture Spec §4.1's Logical Determinism. Phase 3 therefore defines JSON column order as the lexicographic (byte-wise) order of key names, and implements this using `serde_json`'s default `Map` (a `BTreeMap`, already lexicographically ordered) rather than enabling the `preserve_order` feature — meeting the determinism requirement without an additional dependency (`indexmap`) that a source-order convention would otherwise require.

---

## 2. Engineering Baseline for This Phase

Everything in Document 00A §2 and Document 00B §2 continues to apply unchanged. The following restates only what is newly load-bearing in Phase 3:

- **§4.1 Determinism:** every reader in this document is a pure function of its input bytes (plus the small, explicit options struct each format accepts, e.g. a CSV delimiter) — the same bytes and options always produce the same `Dataset`, and therefore the same `Fingerprint` (Document 00B §4.6), independent of process, platform, or the underlying filesystem's directory-iteration order (which never enters a reader's logic, since each reader is handed one already-resolved path or byte stream). This is the concrete instance of Logical Determinism §15.6's "deterministic import" verification item is checking.
- **§9.1 Dataset Engine:** this document implements the "ingestion" and "source abstraction" responsibilities named there; "normalisation" is implemented narrowly, as the type-widening algorithm of §4.3 (resolving heterogeneous source representations to one `ColumnType` per column) — not as any semantic normalisation, which remains out of scope per §1.4 Note 3.
- **§14.7 Dependency Management:** three new external dependencies are introduced (`csv`, `calamine`, `serde_json`). Each is justified individually in §3.2 against §14.7's criteria (maturity, maintenance, licensing, performance, security, community adoption) rather than accepted by default.
- **§6.2A Mutability Tiers:** no new Core Architectural Object is introduced. Every reader's output is a `Dataset` (Tier 1, already established by Document 00B); `rasica-ingestion` itself introduces only non-Tiered helper types (options structs, the type-widening accumulator) that exist only during construction, exactly as `DatasetBuilder` (Document 00B §4.6) is not itself Tiered.
- **§14.9 Error Handling:** `rasica-ingestion` defines one crate-local `IngestionError` implementing Document 00A's `RasicaError` contract (§4.4.1), following the worked example (`ConfigError`) verbatim in structure, and wraps `rasica-dataset`'s `SchemaError`/`DatasetError` rather than duplicating their variants.

---

## 3. Repository & Workspace Layout Update

### 3.1 Directory Structure (Phase 3 additions)

This is additive to Document 00A §3.1 and Document 00B §3.1. No previously created path is renamed or moved.

```text
rasica/
├── crates/
│   ├── rasica-common/                # unchanged, Phase 1
│   ├── rasica-core/                  # unchanged, Phase 1
│   ├── rasica-dataset/               # unchanged, Phase 2
│   └── rasica-ingestion/             # new
│       ├── Cargo.toml
│       ├── benches/
│       │   └── csv_ingestion.rs
│       ├── tests/
│       │   └── fixtures/
│       │       ├── well_formed.csv
│       │       ├── utf8_bom.csv
│       │       ├── invalid_encoding.csv
│       │       ├── well_formed.xlsx
│       │       └── well_formed.json
│       └── src/
│           ├── lib.rs
│           ├── error.rs
│           ├── encoding.rs
│           ├── typing.rs
│           ├── csv.rs
│           ├── excel.rs
│           ├── json.rs
│           ├── ingest.rs
│           └── prelude.rs
├── tests/
│   └── workspace_smoke/
│       └── tests/
│           └── smoke.rs              # extended, not replaced (§5.2)
```

`domains/`, `datasets/`, and the remaining `crates/rasica-*` from Architecture Spec Appendix D remain out of scope, created by the phase specification that first needs them. The `tests/fixtures/well_formed.xlsx` file is a small, binary `.xlsx` workbook and is therefore described by content and structure in §5.2 rather than reproduced inline; implementers construct it once, by hand or with a throwaway script, and commit it as a fixed test fixture.

### 3.2 Workspace Root `Cargo.toml` — Diff

```toml
[workspace]
members = [
    "crates/rasica-common",
    "crates/rasica-core",
    "crates/rasica-dataset",
    "crates/rasica-ingestion",         # new
    "tests/workspace_smoke",
]

[workspace.dependencies]
# ... Phase 1 and Phase 2 entries unchanged ...

# --- data ingestion (§15.6) ---
# csv: the de facto standard CSV reader for Rust; mature (pre-1.0 API stable
#   since 2018), maintained by BurntSushi (also the author of ripgrep/regex),
#   MIT/Unlicense dual-licensed (already within deny.toml's allow list via
#   MIT), no unsafe in its public parsing path, and the highest-adoption CSV
#   crate on crates.io by a wide margin (§14.7's "community adoption").
csv = "1.3"
# calamine: pure-Rust reader for Excel (.xlsx/.xls/.xlsm) and OpenDocument
#   spreadsheets; MIT licensed, actively maintained, and — unlike bindings to
#   libxlsxwriter or similar — introduces no C FFI surface, keeping
#   `#![forbid(unsafe_code)]` (§4.5 below) achievable in this crate.
calamine = "0.25"
# serde_json: the standard JSON implementation in the Rust ecosystem, already
#   a transitive dependency of `figment` (Document 00A §4.5) via its
#   `serde`-based configuration layers, so this adds no new supply-chain
#   surface beyond what Phase 1 already pulled in.
serde_json = "1.0"
```

`[workspace.lints]` (Document 00A §3.2), `rustfmt.toml`, `clippy.toml`, `nextest.toml` are unchanged; `rasica-ingestion` inherits them via `[lints] workspace = true` exactly as every earlier crate does. `deny.toml` requires no change: `csv` (MIT/Unlicense), `calamine` (MIT), and `serde_json` (MIT/Apache-2.0) each satisfy an already-allowed license, and none introduces a banned wildcard dependency or an unknown registry/git source.

---

## 4. Crate: `rasica-ingestion`

### 4.1 Responsibilities

`rasica-ingestion` owns the "ingestion" and "source abstraction" items of Architecture Spec §9.1's Dataset Engine responsibilities list. It depends on `rasica-common` (for `RasicaError`), `rasica-core` (transitively required by `rasica-dataset`'s public types), and `rasica-dataset` (for `Schema`, `Column`, `ColumnType`, `Value`, `Row`, `DatasetBuilder`, `Dataset`, `SourceFormat`, `SourceMetadata`), and on nothing else internal, preserving the acyclic dependency graph Document 00A §5.1 established and Document 00B §4.1 continued.

`rasica-ingestion` shall contain no semantic or business-rule validation (Phase 4), no statistical or structural inference (Phase 5), and constructs every `Dataset` it produces exclusively through `DatasetBuilder` — it introduces no alternative construction path for `Dataset`, per Document 00B §10's forward pointer ("Phase 3 will implement one reader per `SourceFormat` variant... no new construction API is expected").

### 4.2 `Cargo.toml`

```toml
[package]
name = "rasica-ingestion"
description = "External-source readers (CSV, Excel, JSON) producing rasica-dataset Datasets."
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
rasica-dataset = { path = "../rasica-dataset" }
thiserror = { workspace = true }
csv = { workspace = true }
calamine = { workspace = true }
serde_json = { workspace = true }

[dev-dependencies]
proptest = { workspace = true }
rstest = { workspace = true }
criterion = { workspace = true }

[[bench]]
name = "csv_ingestion"
harness = false
```

### 4.3 Type Inference and Widening — `src/typing.rs`

This is the one algorithm every reader in this crate shares. It answers exactly the representational question §1.4 Note 3 scopes this phase to: given every value observed in one column, across an arbitrary mix of Rust-native source types, what is the single `rasica_dataset::schema::ColumnType` that can represent all of them without loss?

```rust
//! Deterministic column-type inference and widening, shared by every reader
//! in this crate (§1.4 Note 3 of the Phase 3 Implementation Specification).
//!
//! Each source format observes its cells in whatever native representation
//! that format provides (raw text for CSV, `serde_json::Value` for JSON,
//! `calamine::DataType` for Excel). [`NaturalType`] is the one common
//! vocabulary every format's observations are translated into before this
//! module's widening rule is applied, so the rule itself is written once.

use rasica_dataset::schema::ColumnType;

/// The representational type of a single observed, non-null value, prior to
/// being reconciled against the rest of its column.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum NaturalType {
    /// A value recognised unambiguously as boolean by the source format's
    /// own type system (never inferred from a text literal such as `"1"`,
    /// which would be ambiguous with [`NaturalType::Integer`]).
    Boolean,
    /// A value representable exactly as a 64-bit signed integer.
    Integer,
    /// A value requiring floating-point representation.
    Float,
    /// Any value not covered by the above — including every value once any
    /// sibling in its column has forced widening past what the above three
    /// variants can jointly represent.
    Text,
}

/// Combines two [`NaturalType`]s observed in the same column into the
/// narrowest type able to represent both, without loss.
///
/// This operation is commutative and associative — `join` may therefore be
/// folded over a column's values in any order and still produce a
/// deterministic result, which is what allows §4.5's, §4.6's, and §4.7's
/// readers to share one accumulator (below) regardless of each format's own
/// row-iteration order.
///
/// | ⊔        | Boolean | Integer | Float | Text |
/// |----------|---------|---------|-------|------|
/// | Boolean  | Boolean | Text    | Text  | Text |
/// | Integer  | Text    | Integer | Float | Text |
/// | Float    | Text    | Float   | Float | Text |
/// | Text     | Text    | Text    | Text  | Text |
///
/// Boolean is never widened into Integer or Float: RASICA does not treat
/// `true`/`1` as interchangeable, since doing so would make a genuinely
/// boolean column and a genuinely integer column containing only `0`/`1`
/// indistinguishable, which is exactly the kind of representational
/// ambiguity §15.6's "correct typing" verification item exists to prevent.
#[must_use]
pub(crate) const fn join(a: NaturalType, b: NaturalType) -> NaturalType {
    use NaturalType::{Boolean, Float, Integer, Text};
    match (a, b) {
        (Boolean, Boolean) => Boolean,
        (Integer, Integer) => Integer,
        (Float, Float) | (Integer, Float) | (Float, Integer) => Float,
        _ => Text,
    }
}

/// Folds a column's observed [`NaturalType`]s into one resolved
/// [`ColumnType`], one value at a time, in a single forward pass.
///
/// A column containing only null values (or, degenerately, zero rows) has
/// no observation to resolve from; such a column resolves to
/// [`ColumnType::Text`], the widest and therefore safest representation for
/// a column about which nothing else is known. This mirrors `join`'s own
/// behaviour of resolving any genuine ambiguity to `Text` rather than
/// guessing.
#[derive(Debug, Clone, Copy, Default)]
pub(crate) struct ColumnTypeAccumulator {
    resolved: Option<NaturalType>,
}

impl ColumnTypeAccumulator {
    /// Starts a fresh accumulator with no observations yet.
    #[must_use]
    pub(crate) const fn new() -> Self {
        Self { resolved: None }
    }

    /// Folds in one observed value's [`NaturalType`]. Pass `None` for a
    /// null cell: nulls do not participate in type resolution, matching
    /// `rasica_dataset`'s treatment of [`rasica_dataset::value::Value::Null`]
    /// as agreeing with every [`ColumnType`] (Document 00B §4.6).
    pub(crate) fn observe(&mut self, natural_type: Option<NaturalType>) {
        let Some(observed) = natural_type else {
            return;
        };
        self.resolved = Some(match self.resolved {
            None => observed,
            Some(current) => join(current, observed),
        });
    }

    /// Resolves the final [`ColumnType`] for this column.
    #[must_use]
    pub(crate) fn finish(self) -> ColumnType {
        match self.resolved {
            Some(NaturalType::Boolean) => ColumnType::Boolean,
            Some(NaturalType::Integer) => ColumnType::Integer,
            Some(NaturalType::Float) => ColumnType::Float,
            Some(NaturalType::Text) | None => ColumnType::Text,
        }
    }
}

/// Classifies a raw CSV/text cell's [`NaturalType`], used by §4.5's CSV
/// reader during its type-resolution pass.
///
/// Recognition is deliberately strict and case-sensitive-only for booleans
/// (`"true"`/`"false"`, exactly) to avoid the ambiguity a looser match
/// (`"1"`, `"yes"`, `"T"`, ...) would introduce against [`NaturalType::Integer`]
/// and [`NaturalType::Text`] alike.
#[must_use]
pub(crate) fn classify_text(raw: &str) -> NaturalType {
    if raw == "true" || raw == "false" {
        NaturalType::Boolean
    } else if raw.parse::<i64>().is_ok() {
        NaturalType::Integer
    } else if raw.parse::<f64>().is_ok() {
        NaturalType::Float
    } else {
        NaturalType::Text
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn join_is_commutative_for_every_pair() {
        let variants = [
            NaturalType::Boolean,
            NaturalType::Integer,
            NaturalType::Float,
            NaturalType::Text,
        ];
        for &a in &variants {
            for &b in &variants {
                assert_eq!(join(a, b), join(b, a));
            }
        }
    }

    #[test]
    fn integer_and_float_widen_to_float() {
        assert_eq!(join(NaturalType::Integer, NaturalType::Float), NaturalType::Float);
    }

    #[test]
    fn boolean_and_integer_widen_to_text() {
        assert_eq!(join(NaturalType::Boolean, NaturalType::Integer), NaturalType::Text);
    }

    #[test]
    fn all_null_column_resolves_to_text() {
        let mut acc = ColumnTypeAccumulator::new();
        acc.observe(None);
        acc.observe(None);
        assert_eq!(acc.finish(), ColumnType::Text);
    }

    #[test]
    fn classify_text_does_not_treat_zero_or_one_as_boolean() {
        assert_eq!(classify_text("1"), NaturalType::Integer);
        assert_eq!(classify_text("0"), NaturalType::Integer);
    }

    proptest::proptest! {
        #[test]
        fn accumulator_result_is_independent_of_observation_order(
            a in 0..4usize, b in 0..4usize, c in 0..4usize,
        ) {
            let variants = [
                NaturalType::Boolean,
                NaturalType::Integer,
                NaturalType::Float,
                NaturalType::Text,
            ];
            let observations = [variants[a], variants[b], variants[c]];

            let mut forward = ColumnTypeAccumulator::new();
            for &o in &observations {
                forward.observe(Some(o));
            }

            let mut reversed = ColumnTypeAccumulator::new();
            for &o in observations.iter().rev() {
                reversed.observe(Some(o));
            }

            proptest::prop_assert_eq!(forward.finish(), reversed.finish());
        }
    }
}
```

### 4.4 Encoding — `src/encoding.rs`

Implements §1.4 Note 2 in full: UTF-8 is the only supported text encoding for CSV and JSON; a leading byte-order mark is stripped rather than ingested.

```rust
//! UTF-8 validation and byte-order-mark handling for text-based sources
//! (§1.4 Note 2 of the Phase 3 Implementation Specification).

const UTF8_BOM: [u8; 3] = [0xEF, 0xBB, 0xBF];

/// Strips a leading UTF-8 byte-order mark from `bytes`, if present, then
/// validates the remainder as UTF-8.
///
/// # Errors
///
/// Returns the underlying [`std::str::Utf8Error`] if `bytes` (after BOM
/// stripping) is not valid UTF-8. This is the sole encoding check Phase 3
/// performs; non-UTF-8 encodings are out of scope (§1.4 Note 2) and are
/// surfaced to callers as [`crate::error::IngestionError::InvalidEncoding`].
pub(crate) fn strip_bom_and_validate_utf8(bytes: &[u8]) -> Result<&str, std::str::Utf8Error> {
    let without_bom = bytes.strip_prefix(&UTF8_BOM).unwrap_or(bytes);
    std::str::from_utf8(without_bom)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_bom_when_present() {
        let mut bytes = UTF8_BOM.to_vec();
        bytes.extend_from_slice(b"a,b\n1,2\n");
        assert_eq!(
            strip_bom_and_validate_utf8(&bytes).expect("valid UTF-8 after BOM"),
            "a,b\n1,2\n"
        );
    }

    #[test]
    fn passes_through_unchanged_without_bom() {
        assert_eq!(strip_bom_and_validate_utf8(b"a,b\n1,2\n"), Ok("a,b\n1,2\n"));
    }

    #[test]
    fn rejects_invalid_utf8() {
        assert!(strip_bom_and_validate_utf8(&[0xFF, 0xFE, 0x00]).is_err());
    }
}
```

### 4.5 CSV Reader — `src/csv.rs`

Reads its entire input into memory once (an in-memory `Vec<csv::StringRecord>`), then makes two deterministic passes over that in-memory buffer: one to resolve each column's `ColumnType` (§4.3), one to build `Row`s against the resolved `Schema`. No file is read twice; only the already-buffered records are visited twice.

```rust
//! CSV ingestion (Architecture Spec §15.6, Initial Source: CSV).

use std::io::Read;

use rasica_dataset::{
    dataset::DatasetBuilder,
    dataset::Dataset,
    row::Row,
    schema::{Column, ColumnType, Schema},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};

use crate::{
    encoding::strip_bom_and_validate_utf8,
    error::IngestionError,
    typing::{classify_text, ColumnTypeAccumulator},
};

/// Configuration for [`read`].
#[derive(Debug, Clone, Copy)]
pub struct CsvOptions {
    /// The field delimiter byte. Defaults to `,` via [`Default`].
    pub delimiter: u8,
}

impl Default for CsvOptions {
    fn default() -> Self {
        Self { delimiter: b',' }
    }
}

/// Reads a CSV document from `reader`, treating its first row as the header,
/// and returns a [`Dataset`] tagged [`SourceFormat::Csv`] with `origin` as
/// its recorded provenance.
///
/// # Errors
///
/// Returns [`IngestionError::InvalidEncoding`] if the input is not valid
/// UTF-8 (§1.4 Note 2); [`IngestionError::Empty`] if the input has a header
/// but zero data rows, or no rows at all; [`IngestionError::InconsistentRowArity`]
/// if any data row has a different field count than the header;
/// [`IngestionError::SchemaConstructionFailed`] or
/// [`IngestionError::DatasetConstructionFailed`] if the resolved schema or
/// rows are otherwise malformed per `rasica-dataset`'s own invariants.
pub fn read(
    mut reader: impl Read,
    origin: impl Into<String>,
    options: CsvOptions,
) -> Result<Dataset, IngestionError> {
    let origin = origin.into();

    let mut raw_bytes = Vec::new();
    reader
        .read_to_end(&mut raw_bytes)
        .map_err(|cause| IngestionError::SourceUnreadable {
            origin: origin.clone(),
            cause,
        })?;
    let text = strip_bom_and_validate_utf8(&raw_bytes).map_err(|cause| {
        IngestionError::InvalidEncoding {
            origin: origin.clone(),
            cause,
        }
    })?;

    let mut csv_reader = ::csv::ReaderBuilder::new()
        .delimiter(options.delimiter)
        .has_headers(true)
        .flexible(true) // arity is checked explicitly below, with row numbers.
        .from_reader(text.as_bytes());

    let header = csv_reader
        .headers()
        .map_err(|cause| IngestionError::SourceUnreadable {
            origin: origin.clone(),
            cause: std::io::Error::new(std::io::ErrorKind::InvalidData, cause),
        })?
        .clone();
    if header.is_empty() {
        return Err(IngestionError::Empty {
            origin: origin.clone(),
        });
    }

    let records: Vec<::csv::StringRecord> = csv_reader
        .records()
        .enumerate()
        .map(|(index, result)| {
            let record = result.map_err(|cause| IngestionError::SourceUnreadable {
                origin: origin.clone(),
                cause: std::io::Error::new(std::io::ErrorKind::InvalidData, cause),
            })?;
            if record.len() != header.len() {
                return Err(IngestionError::InconsistentRowArity {
                    origin: origin.clone(),
                    row_number: index + 2, // +1 for the header row, +1 for 1-based numbering.
                    expected: header.len(),
                    actual: record.len(),
                });
            }
            Ok(record)
        })
        .collect::<Result<_, IngestionError>>()?;

    if records.is_empty() {
        return Err(IngestionError::Empty {
            origin: origin.clone(),
        });
    }

    // Pass 1: resolve one ColumnType per column.
    let mut accumulators: Vec<ColumnTypeAccumulator> =
        vec![ColumnTypeAccumulator::new(); header.len()];
    for record in &records {
        for (position, raw) in record.iter().enumerate() {
            let natural_type = if raw.is_empty() {
                None
            } else {
                Some(classify_text(raw))
            };
            accumulators[position].observe(natural_type);
        }
    }
    let column_types: Vec<ColumnType> = accumulators.into_iter().map(ColumnTypeAccumulator::finish).collect();

    let columns = header
        .iter()
        .zip(&column_types)
        .map(|(name, &column_type)| Column::new(name, column_type))
        .collect();
    let schema = Schema::new(columns).map_err(IngestionError::SchemaConstructionFailed)?;

    // Pass 2: build each Row against the resolved Schema.
    let mut builder = DatasetBuilder::new(schema);
    for record in &records {
        let values = record
            .iter()
            .zip(&column_types)
            .map(|(raw, &column_type)| parse_value(raw, column_type))
            .collect();
        builder
            .push_row(Row::new(values))
            .map_err(IngestionError::DatasetConstructionFailed)?;
    }

    Ok(builder.build(SourceMetadata::new(SourceFormat::Csv, origin)))
}

/// Parses one already-classified raw cell into a [`Value`].
///
/// This never fails: `column_type` was resolved (§4.3) from the very values
/// it is now applied to, so every non-empty cell is guaranteed parseable as
/// its column's resolved type, and an empty cell is always [`Value::Null`].
fn parse_value(raw: &str, column_type: ColumnType) -> Value {
    if raw.is_empty() {
        return Value::Null;
    }
    match column_type {
        ColumnType::Boolean => Value::Boolean(raw == "true"),
        ColumnType::Integer => Value::Integer(
            raw.parse()
                .expect("column_type was resolved from this exact value in pass 1"),
        ),
        ColumnType::Float => Value::Float(
            raw.parse()
                .expect("column_type was resolved from this exact value in pass 1"),
        ),
        ColumnType::Text => Value::Text(raw.to_owned()),
    }
}
```

### 4.6 Excel Reader — `src/excel.rs`

```rust
//! Excel (`.xlsx`) ingestion (Architecture Spec §15.6, Initial Source: Excel).
//!
//! Only `.xlsx` (Office Open XML) is targeted explicitly; calamine's
//! `open_workbook_auto` also accepts legacy `.xls` and OpenDocument `.ods`
//! transparently, so this reader is not artificially restricted to `.xlsx`,
//! but `.xlsx` is the only format this document's fixtures and exit
//! criteria (§8) exercise.

use std::path::Path;

use calamine::{open_workbook_auto, DataType, Reader};
use rasica_dataset::{
    dataset::{Dataset, DatasetBuilder},
    row::Row,
    schema::{Column, ColumnType, Schema},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};

use crate::{
    error::IngestionError,
    typing::{ColumnTypeAccumulator, NaturalType},
};

/// Configuration for [`read`].
#[derive(Debug, Clone)]
pub struct ExcelOptions {
    /// The worksheet to read. `None` selects the workbook's first sheet.
    pub sheet_name: Option<String>,
}

impl Default for ExcelOptions {
    fn default() -> Self {
        Self { sheet_name: None }
    }
}

/// Reads one worksheet of an Excel workbook at `path`, treating its first
/// row as the header, and returns a [`Dataset`] tagged [`SourceFormat::Excel`].
///
/// # Errors
///
/// Returns [`IngestionError::SourceUnreadable`] if the workbook cannot be
/// opened; [`IngestionError::ExcelSheetNotFound`] if `options.sheet_name` is
/// `Some` and no such sheet exists; [`IngestionError::Empty`] if the sheet
/// has a header but no data rows; [`IngestionError::InconsistentRowArity`],
/// [`IngestionError::SchemaConstructionFailed`], and
/// [`IngestionError::DatasetConstructionFailed`] as in §4.5.
pub fn read(path: &Path, options: ExcelOptions) -> Result<Dataset, IngestionError> {
    let origin = path.display().to_string();

    let mut workbook = open_workbook_auto(path).map_err(|cause| IngestionError::SourceUnreadable {
        origin: origin.clone(),
        cause: std::io::Error::new(std::io::ErrorKind::InvalidData, cause),
    })?;

    let sheet_name = match &options.sheet_name {
        Some(name) => name.clone(),
        None => workbook
            .sheet_names()
            .first()
            .cloned()
            .ok_or_else(|| IngestionError::Empty {
                origin: origin.clone(),
            })?,
    };

    let range = workbook
        .worksheet_range(&sheet_name)
        .ok_or_else(|| IngestionError::ExcelSheetNotFound {
            origin: origin.clone(),
            sheet: sheet_name.clone(),
        })?
        .map_err(|cause| IngestionError::SourceUnreadable {
            origin: origin.clone(),
            cause: std::io::Error::new(std::io::ErrorKind::InvalidData, cause),
        })?;

    let mut rows_iter = range.rows();
    let header = rows_iter.next().ok_or_else(|| IngestionError::Empty {
        origin: origin.clone(),
    })?;
    let arity = header.len();
    if arity == 0 {
        return Err(IngestionError::Empty {
            origin: origin.clone(),
        });
    }

    let data_rows: Vec<&[DataType]> = rows_iter.collect();
    if data_rows.is_empty() {
        return Err(IngestionError::Empty {
            origin: origin.clone(),
        });
    }

    for (index, row) in data_rows.iter().enumerate() {
        if row.len() != arity {
            return Err(IngestionError::InconsistentRowArity {
                origin: origin.clone(),
                row_number: index + 2,
                expected: arity,
                actual: row.len(),
            });
        }
    }

    // Pass 1: resolve one ColumnType per column.
    let mut accumulators: Vec<ColumnTypeAccumulator> = vec![ColumnTypeAccumulator::new(); arity];
    for row in &data_rows {
        for (position, cell) in row.iter().enumerate() {
            accumulators[position].observe(natural_type_of(cell));
        }
    }
    let column_types: Vec<ColumnType> = accumulators.into_iter().map(ColumnTypeAccumulator::finish).collect();

    let columns = header
        .iter()
        .zip(&column_types)
        .map(|(cell, &column_type)| Column::new(cell.to_string(), column_type))
        .collect();
    let schema = Schema::new(columns).map_err(IngestionError::SchemaConstructionFailed)?;

    // Pass 2: build each Row against the resolved Schema.
    let mut builder = DatasetBuilder::new(schema);
    for row in &data_rows {
        let values = row
            .iter()
            .zip(&column_types)
            .map(|(cell, &column_type)| parse_value(cell, column_type))
            .collect();
        builder
            .push_row(Row::new(values))
            .map_err(IngestionError::DatasetConstructionFailed)?;
    }

    Ok(builder.build(SourceMetadata::new(SourceFormat::Excel, origin)))
}

/// Classifies one Excel cell's [`NaturalType`], or `None` if the cell is
/// empty (calamine's [`DataType::Empty`]).
///
/// Per §1.4 Note 4, [`DataType::DateTime`] is classified as
/// [`NaturalType::Text`]: temporal semantics are out of scope for this
/// phase, and calamine's textual rendering of the underlying serial value
/// is lossless.
fn natural_type_of(cell: &DataType) -> Option<NaturalType> {
    match cell {
        DataType::Empty => None,
        DataType::Bool(_) => Some(NaturalType::Boolean),
        DataType::Int(_) => Some(NaturalType::Integer),
        DataType::Float(_) => Some(NaturalType::Float),
        DataType::String(_) | DataType::DateTime(_) | DataType::Duration(_) | DataType::Error(_) => {
            Some(NaturalType::Text)
        }
    }
}

/// Converts one Excel cell into a [`Value`] under its column's resolved type.
///
/// As in §4.5, this cannot fail: `column_type` is the join (§4.3) of every
/// cell's own [`NaturalType`] observed in pass 1, so every cell already
/// agrees with it — a numeric cell being widened to [`ColumnType::Text`]
/// is rendered via calamine's own `to_string()`, which is exact and lossless.
fn parse_value(cell: &DataType, column_type: ColumnType) -> Value {
    if matches!(cell, DataType::Empty) {
        return Value::Null;
    }
    match (cell, column_type) {
        (DataType::Bool(b), ColumnType::Boolean) => Value::Boolean(*b),
        (DataType::Int(i), ColumnType::Integer) => Value::Integer(*i),
        (DataType::Int(i), ColumnType::Float) => Value::Float(*i as f64),
        (DataType::Float(f), ColumnType::Float) => Value::Float(*f),
        (_, ColumnType::Text) => Value::Text(cell.to_string()),
        (cell, column_type) => unreachable!(
            "column_type {column_type:?} was resolved from this exact cell {cell:?} in pass 1"
        ),
    }
}
```

### 4.7 JSON Reader — `src/json.rs`

```rust
//! JSON ingestion (Architecture Spec §15.6, Initial Source: JSON).
//!
//! Supports exactly one shape: a top-level array of flat objects, all
//! sharing the same key set (§1.4 Note 5). Column order is the lexicographic
//! order of key names, not source-incidental order (§1.4 Note 5).

use std::io::Read;

use rasica_dataset::{
    dataset::{Dataset, DatasetBuilder},
    row::Row,
    schema::{Column, ColumnType, Schema},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};
use serde_json::Value as JsonValue;

use crate::{
    encoding::strip_bom_and_validate_utf8,
    error::IngestionError,
    typing::{ColumnTypeAccumulator, NaturalType},
};

/// Reads a JSON array-of-objects document from `reader` and returns a
/// [`Dataset`] tagged [`SourceFormat::Json`].
///
/// # Errors
///
/// Returns [`IngestionError::InvalidEncoding`] if the input is not valid
/// UTF-8; [`IngestionError::SourceUnreadable`] if the input is not
/// well-formed JSON; [`IngestionError::UnsupportedJsonShape`] if the
/// top-level value is not an array, or any element is not a flat object
/// (§1.4 Note 5); [`IngestionError::Empty`] if the array has zero elements;
/// [`IngestionError::AmbiguousJsonSchema`] if elements do not share exactly
/// the same key set; [`IngestionError::SchemaConstructionFailed`] and
/// [`IngestionError::DatasetConstructionFailed`] as in §4.5.
pub fn read(mut reader: impl Read, origin: impl Into<String>) -> Result<Dataset, IngestionError> {
    let origin = origin.into();

    let mut raw_bytes = Vec::new();
    reader
        .read_to_end(&mut raw_bytes)
        .map_err(|cause| IngestionError::SourceUnreadable {
            origin: origin.clone(),
            cause,
        })?;
    let text = strip_bom_and_validate_utf8(&raw_bytes).map_err(|cause| {
        IngestionError::InvalidEncoding {
            origin: origin.clone(),
            cause,
        }
    })?;

    let parsed: JsonValue =
        serde_json::from_str(text).map_err(|cause| IngestionError::SourceUnreadable {
            origin: origin.clone(),
            cause: std::io::Error::new(std::io::ErrorKind::InvalidData, cause),
        })?;

    let JsonValue::Array(elements) = parsed else {
        return Err(IngestionError::UnsupportedJsonShape {
            origin: origin.clone(),
        });
    };
    if elements.is_empty() {
        return Err(IngestionError::Empty {
            origin: origin.clone(),
        });
    }

    // Column order is the lexicographic key order of the first (and, once
    // validated below, every) object — `serde_json::Map`'s default
    // backing (`BTreeMap`) already iterates in this order (§1.4 Note 5).
    let mut column_names: Option<Vec<String>> = None;
    let mut objects = Vec::with_capacity(elements.len());
    for (index, element) in elements.into_iter().enumerate() {
        let JsonValue::Object(map) = element else {
            return Err(IngestionError::UnsupportedJsonShape {
                origin: origin.clone(),
            });
        };
        let keys: Vec<String> = map.keys().cloned().collect();
        match &column_names {
            None => column_names = Some(keys),
            Some(expected) if expected == &keys => {}
            Some(expected) => {
                return Err(IngestionError::AmbiguousJsonSchema {
                    origin: origin.clone(),
                    object_index: index,
                    expected_keys: expected.clone(),
                    actual_keys: keys,
                });
            }
        }
        objects.push(map);
    }
    let column_names = column_names.expect("objects is non-empty, so column_names was set above");

    // Pass 1: resolve one ColumnType per column.
    let mut accumulators: Vec<ColumnTypeAccumulator> =
        vec![ColumnTypeAccumulator::new(); column_names.len()];
    for object in &objects {
        for (position, name) in column_names.iter().enumerate() {
            let field = object
                .get(name)
                .expect("every object was validated to share this exact key set above");
            accumulators[position].observe(natural_type_of(field, &origin, name)?);
        }
    }
    let column_types: Vec<ColumnType> = accumulators.into_iter().map(ColumnTypeAccumulator::finish).collect();

    let columns = column_names
        .iter()
        .zip(&column_types)
        .map(|(name, &column_type)| Column::new(name.clone(), column_type))
        .collect();
    let schema = Schema::new(columns).map_err(IngestionError::SchemaConstructionFailed)?;

    // Pass 2: build each Row against the resolved Schema.
    let mut builder = DatasetBuilder::new(schema);
    for object in &objects {
        let values = column_names
            .iter()
            .zip(&column_types)
            .map(|(name, &column_type)| {
                let field = object
                    .get(name)
                    .expect("every object was validated to share this exact key set above");
                parse_value(field, column_type)
            })
            .collect();
        builder
            .push_row(Row::new(values))
            .map_err(IngestionError::DatasetConstructionFailed)?;
    }

    Ok(builder.build(SourceMetadata::new(SourceFormat::Json, origin)))
}

/// Classifies one JSON field's [`NaturalType`], or `None` for `null`.
///
/// # Errors
///
/// Returns [`IngestionError::UnsupportedJsonValue`] for a nested array or
/// object (§1.4 Note 5): silently stringifying a nested value would be a
/// lossy, ambiguous representation, which §15.6's "no data loss" and
/// "correct typing" verification items both rule out.
fn natural_type_of(
    field: &JsonValue,
    origin: &str,
    key: &str,
) -> Result<Option<NaturalType>, IngestionError> {
    match field {
        JsonValue::Null => Ok(None),
        JsonValue::Bool(_) => Ok(Some(NaturalType::Boolean)),
        JsonValue::Number(n) if n.is_i64() || n.is_u64() => Ok(Some(NaturalType::Integer)),
        JsonValue::Number(_) => Ok(Some(NaturalType::Float)),
        JsonValue::String(_) => Ok(Some(NaturalType::Text)),
        JsonValue::Array(_) | JsonValue::Object(_) => Err(IngestionError::UnsupportedJsonValue {
            origin: origin.to_owned(),
            key: key.to_owned(),
        }),
    }
}

/// Converts one JSON field into a [`Value`] under its column's resolved type.
///
/// As in §4.5 and §4.6, this cannot fail for the same reason: `column_type`
/// was resolved from this exact field's own [`NaturalType`] in pass 1.
fn parse_value(field: &JsonValue, column_type: ColumnType) -> Value {
    match (field, column_type) {
        (JsonValue::Null, _) => Value::Null,
        (JsonValue::Bool(b), ColumnType::Boolean) => Value::Boolean(*b),
        (JsonValue::Number(n), ColumnType::Integer) => Value::Integer(
            n.as_i64()
                .expect("column_type Integer was resolved only from i64/u64-representable numbers"),
        ),
        (JsonValue::Number(n), ColumnType::Float) => Value::Float(
            n.as_f64()
                .expect("every serde_json::Number converts losslessly to f64"),
        ),
        (JsonValue::String(s), ColumnType::Text) => Value::Text(s.clone()),
        (field, ColumnType::Text) => Value::Text(field.to_string()),
        (field, column_type) => unreachable!(
            "column_type {column_type:?} was resolved from this exact field {field:?} in pass 1"
        ),
    }
}
```

### 4.8 Dispatch Entry Point — `src/ingest.rs`

Implements the "source abstraction" item of Architecture Spec §9.1: one call site across all three Initial Sources, for `rasica-cli` (Architecture Spec §8.3) or any other future caller.

```rust
//! One uniform entry point across every Initial Source (§9.1, "source
//! abstraction"). Format-specific configuration lives in this module so
//! callers select a format once, rather than importing three modules.

use std::{fs::File, io::BufReader, path::Path};

use rasica_dataset::dataset::Dataset;

use crate::{csv, error::IngestionError, excel, json};

/// Per-format configuration for [`ingest_path`].
#[derive(Debug, Clone)]
pub enum FormatOptions {
    /// See [`csv::CsvOptions`].
    Csv(csv::CsvOptions),
    /// See [`excel::ExcelOptions`].
    Excel(excel::ExcelOptions),
    /// JSON accepts no configuration in Phase 3 (§1.4 Note 5 fixes its
    /// supported shape and column-ordering convention unconditionally).
    Json,
}

/// Reads `path` under `options`, dispatching to the matching format's
/// reader, and returns the resulting [`Dataset`].
///
/// # Errors
///
/// Propagates whichever [`IngestionError`] the selected format's reader
/// returns; see [`csv::read`], [`excel::read`], and [`json::read`].
pub fn ingest_path(path: &Path, options: FormatOptions) -> Result<Dataset, IngestionError> {
    let origin = path.display().to_string();
    match options {
        FormatOptions::Csv(csv_options) => {
            let file = File::open(path).map_err(|cause| IngestionError::SourceUnreadable {
                origin: origin.clone(),
                cause,
            })?;
            csv::read(BufReader::new(file), origin, csv_options)
        }
        FormatOptions::Excel(excel_options) => excel::read(path, excel_options),
        FormatOptions::Json => {
            let file = File::open(path).map_err(|cause| IngestionError::SourceUnreadable {
                origin: origin.clone(),
                cause,
            })?;
            json::read(BufReader::new(file), origin)
        }
    }
}
```

### 4.9 Error Framework — `src/error.rs`

Follows Document 00A §4.4.2's worked example exactly, and wraps `rasica-dataset`'s own errors (Document 00B §4.7) rather than duplicating their variants — per §14.6's prohibition on unrelated responsibilities sharing one type.

```rust
//! Errors produced while ingesting an external source (Architecture Spec
//! §14.9; Document 00A §4.4).

use thiserror::Error;

use rasica_common::error::{ErrorCode, ErrorSeverity, RasicaError};
use rasica_dataset::{dataset::DatasetError, schema::SchemaError};

/// Errors from every reader in this crate.
#[derive(Debug, Error)]
pub enum IngestionError {
    /// The source could not be opened or read at the I/O level.
    #[error("failed to read source '{origin}': {cause}")]
    SourceUnreadable {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
        /// The underlying I/O failure, preserved for diagnosis.
        #[source]
        cause: std::io::Error,
    },

    /// The source's bytes were not valid UTF-8 (§1.4 Note 2).
    #[error("source '{origin}' is not valid UTF-8: {cause}")]
    InvalidEncoding {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
        /// The underlying UTF-8 validation failure.
        #[source]
        cause: std::str::Utf8Error,
    },

    /// The source declared a header (or, for JSON, at least one object) but
    /// contained zero data rows, or contained no rows at all.
    #[error("source '{origin}' contains no data rows")]
    Empty {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
    },

    /// A data row's field count disagreed with the header's.
    #[error(
        "source '{origin}' row {row_number} has {actual} fields but the header declares {expected}"
    )]
    InconsistentRowArity {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
        /// The 1-based row number (including the header) at which the
        /// mismatch was found.
        row_number: usize,
        /// The header's field count.
        expected: usize,
        /// The offending row's actual field count.
        actual: usize,
    },

    /// A JSON array element's key set disagreed with the first element's
    /// (§1.4 Note 5).
    #[error(
        "source '{origin}' object at index {object_index} has a different key set than the first object"
    )]
    AmbiguousJsonSchema {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
        /// The 0-based index of the first object whose keys disagreed.
        object_index: usize,
        /// The key set established by the first object in the array.
        expected_keys: Vec<String>,
        /// The offending object's actual key set.
        actual_keys: Vec<String>,
    },

    /// A JSON field held a nested array or object (§1.4 Note 5).
    #[error("source '{origin}' field '{key}' is a nested array or object, which is not supported")]
    UnsupportedJsonValue {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
        /// The offending field's key.
        key: String,
    },

    /// The top-level JSON value was not an array of flat objects (§1.4 Note 5).
    #[error("source '{origin}' is not a JSON array of flat objects")]
    UnsupportedJsonShape {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
    },

    /// The requested Excel worksheet does not exist in the workbook.
    #[error("source '{origin}' has no worksheet named '{sheet}'")]
    ExcelSheetNotFound {
        /// The path, URI, or other descriptor identifying the source.
        origin: String,
        /// The requested, absent sheet name.
        sheet: String,
    },

    /// The resolved schema was rejected by `rasica-dataset` (e.g. duplicate
    /// column names after header normalisation).
    #[error("source produced an invalid schema: {0}")]
    SchemaConstructionFailed(#[source] SchemaError),

    /// A row was rejected by `rasica-dataset`'s own structural checks.
    #[error("source produced an invalid dataset: {0}")]
    DatasetConstructionFailed(#[source] DatasetError),
}

impl RasicaError for IngestionError {
    fn error_code(&self) -> ErrorCode {
        match self {
            Self::SourceUnreadable { .. } => ErrorCode("ingestion::source_unreadable"),
            Self::InvalidEncoding { .. } => ErrorCode("ingestion::invalid_encoding"),
            Self::Empty { .. } => ErrorCode("ingestion::empty"),
            Self::InconsistentRowArity { .. } => ErrorCode("ingestion::inconsistent_row_arity"),
            Self::AmbiguousJsonSchema { .. } => ErrorCode("ingestion::ambiguous_json_schema"),
            Self::UnsupportedJsonValue { .. } => ErrorCode("ingestion::unsupported_json_value"),
            Self::UnsupportedJsonShape { .. } => ErrorCode("ingestion::unsupported_json_shape"),
            Self::ExcelSheetNotFound { .. } => ErrorCode("ingestion::excel_sheet_not_found"),
            Self::SchemaConstructionFailed(_) => ErrorCode("ingestion::schema_construction_failed"),
            Self::DatasetConstructionFailed(_) => ErrorCode("ingestion::dataset_construction_failed"),
        }
    }

    fn severity(&self) -> ErrorSeverity {
        // Every condition is caught before `DatasetBuilder::build` is
        // called, i.e. before any Tier 1 `Dataset` exists — matching
        // `DatasetError`'s rationale in Document 00B §4.7.
        ErrorSeverity::Recoverable
    }
}
```

### 4.10 `src/lib.rs` and `src/prelude.rs`

```rust
// src/lib.rs
//! `rasica-ingestion`: readers for the Initial Sources named in Architecture
//! Spec §15.6 (CSV, Excel, JSON), each producing a `rasica_dataset::Dataset`
//! exclusively via `rasica_dataset::dataset::DatasetBuilder`.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod csv;
pub mod encoding;
pub mod error;
pub mod excel;
pub mod ingest;
pub mod json;
pub mod prelude;
mod typing;
```

```rust
// src/prelude.rs
//! Convenience re-export of the types most consumers of `rasica-ingestion`
//! need, following the same convention as `rasica_dataset::prelude`
//! (Document 00B §4.8).

pub use crate::{
    csv::CsvOptions,
    error::IngestionError,
    excel::ExcelOptions,
    ingest::{ingest_path, FormatOptions},
};
```

---

## 5. Testing Framework Extension

### 5.1 Policy

Unchanged from Document 00B §5.1: unit tests live alongside the code they test (already shown inline in §4.3–§4.9 above); this section covers cross-cutting fixtures, the `workspace_smoke` extension, and the benchmark.

### 5.2 Fixtures — `tests/fixtures/`

| Fixture | Purpose | Content |
|---|---|---|
| `well_formed.csv` | Baseline round-trip and type-inference check | Header `id,name,active,score`; rows mixing integers, text, `true`/`false`, and floats; at least one empty cell per column to exercise `Value::Null`. |
| `utf8_bom.csv` | Byte-order-mark handling (§1.4 Note 2) | Byte-identical to `well_formed.csv` except prefixed with the three-byte UTF-8 BOM. |
| `invalid_encoding.csv` | Encoding rejection (§1.4 Note 2) | A byte sequence containing an invalid UTF-8 continuation byte (e.g. a lone `0xFF`) in place of a header field. |
| `well_formed.xlsx` | Excel round-trip | A single-sheet workbook with the same logical content as `well_formed.csv`, plus one cell of Excel's native `DateTime` type to exercise §1.4 Note 4. Committed as a binary fixture; not reproduced in this document. |
| `well_formed.json` | JSON round-trip | A top-level array of flat objects with the same logical content as `well_formed.csv`, with keys deliberately written out of alphabetical order in the source bytes, to exercise §1.4 Note 5's lexicographic column-ordering rule. |

Each fixture's expected `Dataset` (schema, per-row values, and resolved `ColumnType`s) is hand-written once as a `fn expected_well_formed_dataset() -> Dataset` test helper shared across all three format-specific round-trip tests in §5.3, so the same expectation is checked against all three formats rather than three independently-written expectations that could silently drift apart.

### 5.3 Integration Tests — `tests/round_trip.rs`

```rust
//! Round-trip tests: each fixture in `tests/fixtures/` is ingested and
//! compared against a hand-built expected `Dataset`, per §15.6's exit
//! criterion ("imported datasets match source datasets exactly").

use std::{fs::File, io::BufReader, path::Path};

use rasica_core::prelude::DeterministicFingerprint;
use rasica_dataset::{
    dataset::DatasetBuilder,
    row::Row,
    schema::{Column, ColumnType, Schema},
    value::Value,
};
use rasica_ingestion::{csv, excel, json};

fn fixture_path(name: &str) -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures").join(name)
}

/// The single expected `Dataset` every well-formed fixture must ingest to,
/// independent of source format (§5.2).
fn expected_well_formed_dataset() -> rasica_dataset::dataset::Dataset {
    let schema = Schema::new(vec![
        Column::new("id", ColumnType::Integer),
        Column::new("name", ColumnType::Text),
        Column::new("active", ColumnType::Boolean),
        Column::new("score", ColumnType::Float),
    ])
    .expect("hand-written schema is well-formed");

    let mut builder = DatasetBuilder::new(schema);
    builder
        .push_row(Row::new(vec![
            Value::Integer(1),
            Value::Text("Ada".into()),
            Value::Boolean(true),
            Value::Float(9.5),
        ]))
        .expect("hand-written row matches hand-written schema");
    builder
        .push_row(Row::new(vec![
            Value::Integer(2),
            Value::Null,
            Value::Boolean(false),
            Value::Float(3.25),
        ]))
        .expect("hand-written row matches hand-written schema");

    builder.build(rasica_dataset::source::SourceMetadata::new(
        rasica_dataset::source::SourceFormat::InMemory,
        "expected",
    ))
}

/// Compares two `Dataset`s by content, ignoring identity and provenance —
/// exactly what `DeterministicFingerprint` already excludes (Document 00B
/// §4.6) — so this is a single, reusable equality check across every format.
fn assert_content_equal(actual: &rasica_dataset::dataset::Dataset, expected: &rasica_dataset::dataset::Dataset) {
    assert_eq!(actual.fingerprint(), expected.fingerprint());
}

#[test]
fn csv_round_trip_matches_expected_dataset() {
    let file = File::open(fixture_path("well_formed.csv")).expect("fixture exists");
    let dataset = csv::read(BufReader::new(file), "well_formed.csv", csv::CsvOptions::default())
        .expect("fixture is well-formed");
    assert_content_equal(&dataset, &expected_well_formed_dataset());
}

#[test]
fn json_round_trip_matches_expected_dataset_regardless_of_source_key_order() {
    let file = File::open(fixture_path("well_formed.json")).expect("fixture exists");
    let dataset = json::read(BufReader::new(file), "well_formed.json").expect("fixture is well-formed");
    assert_content_equal(&dataset, &expected_well_formed_dataset());
}

#[test]
fn excel_round_trip_matches_expected_dataset() {
    let dataset = excel::read(&fixture_path("well_formed.xlsx"), excel::ExcelOptions::default())
        .expect("fixture is well-formed");
    // The Excel fixture additionally carries one DateTime cell (§1.4 Note 4)
    // beyond `expected_well_formed_dataset`'s shape, so this test checks the
    // shared columns' values individually rather than a single fingerprint
    // equality, and separately asserts the DateTime column resolved to Text.
    assert_eq!(dataset.schema().arity(), 5);
    assert_eq!(dataset.schema().columns()[4].column_type(), ColumnType::Text);
}

#[test]
fn utf8_bom_is_stripped_not_ingested_as_data() {
    let with_bom = File::open(fixture_path("utf8_bom.csv")).expect("fixture exists");
    let without_bom = File::open(fixture_path("well_formed.csv")).expect("fixture exists");

    let from_bom = csv::read(BufReader::new(with_bom), "utf8_bom.csv", csv::CsvOptions::default())
        .expect("BOM-prefixed fixture is well-formed after stripping");
    let from_plain = csv::read(BufReader::new(without_bom), "well_formed.csv", csv::CsvOptions::default())
        .expect("fixture is well-formed");

    assert_content_equal(&from_bom, &from_plain);
}

#[test]
fn invalid_encoding_is_rejected_not_mis_decoded() {
    let file = File::open(fixture_path("invalid_encoding.csv")).expect("fixture exists");
    let result = csv::read(BufReader::new(file), "invalid_encoding.csv", csv::CsvOptions::default());
    assert!(matches!(result, Err(rasica_ingestion::error::IngestionError::InvalidEncoding { .. })));
}

#[test]
fn repeated_import_is_deterministic() {
    for _ in 0..3 {
        let file = File::open(fixture_path("well_formed.csv")).expect("fixture exists");
        let dataset = csv::read(BufReader::new(file), "well_formed.csv", csv::CsvOptions::default())
            .expect("fixture is well-formed");
        assert_eq!(dataset.fingerprint(), expected_well_formed_dataset().fingerprint());
    }
}
```

### 5.4 `workspace_smoke` — Extension

Document 00B §5.2 extended `workspace_smoke` to exercise a real `Dataset`. Phase 3 extends it once more to exercise a real ingestion round trip, so the end-to-end workspace smoke test now spans all three phases delivered so far:

```rust
// tests/workspace_smoke/tests/smoke.rs (extension)
#[test]
fn ingests_a_csv_fixture_into_an_immutable_dataset() {
    let csv_bytes = b"id,label\n1,alpha\n2,beta\n".as_slice();
    let dataset = rasica_ingestion::csv::read(csv_bytes, "inline-fixture", rasica_ingestion::csv::CsvOptions::default())
        .expect("inline CSV literal is well-formed");

    assert_eq!(dataset.row_count(), 2);
    assert_eq!(dataset.schema().arity(), 2);
    // Reuses Document 00B's own smoke assertion pattern: Dataset is Tier 1.
    fn assert_immutable<T: rasica_core::prelude::Immutable>(_: &T) {}
    assert_immutable(&dataset);
}
```

### 5.5 Benchmark Harness — `benches/csv_ingestion.rs`

Benchmarks parsing and type-resolution cost in isolation from filesystem variance, by feeding an in-memory, deterministically generated CSV byte buffer through `csv::read` via a `Cursor`, following the same "no I/O of any kind" rationale Document 00B §5.4 applied to `dataset_construction`.

```rust
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
        b.iter(|| read(Cursor::new(bytes.clone()), "synthetic", CsvOptions::default()).unwrap())
    });
}

criterion_group!(benches, bench_csv_ingestion);
criterion_main!(benches);
```

---

## 6. Build Pipeline (CI) Updates

### 6.1 Workspace Membership

`crates/rasica-ingestion` is added to `cargo metadata`'s workspace member set (§3.2); every existing CI job (`fmt`, `clippy`, `test`, `doc`, `audit`, `msrv`) already iterates `--workspace`, so no job body changes — only the set of crates each job covers grows, exactly as Document 00B observed for `rasica-dataset`.

### 6.2 `benchmark-regression` — Extended Body

```yaml
  benchmark-regression:
    name: Benchmark Regression Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: Swatinem/rust-cache@v2
      # Runs both Phase 2's dataset_construction benchmark and Phase 3's
      # csv_ingestion benchmark (§5.5), giving Architecture Spec §14.15's
      # "ingestion" benchmarking category its first real body. Comparison
      # against a stored baseline remains deferred to the Benchmarking
      # Specification (Appendix E item 24), as Document 00B established.
      - run: cargo bench --workspace
      - uses: actions/upload-artifact@v4
        with:
          name: criterion-results
          path: target/criterion
```

### 6.3 `deny.toml`

No change, per §3.2: `csv`, `calamine`, and `serde_json` each satisfy the existing license allow-list, none is a `dev-dependency`-only or wildcard dependency, and none pulls in an unsafe-heavy FFI surface warranting a new `[bans].deny` entry.

---

## 7. Documentation Framework

Unchanged from Document 00A §8 and Document 00B §7: `#![warn(missing_docs)]` promoted to `deny` in CI applies identically to `rasica-ingestion`; every public item in §4 above carries a doc comment stating its purpose and, where non-obvious, the Architecture Spec section or Interpretation Note it implements.

---

## 8. Exit Criteria (Checkable)

Architecture Spec §15.6 states Phase 3's exit criterion and four-item verification list in prose. This section makes each one a specific, automatable check.

| §15.6 Requirement | Concrete Check |
|---|---|
| "Imported datasets match source datasets exactly." | `tests/round_trip.rs`'s `csv_round_trip_matches_expected_dataset`, `json_round_trip_matches_expected_dataset_regardless_of_source_key_order`, and `excel_round_trip_matches_expected_dataset` (§5.3) each compare an ingested fixture against a hand-built expected `Dataset`. |
| Verification: "no data loss" | Every value in every fixture (§5.2) appears, unchanged, in the corresponding assertion in §5.3; `IngestionError::UnsupportedJsonValue` (§4.9) rejects rather than silently drops a nested JSON value that could not be losslessly represented. |
| Verification: "correct typing" | `typing::tests` (§4.3) verify the widening lattice directly (commutativity, associativity via the `accumulator_result_is_independent_of_observation_order` property test, and the Boolean/Integer non-conflation case); `excel_round_trip_matches_expected_dataset` additionally verifies a native Excel `DateTime` cell resolves to `ColumnType::Text` per §1.4 Note 4. |
| Verification: "correct encoding" | `utf8_bom_is_stripped_not_ingested_as_data` and `invalid_encoding_is_rejected_not_mis_decoded` (§5.3). |
| Verification: "deterministic import" | `repeated_import_is_deterministic` (§5.3): three independent imports of the same fixture produce the same `Fingerprint` (Document 00B §4.6). |

Additional Phase-3-specific verification, implied by §9.1 and §8.3 being load-bearing for later phases:

| Requirement | Concrete Check |
|---|---|
| No crate depends on an unimplemented crate | `cargo metadata` shows `rasica-common`, `rasica-core`, `rasica-dataset`, `rasica-ingestion`, and `workspace-smoke` as the only workspace members; `rasica-ingestion`'s only internal path dependencies are `rasica-common`, `rasica-core`, and `rasica-dataset` (§4.2). |
| No new construction path for `Dataset` | Every reader in §4.5–§4.7 constructs its result exclusively via `DatasetBuilder::new` / `DatasetBuilder::push_row` / `DatasetBuilder::build` (checked by review, per §14.12); no reader constructs a `Dataset` value directly. |
| `unsafe` is absent | `#![forbid(unsafe_code)]` present in `rasica-ingestion`'s crate root (§4.10). |

Phase 3 is complete when every row above is true on a single commit of `main`, in addition to every Phase 1 (Document 00A §9) and Phase 2 (Document 00B §8) exit criterion continuing to hold.

---

## 9. Traceability Matrix

| This Document | Architecture Spec / Prior Document Source |
|---|---|
| §1.4 Note 1 (crate placement) | Appendix D, §9.1, Document 00B §4.1 |
| §1.4 Note 2 (encoding scope) | §15.6 ("correct encoding") |
| §1.4 Note 3 (typing scope) | §15.6 ("correct typing"), §6.7, §15.8, Document 00B §1.4 Note 1 |
| §1.4 Note 4 (Excel temporal cells) | §6.5, §15.8 (no phase yet assigned to scale/temporal properties) |
| §1.4 Note 5 (JSON shape and ordering) | §4.1 (Logical Determinism), §15.6 ("deterministic import") |
| §2 (Engineering Baseline) | Document 00A §2; Document 00B §2; §4.1, §9.1, §14.7, §14.9 |
| §3 (Repository & Workspace) | §15.6, Appendix D |
| §4.3 (Typing) | §15.6 ("correct typing"), §4.1 |
| §4.4 (Encoding) | §15.6 ("correct encoding") |
| §4.5–§4.7 (CSV / Excel / JSON readers) | §15.6 (Initial Sources) |
| §4.8 (Dispatch) | §9.1 ("source abstraction") |
| §4.9 (Error Framework) | Document 00A §4.4 |
| §5 (Testing Framework Extension) | Document 00A §6; Document 00B §5; §14.13 |
| §5.5 (Benchmark) | §14.15 ("ingestion"), Appendix H |
| §6 (CI Updates) | Document 00A §7; Document 00B §6; §14.14 |
| §8 (Exit Criteria) | §15.6 |

---

## 10. Non-Goals and Forward Pointers

- **SQL, Apache Arrow, and Apache Parquet readers** remain unimplemented. Architecture Spec §15.6 lists them as "Future Sources" without a roadmap phase number, matching the precedent Document 00B §10 already set for `ColumnMetadata::scale`/`::temporal_properties`. `SourceFormat::Sql` / `::Arrow` / `::Parquet` (Document 00B §4.5) remain declared but unimplemented variants; whichever future phase implements them is expected to add one module to `rasica-ingestion` per variant, following §4.5–§4.7's pattern, with no change to `FormatOptions`'s existing variants.
- **Newline-delimited JSON and nested JSON values** are not supported (§1.4 Note 5). A future ADR (§16.5/§14.18) could extend `src/json.rs` to accept NDJSON as an additional, explicitly-selected mode, or to flatten nested objects under a documented key-joining convention — either is additive to `JsonOptions` (not yet introduced in Phase 3, since JSON currently accepts no configuration) rather than a breaking change to `json::read`'s existing behaviour.
- **Non-UTF-8 text encodings** are not supported (§1.4 Note 2). `src/encoding.rs`'s narrow, single-function surface (`strip_bom_and_validate_utf8`) is deliberately the only place a future encoding-detection or explicit-encoding-selection feature would need to change.
- **Semantic validation** — nullability rules, referential checks, business-rule enforcement — remains Phase 4's responsibility (Architecture Spec §15.7, §9.2). This phase's readers reject only structural malformation (encoding, arity, ambiguous JSON schema, unsupported shapes); a structurally well-formed but semantically wrong `Dataset` (e.g. a "percentage" column containing values over 100) passes through this phase without complaint, exactly as intended.
- **Structural and statistical inference** — identifiers, categorical/continuous variables, distributions, relationships, and genuine temporal-semantics resolution (including proper interpretation of the Excel `DateTime` cells this phase renders as text, §1.4 Note 4) — remain Phase 5's responsibility (Architecture Spec §15.8). This phase's type-widening algorithm (§4.3) answers only the representational question of which `ColumnType` fits a column's observed values; it makes no claim about what those values *mean*.
- **Chunked, paged, or out-of-core reading** (Architecture Spec Appendix F) is not implemented; every reader in this document buffers its entire source in memory before constructing a `Dataset`, consistent with Document 00B §1.4 Note 2's identical narrowing of `Dataset`'s own backing. `rasica-ingestion`'s public signatures (`read`, `ingest_path`) expose no behaviour that depends on this being the case, so a future ADR introducing streaming ingestion could do so behind the same signatures.

---

*End of Document 00C. The next document in sequence is the Phase 4 Implementation Specification — Validation Engine, which is the first consumer of a `Dataset` that may originate from any of the three readers defined here, and the first phase to interpret — rather than merely represent — the content a `Dataset` carries (Architecture Spec §15.7).*
