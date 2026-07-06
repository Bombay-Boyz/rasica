# 00F — Phase 6: Knowledge Engine — Implementation Specification

> **Status note (not present in Documents 00A/00B/00C).** This document was drafted by an AI assistant at the user's request, directly from Architecture Specification `rasica-v2.md` §6.8 ("Knowledge Graph"), §8.3 ("Core Dependency Graph"), §8.4 ("Domain Module Dependencies"), §9.4 ("Knowledge Engine"), §10.2–§10.10 ("Knowledge and Reasoning Model"), §10.11A/§10.14A (Rule Engine evaluation and indexing requirements, which constrain what the Knowledge Graph must expose even though the Rule Engine itself is a later phase), §11.9–§11.13 (Domain Activation and Domain Knowledge Contribution), and §15.9 ("Phase 6 — Knowledge Engine"). Like Document 00E (Phase 5) and unlike Documents 00A/00B/00C/00D, no human-authored companion "07 Knowledge Engine Specification" (referenced in Appendix E but not supplied to the assistant) was available as a source, and no scaffold script for this phase exists yet. Every design decision below that goes beyond what the Architecture Specification states outright is flagged inline as a **[DRAFT DECISION]** and should be reviewed and either ratified or revised before treating this document as authoritative in the same sense as 00A/00B/00C/00D.

---

## 0. Prerequisite: Phase 5's actual (scaffolded) state, and the one gap it left open

> **Revision note.** This section originally speculated about two gaps in Document 00E's *design* before Phase 5 had a real scaffold script. `setup_rasica_phase5.sh` (the actual, already-generated `rasica-structural-inference` crate) has since been reviewed directly. One of the two originally-speculated gaps did not exist in the real code; the other did, and has now been patched at the source (in `setup_rasica_phase5.sh` and, if already run, `crates/rasica-structural-inference/src/knowledge.rs`) rather than worked around here. This section is rewritten to describe the real crate, not the hypothetical one.

Per §8.3's Core Dependency Graph, the pipeline order is:

```
Dataset Engine → Validation Engine → Structural Inference Engine → Structural Knowledge ─┐
                                                                                          ├─► Knowledge Graph
                                                              Domain Facts (Phase 9, deferred) ─┘
```

**Accessors: not a gap.** `StructuralKnowledge`, `ColumnKnowledge`, `RelationshipEvidence`, and `ColumnRef` all have full public accessors in the actual scaffolded crate (`origin()`, `columns()`, `column(index)`, `relationships()`; `role()`, `distribution()`, `categories()`; `left()`, `right()`, `kind()`; `column_position()`). No change was needed here.

**No `Id<DatasetMarker>`/`Identifiable` pattern exists anywhere in this workspace.** The actual `setup_rasica_phase4.sh` (Validation Engine) never exercises `rasica_common::Id<T>`/`Identifiable` at all: `ValidationReport` carries a plain caller-supplied `origin: String` instead of a Dataset identity handle, "for exactly the same 'architecturally independent, must not assume a provenance-recording convention beyond `rasica-dataset` itself' reason." Phase 5 follows the same precedent — `StructuralKnowledge::origin() -> &str` and `ColumnRef` carries `column_position` alone, with **no `dataset_id` field anywhere**. This document's earlier draft assumed `Id<DatasetMarker>` throughout (`EntityOrigin::StructuralColumn`'s `dataset_id` field, `KnowledgeGraph::dataset_id`, an `IntegrationError::DatasetMismatch` variant); **all of that is revised below (§4.1, §4.5, §6) to drop `Id<DatasetMarker>` entirely** and follow the workspace's actual `origin: String` convention instead.

**The one real gap: column names.** Per the actual `relationship.rs`, `ColumnRef` identifies a column **only by position** — "Identifies one column within the Dataset being inferred over, by position," with an explicit code comment noting it deliberately does *not* also carry a Dataset identity handle. Column *names* were absent from `ColumnKnowledge` entirely in the original scaffold; the existing `tests/accuracy.rs` worked around this by re-zipping `dataset.schema().columns()` against `knowledge.column(index)` itself, at the call site, rather than the crate exposing the name.

**Fix applied.** Rather than have `integrate` (§6) take the original `Dataset` as a second, separately-supplied argument (inviting a `Dataset`/`StructuralKnowledge` mismatch this crate would then have to detect and reject), `ColumnKnowledge` now carries `name: String` directly, populated in `infer()` from `column.name()` at the point each column is classified. This is a three-spot patch to `crates/rasica-structural-inference/src/knowledge.rs` (add the field, add the `name()` accessor, thread `column.name()` through the one call site in `infer`'s loop) — see the accompanying patched `setup_rasica_phase5.sh` and the change log below. It does **not** violate §4.1's "column names are never consulted by any heuristic" constraint: `role.rs`'s classification heuristics still see only declared type and values, and `name` is attached to the already-computed `ColumnKnowledge` after classification has finished — storing a fact is not the same as an heuristic consulting it.

### Change log applied to Phase 5

| File | Change | Downstream effect |
| --- | --- | --- |
| `src/knowledge.rs` | `ColumnKnowledge` gains `name: String`; `ColumnKnowledge::new` gains a leading `name: impl Into<String>` parameter; new `pub fn name(&self) -> &str` accessor. | `ColumnKnowledge::new` is a private `fn` with exactly one call site (inside `infer`, same file) — no external crate or test constructs it directly, so this is not a breaking change to any consumer. |
| `src/knowledge.rs` | `infer`'s per-column loop passes `column.name()` (already in scope as the loop binds `(index, column)` from `schema.columns().iter().enumerate()`) into `ColumnKnowledge::new`. | No new borrow or allocation beyond the `String` clone `.into()` already performs; no change to `infer`'s signature, error type, or determinism properties — `name` is deterministic (schema order is fixed) so `PartialEq`/fingerprint comparisons remain sound. |
| `tests/knowledge.rs` (unit tests) | One new test, `column_knowledge_carries_the_schema_column_name`, asserting `column(0).name() == "col"`. | Additive only. |
| `tests/accuracy.rs` | **No change required.** It already zips `schema.columns()` against `knowledge.column(index)` itself; it can optionally be simplified to read `knowledge.column(index).name()` directly instead of `column.name()` from the schema, but both now return the same value, so this is cosmetic, not a fix. |
| `benches/structural_inference.rs` | **No change required** — does not construct `ColumnKnowledge` directly. |
| `src/relationship.rs`, `src/role.rs`, `src/distribution.rs`, `src/category.rs`, `src/dataset_view.rs`, `src/error.rs`, `src/lib.rs`, `src/prelude.rs`, `Cargo.toml` | **No change required.** | — |

No other file in the scaffold constructs `ColumnKnowledge` or destructures its fields directly, so this patch is fully contained to `src/knowledge.rs`, and Phase 5's own exit criteria (Document 00E §9 / the accuracy and determinism tests) are unaffected: `name` is deterministic, doesn't participate in any classification decision, and every existing test still passes unmodified.

### Consequence for this document (Phase 6)

Because column names are now available directly from `StructuralKnowledge::columns()[i].name()`, **`integrate` (§6) no longer needs the original `Dataset` as a parameter at all**, and `rasica-knowledge` no longer needs a compile-time dependency on `rasica-dataset` for name resolution. This removes an entire class of problem the original draft of this section introduced (a caller passing a `Dataset` that doesn't correspond to the `StructuralKnowledge` it's paired with) rather than merely working around it. §4.1, §4.5, §6, and §8 below are revised accordingly.

The rest of this document proceeds on the basis that Phase 5's crate includes the `name` field described above, and that it compiles and passes its own exit criteria (Document 00E §9, plus the new name-accessor test) before Phase 6's own code is written.

---

## 1. Objective

Per §15.9:

> Construct the Knowledge Graph.

Per §6.8:

> The Knowledge Graph is the central semantic representation of RASICA. ... Unlike Metadata, which describes isolated characteristics, the Knowledge Graph describes how objects relate to one another.

Per §10.6:

> Every discovered entity becomes a node. Every relationship becomes an edge. ... The graph stores facts. It performs no reasoning.

Per §9.4, the Knowledge Engine's responsibilities are: integrating Structural Knowledge, integrating Domain Facts, resolving relationships, and maintaining semantic consistency. The third sentence of §10.6 is the load-bearing constraint for this entire phase, mirroring Document 00E's own "no interpretation" boundary one layer up: this crate assembles and indexes facts, it never evaluates them (that is the Rule Engine, Phase 8, §10.11A).

### 1.1 Deliverables (§15.9)

- entity graph,
- relationship graph,
- semantic graph.

**[DRAFT DECISION]** As with Document 00E folding six §6.7 deliverables into one `StructuralKnowledge` type, this document folds these three deliverables into one `KnowledgeGraph` type (§4.5): "entity graph" and "relationship graph" are the `entities`/`facts` collections and their indexes (§4.5), and "semantic graph" is not a fourth, separate structure but the same graph considered as a whole — the entities-plus-relational-facts structure *is* the semantic graph §6.8/§10.6 describe. This is a naming/structuring decision, not an omission of any deliverable.

### 1.2 Exit criterion (§15.9)

> Knowledge graphs generated deterministically. ... Identical datasets generate identical Knowledge Graphs.

Unlike Document 00E's equivalent criterion (Phase 5's unquantified "expected accuracy," which required a **[DRAFT DECISION]** threshold), §15.9's criterion is already exact enough to test directly, in the same way Document 00D's fault-injection criterion was: two independently-constructed but logically-identical `Dataset`s (e.g. one read from CSV, one from JSON, per Document 00C's own round-trip precedent) **shall** produce `KnowledgeGraph` values with equal `DeterministicFingerprint` output. §7 below specifies this test directly.

**[DRAFT DECISION extension]** §15.9's own exit criterion does not mention performance, but §10.14A imposes an additional, non-optional requirement specifically on this phase's output: the Knowledge Graph "shall provide indexed lookup by fact type and by entity name with average-case complexity no worse than O(log n)... linear full-graph scans per Rule condition are prohibited." Because this requirement exists to protect a *later* phase (the Rule Engine, Phase 8) from a scalability regression that would otherwise only surface once that phase is built, this document treats it as a first-class exit criterion for Phase 6 (§9), not an optional nicety — it is far cheaper to guarantee by construction now (§4.5) than to retrofit once Rule Engine code already assumes it.

---

## 2. Scope

### 2.1 In scope

- A new crate, `rasica-knowledge`, whose single public entry point, `integrate`, consumes an existing `rasica_structural_inference::knowledge::StructuralKnowledge` — which, per §0, already carries each column's `name` and the dataset's `origin` string directly, so no separate `Dataset` argument is needed — and a slice of `DomainFact` values (§4.6; empty in every real invocation until Phase 9 exists), and produces an immutable `KnowledgeGraph`.
- `Entity` nodes, one per `Dataset` column, labelled from `StructuralKnowledge::columns()[i].name()` (§0).
- `Fact` values (§10.11A's "immutable, typed, addressable statement"), both non-relational (e.g. `HasNumericColumn`) and relational (a `Fact` with an `object`, i.e. a graph edge, per §6.8's worked examples), derived deterministically from `StructuralKnowledge`.
- A `DerivationStrength` classification for every `Fact` (§10.7's "Explainable" principle), replacing any notion of confidence or probability, consistent with the same [2.1] revision that removed "Confidence Evaluation" from §11.10.
- Indexed lookup by fact type and by entity label, satisfying §10.14A.
- The **interface** (`DomainFact`, and the integration algorithm's handling of it) that Domain Modules will populate starting at Phase 9 — exercised in this phase's own tests only with a fixed, hand-written `&[DomainFact]` fixture, never with a real Domain Module, since none exists yet. This mirrors Document 00E's own posture toward Phase 4 (§0 there): building to a stable, specified interface without waiting for the producer of that interface's input to exist.
- A determinism test harness verifying §1.2, and a construction-level (not benchmark-level) verification of §10.14A's indexing requirement.

### 2.2 Out of scope (deferred to later phases or explicitly excluded by §6.8/§10.6)

- **Domain Facts' actual production.** Producing a real `DomainFact` value requires a Domain Module, which requires the Domain Framework — Phase 9 (§11, §15.12). Per §8.4's Domain Module Dependencies table, Domain Modules depend on Knowledge interfaces, never the reverse, so `rasica-knowledge` cannot depend on a (nonexistent) `rasica-domain-sdk` crate to borrow its types. This document therefore defines `DomainFact` itself (§4.6), as a small, closed vocabulary sufficient for §6.9's and §11.13's worked examples; Phase 9's Domain SDK Specification (Appendix E item 10) is expected to adopt this shape or, if it must diverge, backport the change here — the same "divergence must be backported" discipline Appendix G's Type Authority Policy already establishes for Appendix G itself.
- **Rule evaluation.** §10.6: "The graph stores facts. It performs no reasoning." Reasoning over the fact base is the Rule Engine's job (Phase 8, §9.6, §10.11A) — this crate's job ends at making the fact base *available*, indexed, per §10.14A.
- **Capability discovery.** A separate registry (`Capability Registry`, §6.10, §9.5) built *from* the Knowledge Graph in Phase 7, not part of it. `KnowledgeGraph` exposes read access sufficient for Phase 7 to query it, but does not itself compute or store capabilities.
- **Resolving apparent contradictions between Domain Facts.** §11.11 states plainly that Domain Facts remain Tier 1 (Immutable) and "no Domain Module may suppress another module's contributed knowledge" — only *rule-derived recommendations* built from that knowledge are later resolved, and only by the Rule Engine's declared `Suppresses` relation (§10.11A), never by this crate. `integrate` may therefore produce a `KnowledgeGraph` containing two facts that look contradictory to a human reader without adjudicating between them; this is the architecturally correct outcome, not a defect.
- **Inventing semantic relationship labels.** §6.8's worked example (`Revenue --generated_by--> Customer`) uses a semantic predicate (`generated_by`) that only a Domain Module may assert (§6.9). A relational `Fact` derived purely from `StructuralKnowledge`'s `RelationshipEvidence` (§5.4) is never labelled with an invented semantic predicate; it carries the honestly-scoped, mechanically-derived label Document 00E's own `RelationshipKind` already provides (`"value_subset"`), and nothing more, until a Domain Module later asserts a semantic predicate over the same pair of entities (Phase 9+, §5.5 below).

---

## 3. Crate layout

```
crates/rasica-knowledge/
├── Cargo.toml
├── src/
│   ├── lib.rs
│   ├── entity.rs           # Entity, EntityId, EntityOrigin
│   ├── fact.rs             # FactType, Fact, FactId, DerivationStrength, FactOrigin, RelationshipRef
│   ├── domain_fact.rs      # DomainFact — the Phase 9 integration interface, unused by any producer yet
│   ├── graph.rs            # KnowledgeGraph (Tier 1) and integrate()
│   ├── error.rs
│   └── prelude.rs
├── benches/
│   └── knowledge_graph.rs
└── tests/
    ├── fixtures/
    │   ├── customers.csv               # reuses Document 00E §7.1's fixture
    │   ├── sensor_readings.csv         # reuses Document 00E §7.1's fixture
    │   └── domain_facts_fixture.json   # hand-written DomainFact values, §7.2
    └── determinism.rs
```

This mirrors Documents 00A–00E's convention: one crate per phase, a `prelude.rs` re-exporting the consumer-facing surface, and fixture-driven integration tests. Reusing Document 00E's own fixtures (rather than inventing new ones) keeps the two phases' test data consistent, and lets `tests/determinism.rs` exercise the exact `StructuralKnowledge` shapes Document 00E's own accuracy test already validated.

---

## 4. Core types

### 4.1 `EntityId` and `Entity`

```rust
//! crates/rasica-knowledge/src/entity.rs

/// Marker type for entity identifiers (§0, gap 1's accessor convention;
/// `rasica_common::Id<T>` pattern per Document 00A §4.3.1).
pub struct EntityMarker;
pub type EntityId = rasica_common::Id<EntityMarker>;

/// One node in the Knowledge Graph (§6.8, §10.6): a single discovered
/// object the analytical process reasons about.
///
/// `EntityId` is assigned by [`crate::graph::integrate`] using
/// [`rasica_common::Id::new`] (random, per Document 00A §4.3.1's
/// rationale: identity does not participate in Logical Determinism,
/// content does) — see §4.7 below for how `KnowledgeGraph`'s
/// `DeterministicFingerprint` implementation excludes raw `EntityId`
/// bytes from its fingerprinted content for exactly this reason.
#[derive(Debug, Clone, PartialEq)]
pub struct Entity {
    id: EntityId,
    /// Human-legible label. For a `StructuralColumn` entity, this is the
    /// corresponding `ColumnKnowledge::name()` on `structural` (§0) — never a
    /// synthesized "column N" placeholder.
    label: String,
    origin: EntityOrigin,
}

/// How an `Entity` came to exist in the graph (§10.7's "Explainable"
/// principle: "every relationship must identify origin" — extended here
/// to entities themselves, for the same auditability reason).
///
/// **[DRAFT DECISION — revised, §0.]** No `Id<DatasetMarker>`/
/// `Identifiable` pattern exists anywhere in this workspace (§0: Phase 4
/// and Phase 5 both use a plain `origin: String` instead). `StructuralColumn`
/// therefore carries `column_position` alone, matching `ColumnRef`'s own
/// choice in the actual `rasica-structural-inference` crate, rather than
/// an unconfirmed `Id<DatasetMarker>` this crate would be the first to
/// introduce.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EntityOrigin {
    /// This entity corresponds 1:1 with one column of the `Dataset`
    /// `structural` (§6) was inferred from (the only entity-construction
    /// path this phase actually exercises; see §5.2). There is exactly
    /// one `Dataset` in scope per `integrate` call, so `column_position`
    /// alone is unambiguous — no dataset identity handle is needed.
    StructuralColumn { column_position: usize },
    /// **[DRAFT DECISION — reserved, unexercised until Phase 9.]** A
    /// Domain Module asserted this entity's existence directly (§6.9's
    /// `Customer`, `Machine`, `Experiment` examples — entities with no
    /// 1:1 column correspondence). `contributor` is the domain module's
    /// human-readable identifier as a plain `String` rather than a
    /// strongly-typed `DomainModuleId`, since no `rasica-domain-sdk`
    /// crate exists yet for this crate to borrow that marker type from
    /// without creating the circular dependency §8.4 forbids; Phase 9
    /// should promote this to `rasica_common::Id<DomainModuleMarker>`
    /// once that marker type has a home (most naturally in
    /// `rasica-common` itself, so both this crate and the future Domain
    /// SDK crate can depend on it without depending on each other).
    DomainAsserted { contributor: String },
}
```

### 4.2 `FactType`

```rust
//! crates/rasica-knowledge/src/fact.rs

/// A stable, extensible fact-type identifier (§10.11A step 1: "every
/// fact is an immutable, typed, addressable statement," worked examples
/// `HasNumericColumn("Revenue")`, `HasTemporalColumn("Date")`,
/// `EntityRelationship("Revenue", "generated_by", "Customer")`).
///
/// **[DRAFT DECISION]** Represented as a newtype over an interned
/// `String` rather than a closed Rust enum. §10.11A step 2 and §11.11
/// require Domain Modules (Phase 9+) to contribute Rules that read and
/// produce fact types this crate cannot enumerate at compile time,
/// merged into "one fact-type dependency graph" regardless of which
/// Domain Module contributed which type — impossible if `FactType` were
/// a closed enum only this crate could extend. This is the same
/// open-vocabulary posture Document 00D took for `ValidationConstraint`
/// (§4.6 there), applied to fact types instead of constraints.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct FactType(String);

impl FactType {
    /// Constructs a fact type from its stable name.
    #[must_use]
    pub fn new(name: impl Into<String>) -> Self {
        Self(name.into())
    }

    #[must_use]
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// The fact types this crate itself produces from `StructuralKnowledge`
/// (§5.3). These constants are this crate's own contribution to the
/// open vocabulary `FactType` represents — not an exhaustive list of
/// every fact type the platform will ever see; Domain Modules (Phase 9+)
/// and the Rule Engine (Phase 8) may introduce further values via
/// `FactType::new` without modifying this crate.
impl FactType {
    #[must_use] pub fn has_identifier_column() -> Self { Self::new("HasIdentifierColumn") }
    #[must_use] pub fn has_numeric_column() -> Self { Self::new("HasNumericColumn") }
    #[must_use] pub fn has_categorical_column() -> Self { Self::new("HasCategoricalColumn") }
    #[must_use] pub fn has_temporal_column() -> Self { Self::new("HasTemporalColumn") }
    #[must_use] pub fn entity_relationship() -> Self { Self::new("EntityRelationship") }
}
```

### 4.3 `DerivationStrength` and `FactOrigin`

```rust
/// §10.7's "Explainable" principle, made concrete: every relationship
/// (and, in this document, every `Fact`) identifies a deterministic
/// derivation strength — never a probability or confidence percentage,
/// per the same [2.1] revision that renamed §11.10's "Confidence
/// Evaluation" to "Applicability Scoring."
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DerivationStrength {
    /// Derived from an exact, non-thresholded structural check with no
    /// tolerance for error — e.g. Document 00E §5.2's Identifier check
    /// (`distinct_count == non_null_count`, an equality, not a
    /// threshold).
    StructurallyCertain,
    /// Asserted by a Domain Module (§6.9) — trusted as contributed
    /// knowledge, never independently re-derived or second-guessed by
    /// the Core Engine (§11.13: "Domain Modules contribute knowledge
    /// only").
    DomainAsserted,
    /// Derived from a heuristic that admits a tolerance or a threshold
    /// choice — e.g. Document 00E §5.3's continuous/categorical
    /// distinct-count cutoff, §5.5's 90% temporal parse-success
    /// threshold, or §5.7's relationship-evidence subset check.
    /// Mechanically checkable and fully deterministic, but not a
    /// certainty in the same sense as `StructurallyCertain`.
    Inferred,
}

/// Where a `Fact` came from, for audit purposes (§10.7: "contributing
/// rules, contributing metadata").
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FactOrigin {
    StructuralInference,
    /// **[DRAFT DECISION — reserved, unexercised until Phase 9.]** See
    /// `EntityOrigin::DomainAsserted`'s note on `contributor`'s type.
    Domain { contributor: String },
}
```

### 4.4 `Fact`

```rust
pub struct FactMarker;
pub type FactId = rasica_common::Id<FactMarker>;

/// One immutable, typed, addressable statement in the fact base
/// (§10.11A step 1), derived from either `StructuralKnowledge` (§5.3,
/// §5.4) or a `DomainFact` (§5.5).
///
/// A `Fact` whose `object` is `Some` **is** a graph edge in the sense of
/// §6.8's worked examples; there is deliberately no second, separate
/// "edge" storage location duplicating the same information — see
/// `RelationshipRef` below, and `KnowledgeGraph::relationships` (§4.5),
/// which is a non-owning view over exactly this field.
#[derive(Debug, Clone, PartialEq)]
pub struct Fact {
    id: FactId,
    fact_type: crate::fact::FactType,
    /// The entity this fact is about.
    subject: crate::entity::EntityId,
    /// Present only for relational facts (graph edges).
    object: Option<crate::entity::EntityId>,
    /// The specific predicate text for a relational fact — e.g.
    /// `"value_subset"` (Document 00E's `RelationshipKind::ValueSubset`,
    /// §2.2's "honestly-scoped" label) or, once Phase 9 exists,
    /// `"generated_by"` from an asserted `DomainFact::Relationship`.
    /// `None` for non-relational facts (e.g. `HasNumericColumn`, which
    /// needs no further qualification).
    label: Option<String>,
    derivation: crate::fact::DerivationStrength,
    origin: crate::fact::FactOrigin,
}

/// A non-owning, ergonomic view of one relational `Fact` as a graph
/// edge, for traversal code that wants entity references rather than
/// raw `EntityId`s. Constructed only by `KnowledgeGraph::relationships`
/// (§4.5); never stored.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RelationshipRef<'a> {
    pub subject: &'a crate::entity::Entity,
    pub predicate_type: &'a crate::fact::FactType,
    pub predicate_label: Option<&'a str>,
    pub object: &'a crate::entity::Entity,
    pub derivation: crate::fact::DerivationStrength,
}
```

### 4.5 `KnowledgeGraph`

```rust
//! crates/rasica-knowledge/src/graph.rs

use rasica_core::prelude::Immutable;

/// The Knowledge Graph Core Architectural Object (§6.8, §10.6, §6.2A):
/// Tier 1 — Immutable. Constructed exclusively by [`integrate`], never
/// mutated afterward — a later Domain Module activation that contributes
/// new `DomainFact`s (once Phase 9 exists) would call `integrate` again
/// to construct a *new* `KnowledgeGraph`, mirroring Document 00B §4.5's
/// `Metadata::derive` precedent and Document 00E §4.5's note about
/// `StructuralKnowledge` exactly.
#[derive(Debug, Clone, PartialEq)]
pub struct KnowledgeGraph {
    /// Carried through unchanged from `StructuralKnowledge::origin()`
    /// (§0) — the same caller-supplied provenance tag Phase 4/Phase 5
    /// already use in place of a Dataset identity handle.
    origin: String,
    entities: Vec<crate::entity::Entity>,
    facts: Vec<crate::fact::Fact>,

    // --- Indexes required by §10.14A ---
    //
    // `BTreeMap`, not `HashMap`, for two independent reasons:
    //
    // 1. Determinism (§10.7: "identical datasets shall generate
    //    identical graphs"). This document reads that requirement as
    //    extending to *iteration order*, not merely logical content —
    //    `HashMap`'s iteration order is unspecified and randomised per
    //    process by default, which would make two structurally-identical
    //    `KnowledgeGraph`s produce different `DeterministicFingerprint`
    //    byte sequences unless carefully sorted at fingerprint time
    //    regardless. Using an ordered map avoids needing to re-sort at
    //    every point of use.
    // 2. Complexity (§10.14A: "average-case complexity no worse than
    //    O(log n)... linear full-graph scans... prohibited"). `BTreeMap`
    //    lookup is O(log n) *worst-case*, satisfying §10.14A's bound with
    //    a stronger guarantee than the "average-case" floor it sets.
    by_fact_type: std::collections::BTreeMap<crate::fact::FactType, Vec<crate::fact::FactId>>,
    by_entity_label: std::collections::BTreeMap<String, crate::entity::EntityId>,
}

impl Immutable for KnowledgeGraph {}

impl KnowledgeGraph {
    /// §10.14A indexed lookup by fact type: O(log n) to locate the
    /// bucket, plus O(k) to return its k members — never a scan of
    /// `facts` as a whole.
    #[must_use]
    pub fn facts_of_type(&self, fact_type: &crate::fact::FactType) -> Vec<&crate::fact::Fact> {
        // Implementation: look up `fact_type` in `by_fact_type`, map each
        // `FactId` to its `Fact` via a second small index (an
        // `id -> position` `BTreeMap`, elided here) rather than a linear
        // `facts.iter().find(...)`, to keep this lookup O(log n) too.
        todo!()
    }

    /// §10.14A indexed lookup by entity label.
    #[must_use]
    pub fn entity_by_label(&self, label: &str) -> Option<&crate::entity::Entity> {
        todo!()
    }

    /// Every relational `Fact` (§4.4), exposed as `RelationshipRef`
    /// graph edges (§6.8's worked examples).
    #[must_use]
    pub fn relationships(&self) -> Vec<crate::fact::RelationshipRef<'_>> {
        todo!()
    }

    /// Every entity, in the deterministic order established at
    /// construction (§5.6) — schema column order, then any
    /// Domain-asserted entities in the sorted order §5.6 specifies.
    #[must_use]
    pub fn entities(&self) -> &[crate::entity::Entity] {
        &self.entities
    }
}
```

### 4.6 `DomainFact` — the Phase 9 integration interface

```rust
//! crates/rasica-knowledge/src/domain_fact.rs

/// The shape a Domain Module's contributed knowledge (§6.9, Appendix G's
/// `DomainModule::contribute_knowledge -> Vec<DomainFact>`) must take to
/// be integrated into a `KnowledgeGraph`. Defined **here**, not in a
/// `rasica-domain-sdk` crate, per §8.4's stated dependency direction:
/// Domain Modules depend on Knowledge interfaces, never the reverse — so
/// this crate must own `DomainFact`'s definition even though no producer
/// of it exists until Phase 9.
///
/// **[DRAFT DECISION]** A minimal, closed vocabulary sufficient for
/// §6.9's and §11.13's worked examples (entities, metrics, dimensions,
/// relationships — the first three folding naturally into `Entity`,
/// §5.5), not a commitment to Phase 9's eventual full Domain SDK
/// contract. Per the Type Authority Policy precedent (Appendix G),
/// Phase 9's Domain SDK Specification should adopt this shape verbatim
/// where possible, and backport any necessary divergence here.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum DomainFact {
    /// A named entity with no 1:1 correspondence to a `Dataset` column
    /// (§11.13: `Customer`, `Supplier`, `Product`).
    Entity { label: String, contributor: String },
    /// A named relationship between two entities, matched by label
    /// against entities already present in the graph (§5.5) — either
    /// `StructuralColumn` entities or other `DomainFact::Entity` values
    /// processed earlier in the same `integrate` call (§11.13: "Product
    /// belongs to Category").
    Relationship {
        subject_label: String,
        predicate: String,
        object_label: String,
        contributor: String,
    },
}
```

---

## 5. The integration algorithm

Each step below is a **total, deterministic function** of `(structural, domain_facts)` — no step depends on wall-clock time, random state, or iteration order over a `HashMap`, consistent with the same determinism discipline Document 00E's §5 heuristics and Document 00A's `DeterministicFingerprint` contract both require.

### 5.1 Ordering and determinism

1. Resolve column entities (§5.2).
2. Derive non-relational structural facts (§5.3).
3. Derive relational structural facts from `RelationshipEvidence` (§5.4).
4. Integrate `domain_facts`, sorted first (§5.5, §5.6).
5. Build the `by_fact_type`/`by_entity_label` indexes (§4.5) from the completed `entities`/`facts` vectors.

This is a fixed pipeline, not a scoring competition (mirroring Document 00E §5.1's "decision list, not scoring competition" framing) — each step's output is fully determined by the previous steps' output plus the original input, with no step revisiting or mutating an earlier step's result (consistent with Tier 1 immutability applying to the *object under construction* as much as to the finished `KnowledgeGraph`).

### 5.2 Column entities

For each `(position, column_knowledge)` in `structural.columns().iter().enumerate()` (§0: `ColumnKnowledge` now carries `name` directly, so this step reads solely from `structural` — there is no separate `Dataset` argument to zip against): construct one `Entity` with `label: column_knowledge.name().to_string()` and `origin: EntityOrigin::StructuralColumn { column_position: position }`, matching §4.1's actual field list, which carries no `dataset_id` (§0: no such field exists anywhere in this workspace). Every column becomes an entity regardless of its `VariableRole` — including `Unclassified` columns (Document 00E §5.6: "a legitimate, non-error outcome"), since even an unclassified column is a real, nameable thing in the dataset; only the *facts* asserted about it (§5.3) are role-dependent.

### 5.3 Structural facts (non-relational)

For each column entity, based on `structural.columns()[position].role()`:

| `VariableRole` (Document 00E §4.1) | `FactType` produced | `DerivationStrength` |
| --- | --- | --- |
| `Identifier` | `has_identifier_column()` | `StructurallyCertain` (exact uniqueness check, §5.2 of 00E) |
| `Continuous` | `has_numeric_column()` | `Inferred` (thresholded, §5.3 of 00E) |
| `Categorical` | `has_categorical_column()` | `Inferred` (residual/thresholded, §5.4 of 00E) |
| `Temporal` | `has_temporal_column()` | `Inferred` (90% parse threshold, §5.5 of 00E) |
| `Unclassified` | *(no fact produced)* | — |

**[DRAFT DECISION]** The certain/inferred split above is this document's own classification, not stated by the Architecture Specification; it follows directly from which of Document 00E's own heuristics involve a tolerance (§5.3, §5.4, §5.5 of 00E all name explicit thresholds) versus an exact check (§5.2 of 00E's uniqueness equality). `Unclassified` produces no fact at all — there is nothing true to assert about a column beyond "it exists" (already captured by the entity itself), and asserting `HasUnclassifiedColumn` would be a fact no Rule (Phase 8) has any stated use for per §10.12's worked examples.

### 5.4 Relational facts from `RelationshipEvidence`

For each `evidence` in `structural.relationships()`: resolve `subject` as the entity at `evidence.left().column_position()`, `object` as the entity at `evidence.right().column_position()` (both necessarily positions within the same `structural: &StructuralKnowledge`, since Document 00E §5.7 scopes relationship evidence to a single `Dataset` and, per §0, neither `RelationshipEvidence` nor `ColumnRef` carries a dataset identity of its own). Construct one relational `Fact` with `fact_type: FactType::entity_relationship()`, `label: Some("value_subset".to_string())` (Document 00E's only current `RelationshipKind` variant, §2.2's "honestly-scoped" naming), `derivation: DerivationStrength::Inferred` (a subset check is mechanically exact but semantically uncommitted — it does not claim *which* column is the parent, per Document 00E §4.4's own note), and `origin: FactOrigin::StructuralInference`.

**[DRAFT DECISION]** If Document 00E ever adds a second `RelationshipKind` variant, this mapping (`RelationshipKind` → `label` string) is the one place in this crate that needs a corresponding new arm; documenting that dependency here means a future Document 00E revision knows to check this section too.

### 5.5 Integrating `DomainFact` values

For each `fact` in the (sorted, §5.6) `domain_facts` slice:

- **`DomainFact::Entity { label, contributor }`**: if `by_entity_label` (built incrementally as this step proceeds) already contains `label` — most commonly because a `StructuralColumn` entity happens to share the same name, e.g. a Domain Module asserting that the already-known `"revenue"` column *is* the `Revenue` business concept — no new entity is created; the existing entity is reused as the subject/object for any `DomainFact::Relationship` referencing this label (§10.5: "Domain Knowledge extends Structural Knowledge without modifying it" — extension here means *attaching facts to*, not replacing, an existing entity). Otherwise, a new `Entity` is constructed with `origin: EntityOrigin::DomainAsserted { contributor }`.
- **`DomainFact::Relationship { subject_label, predicate, object_label, contributor }`**: resolve `subject_label`/`object_label` against `by_entity_label` as it stands after all `DomainFact::Entity` values have been processed (§5.6 fixes this two-pass order). If either label is unresolved, `integrate` returns `IntegrationError::UnknownEntityLabel` (§6) rather than silently dropping the relationship or guessing — total but honest, per Document 00E §6's own "infallible in the sense that matters" framing, which reserved exactly this kind of caller-input error for a `Result`, not a panic. Otherwise, construct one relational `Fact` with `label: Some(predicate)`, `derivation: DerivationStrength::DomainAsserted`, `origin: FactOrigin::Domain { contributor }`.

**[DRAFT DECISION — unexercised until Phase 9]** Every rule in this subsection is written and testable today (§7.2) against a hand-written `domain_facts` fixture, even though no real Domain Module can produce one until Phase 9 exists. This is the same posture Document 00E took toward Phase 4 in its own §0: specify and build against the interface, not against whichever producer of that interface's input happens to exist yet.

### 5.6 Determinism of `domain_facts` processing

Because `domain_facts` may, once Phase 9 exists, be an aggregate contributed by multiple simultaneously-activated Domain Modules (§11.11) in whatever order the Domain Manager happens to iterate them, `integrate` **shall** sort a local copy of `domain_facts` by `DomainFact`'s derived `Ord` (§4.6: entity variants before relationship variants, then lexicographic by label fields) before §5.5 processes it, in two passes — all `DomainFact::Entity` values first, then all `DomainFact::Relationship` values — rather than interleaving the two variants in whatever order the input slice happens to list them. **[DRAFT DECISION]** This guarantees `integrate`'s output is independent of the caller-supplied `domain_facts` slice's order, which the Architecture Specification does not state explicitly but which is necessary for §1.2's "identical datasets generate identical Knowledge Graphs" to hold once a second input (`domain_facts`) exists alongside the `Dataset` itself — the same fingerprint-determinism discipline Document 00E §4.2/§4.3 already applied to summation order and category ordering, applied here one level up, before Phase 9 makes the gap observable in practice.

---

## 6. The `integrate` entry point

```rust
//! crates/rasica-knowledge/src/graph.rs (continued)

/// Constructs a [`KnowledgeGraph`] from `structural` knowledge and any
/// already-activated Domain Modules' `domain_facts` (empty in every
/// invocation until Phase 9 exists, §2.1).
///
/// Per §0, this function takes no separate `Dataset` argument: every
/// fact this crate needs from the originating `Dataset` — column names,
/// provenance — is already carried on `structural` itself
/// (`StructuralKnowledge::origin()`, `ColumnKnowledge::name()`), so there
/// is no second argument that could disagree with it, and therefore no
/// `DatasetMismatch`-style error to check for.
///
/// # Errors
///
/// Returns [`IntegrationError::UnknownEntityLabel`] per §5.5 for an
/// unresolvable `DomainFact::Relationship`. Never panics.
pub fn integrate(
    structural: &rasica_structural_inference::knowledge::StructuralKnowledge,
    domain_facts: &[crate::domain_fact::DomainFact],
) -> Result<KnowledgeGraph, crate::error::IntegrationError> {
    // Implementation: see §5 for the full ordered algorithm. Full source
    // intentionally omitted from this specification document, for the
    // same reason Document 00E gave for omitting its own `infer` body:
    // several [DRAFT DECISION] choices above (the certain/inferred
    // classification in §5.3, the entity-reuse-by-label rule in §5.5,
    // the two-pass sort in §5.6) are exactly the kind of decision that
    // should be reviewed before code is generated against them.
    todo!()
}
```

---

## 7. Testing

### 7.1 Determinism fixtures

Reusing Document 00E §7.1's fixture corpus (`customers_ground_truth.csv`, `sensor_readings_ground_truth.csv`) directly, plus one new fixture:

- `domain_facts_fixture.json` — a small, hand-written list of `DomainFact` values exercising both variants against the `customers` fixture: `Entity { label: "Tier", contributor: "test.fixture" }` (deliberately colliding with the already-known `tier` structural entity, to exercise §5.5's reuse-by-label path — assuming a case-normalisation rule not yet specified above; **[DRAFT DECISION]**: entity label matching in §5.5 is case-sensitive, so this fixture actually exercises the *non-collision*, new-entity path unless the fixture's label is written as exactly `"tier"` — reviewers should confirm which behaviour is intended before this test is finalised) and `Relationship { subject_label: "id", predicate: "identifies", object_label: "tier", contributor: "test.fixture" }`.

### 7.2 `tests/determinism.rs`

Per §15.9's Verification clause ("Knowledge graphs generated deterministically"):

- Ingest `customers.csv` twice via two independent paths (once via `rasica-ingestion`'s `csv::read`, once by round-tripping through JSON per Document 00C's own precedent), run `rasica_structural_inference::infer` on each, then `integrate` on each (with an empty `domain_facts` slice), and assert the two resulting `KnowledgeGraph` values have equal `DeterministicFingerprint` output.
- Run `integrate` against `domain_facts_fixture.json`'s contents twice, once in the file's original order and once with the `Vec` reversed, and assert equal `DeterministicFingerprint` output — directly verifying §5.6's order-independence claim.
- Assert `integrate` returns `IntegrationError::UnknownEntityLabel` (not a panic) for a `DomainFact::Relationship` naming a label absent from both the structural columns and any preceding `DomainFact::Entity`. (There is no `DatasetMismatch` case to test: per §0/§6, `integrate` takes no separate `Dataset` argument, so no two arguments can disagree with each other.)

### 7.3 Indexing verification

Per §10.14A: rather than a wall-clock benchmark (deferred to the Benchmarking Specification, Appendix H/§24, per Document 00E §2.2's own precedent for deferring rigorous statistical work to a later, dedicated phase), this document verifies §10.14A **by construction**: a unit test asserts `KnowledgeGraph`'s `by_fact_type`/`by_entity_label` fields are `std::collections::BTreeMap` (via a `static_assertions::assert_type_eq_all!` or equivalent compile-time check), and a second test asserts `facts_of_type`/`entity_by_label` never call `.iter().find(...)` or any other linear scan over the full `facts`/`entities` vectors — checked by code review against §14.7's complexity-threshold discipline rather than mechanically, since Rust's type system cannot itself verify algorithmic complexity.

### 7.4 Unit tests

Each classification rule in §5.3's table gets an isolated unit test (`fact.rs`'s own module), and §5.5's entity-reuse-by-label rule gets a dedicated test with a `domain_facts` fixture deliberately colliding with an existing structural column label, asserting exactly one `Entity` (not two) results.

---

## 8. Workspace integration

Following the same additive pattern as every prior phase's scaffold:

- New workspace member: `crates/rasica-knowledge`.
- New `[workspace.dependencies]` entries: none required. This crate needs no new external dependency — `std::collections::BTreeMap` is part of the standard library, and `blake3`/`proptest`/`rstest`/`criterion` are already present from Phase 1 onward.
- Compile-time dependencies: `rasica-common`, `rasica-core`, `rasica-structural-inference`. Per §0, `integrate` no longer takes a `Dataset` argument, so `rasica-knowledge` has **no** compile-time dependency on `rasica-dataset` — `rasica-dataset` appears only as a `dev-dependency`, needed by `tests/determinism.rs` to construct the `Dataset`s that `rasica-structural-inference::infer` runs against before `integrate` ever sees the result. No dependency on any Domain Module or Domain SDK crate, per §8.4 and §2.2's explicit statement of that constraint.
- `tests/workspace_smoke` extension: one new smoke test asserting `KnowledgeGraph`, `Entity`, and `Fact` compose with `rasica_core::prelude::Immutable`, matching every prior phase's own smoke-test convention.

---

## 9. Exit criteria checklist (§15.9, expanded per §1.2 and §10.14A)

- [ ] Every `VariableRole` variant from Document 00E (§4.1 there) maps to the correct row of §5.3's table, including the "no fact produced" `Unclassified` case.
- [ ] `tests/determinism.rs`'s CSV-vs-JSON fingerprint-equality test (§7.2) passes.
- [ ] `tests/determinism.rs`'s `domain_facts` order-independence test (§7.2) passes.
- [ ] `integrate` is total (never panics) on every fixture, including the deliberate-error fixture in §7.2 (`UnknownEntityLabel`), which returns `Err`, not a panic.
- [ ] `KnowledgeGraph`, `Entity`, and `Fact` are all Tier 1 — Immutable per §6.2A, verified by the same `assert_immutable::<T>()` pattern the workspace smoke test already uses.
- [ ] §10.14A: `by_fact_type`/`by_entity_label` are `BTreeMap`-backed (§7.3), and `facts_of_type`/`entity_by_label` contain no linear scan over the full entity/fact collections.
- [ ] `#![forbid(unsafe_code)]` present; `cargo clippy --workspace --all-targets -- -D warnings`, `cargo fmt --all -- --check`, `cargo deny check` all pass, matching every prior phase's bar.

---

## 10. Summary of every [DRAFT DECISION] in this document, for review

1. §0, gap 1 — assuming Document 00E's crate will expose public accessors on `StructuralKnowledge`/`ColumnKnowledge`/`RelationshipEvidence`/`ColumnRef` not shown in 00E's own listings.
2. §0, gap 2 — resolved: Document 00E's actual scaffold now stores `name` directly on `ColumnKnowledge`, so `integrate` takes no `Dataset` argument at all (§5.2, §6).
3. §1.1 — folding the three §15.9 deliverables (entity graph, relationship graph, semantic graph) into one `KnowledgeGraph` type rather than three separate structures.
4. §1.2 — treating §10.14A's indexing requirement as a first-class Phase 6 exit criterion, not merely a note for the later Rule Engine phase.
5. §4.1/§4.6 — representing `EntityOrigin::DomainAsserted`'s and `FactOrigin::Domain`'s `contributor` field as a plain `String` rather than a strongly-typed `DomainModuleId`, pending Phase 9 introducing a marker type this crate can depend on without a circular dependency.
6. §4.2 — `FactType` as an open, string-backed newtype rather than a closed enum, to accommodate Domain-Module-contributed fact types this crate cannot enumerate at compile time.
7. §4.4 — `Fact`'s `label: Option<String>` field as the single mechanism for both structurally-derived (`"value_subset"`) and future domain-asserted (`"generated_by"`, etc.) relationship predicates, rather than two separate types.
8. §5.3 — the `StructurallyCertain`/`Inferred` classification of each `VariableRole` → `FactType` mapping, and the decision to produce no fact at all for `Unclassified` columns.
9. §5.4 — deriving relational facts' `label` from `RelationshipKind` via a mapping this document owns, which a future Document 00E revision would need to extend.
10. §5.5 — the entity-reuse-by-label rule for `DomainFact::Entity` (and, per §7.1's flagged ambiguity, whether label matching is case-sensitive).
11. §5.6 — sorting `domain_facts` into a fixed two-pass (entities-then-relationships) order before processing, to make `integrate`'s output independent of caller-supplied slice order.
12. §6 — no `IntegrationError::DatasetMismatch` variant: since `integrate` takes no separate `Dataset` argument (§0, gap 2), there is nothing for `structural` to disagree with, so this variant is dropped rather than defined.
13. §7.1 — the specific `domain_facts_fixture.json` contents, and the open question of case-sensitive label matching they were chosen to probe.
14. §7.3 — verifying §10.14A's complexity requirement by construction and code review rather than by a runtime benchmark, deferring the latter to the Benchmarking Specification.

Please review these fourteen points specifically, together with the two Document 00E prerequisite gaps in §0 (which may need to be resolved in `rasica-structural-inference` before this crate's own scaffolding can begin). Once you're satisfied with them (or have told me how to change them), the next step is the same as Phases 1–4: I generate a scaffold script that creates `crates/rasica-knowledge` in full, working Rust, exactly as specified above.
