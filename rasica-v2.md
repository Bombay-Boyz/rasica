# RASICA Architecture Specification

## Vision, Principles and Foundational Architecture

**Version:** 2.1 (Draft)

---

# Document Control

| Item                    | Value                                                                   |
| ----------------------- | ----------------------------------------------------------------------- |
| Project                 | RASICA                                                                  |
| Full Name               | Rule-based Autonomous Statistical Inference and Computational Analytics |
| Document                | Architecture Specification                                              |
| Version                 | 2.1                                                                     |
| Status                  | Draft                                                                   |
| Document Type           | Foundational Architecture                                               |
| Intended Audience       | Architects, Developers, Domain Module Authors, Contributors             |
| Implementation Language | Rust                                                                    |
| Architecture Style      | Clean Architecture + Hexagonal Architecture                             |
| Document Owner          | RASICA Architecture Team                                                |

---

# Revision Notes (2.0 → 2.1)

Version 2.1 is a corrective architectural pass over 2.0. It resolves ambiguities and internal inconsistencies identified during architectural review, without weakening the platform's scope or principles. No domains, input formats, mathematical capability tiers, or renderers were removed. Specifically, this revision:

- Replaces the previously abstract Rule Engine description with a concrete, deterministic evaluation algorithm (§10.12–10.14A).
- Redefines Domain Activation from a "confidence" metric to a deterministic Applicability Score to remove any appearance of probabilistic influence over analytical conclusions (§11.10).
- Reconciles the two previously divergent dependency representations into a single authoritative dependency graph (§8.3).
- Scopes the Determinism principle precisely, distinguishing logical determinism (guaranteed) from bit-identical cross-architecture floating-point determinism (explicitly bounded), and defines the deterministic reduction strategy that makes parallel execution compatible with reproducibility (§4.1, §12.10, §12.22).
- Makes the Domain Module loading mechanism concrete: static, compile-time composition via a trait-based registry, rather than an unspecified dynamic plugin model (§11.18A).
- Replaces the single undifferentiated "Immutability" principle with three explicit mutability tiers applied consistently across every Core Architectural Object (§6.2, Appendix A.4).
- Adds indexing and complexity requirements for the Knowledge Graph, Capability Registry, and Rule Engine to bound reasoning cost as Domain Modules and dataset width grow (§10.11A).
- Clarifies that Dataset immutability is a logical (not physical) guarantee, so chunked/paged materialisation is permitted without future redesign (§6.4).
- Adds minimal canonical trait signatures for the Core Architectural Objects and the Domain SDK so downstream module specifications share one vocabulary (Appendix G).
- Replaces unenforced "shall never" domain-security language with an explicit trust and enforcement model consistent with the compile-time composition decision (§11.22).
- Adds a Non-Functional Requirements baseline (Appendix H) so "high-performance" and "scalable" have measurable acceptance targets.

Each change below is marked inline with a `> **[2.1]**` annotation the first time it appears, so reviewers can trace exactly what changed and why.

> **Editorial note (post-2.1 consistency pass).** Independently of the architectural changes above, this pass corrected a set of internal-consistency defects that did not affect architectural intent: the Table of Contents and Appendix lettering had drifted out of sync with the body (now corrected to match exactly); a heading in §8.3 described data flow in a direction inconsistent with the §7.4 layer diagram (clarified, with a new explanatory note in §7.4); the canonical Rule grammar in §10.11A was missing the `suppresses` field already required by its own Conflict Resolution text and by Appendix G; the Phase 9 roadmap (§15.12) still listed a "Domain Loader," an artifact of the pre-2.1 dynamic-loading model superseded by §11.18A's static composition decision, and a "Lifecycle Manager" never defined elsewhere (both replaced with the "Domain Manager" already defined in §11.7/§11.9/§11.10); Appendix C was missing two Core Architectural Objects and did not distinguish objects from subsystems; the domain lists in §7.2 and Appendix D were clarified as illustrative rather than exhaustive, against the authoritative list in §1.3; and "-ization" spellings were normalised to the "-isation" spelling used throughout the rest of the document. No architectural principle, invariant, tier assignment, or numbered requirement was altered by this pass.

---

# Document Purpose

This document defines the foundational architecture of the RASICA platform.

It establishes the architectural principles, system boundaries, responsibilities, constraints, and governing rules that shall guide the design and implementation of every component within the project.

This document intentionally avoids implementation details. Its purpose is to define **what RASICA is**, **what it must achieve**, and **how the major architectural components relate to one another**.

All subsequent specifications—including module specifications, API specifications, coding standards, and contributor guides—shall conform to the principles established herein.

---

# Document Status

This document represents the constitutional specification of the RASICA platform.

Once approved, changes to this document shall be considered architectural changes.

Architectural changes shall require:

- formal review,
- documented rationale,
- compatibility assessment,
- approval through an Architecture Decision Record (ADR).

Minor editorial corrections may be made without changing the architectural intent of the document.

---

# Table of Contents

```
1.  Introduction
2.  Vision
3.  Mission
4.  Design Goals
5.  Foundational Principles
6.  Core Architectural Objects
7.  System Architecture
8.  Dependency Rules
9.  Architectural Layers in Detail
10. Knowledge and Reasoning Model
11. Domain Framework
12. Analysis and Execution Framework
13. Diagnostics, Auditing and Observability
14. Engineering Principles and Software Standards
15. Module Breakdown and Development Roadmap
16. Milestones and Acceptance Gates
17. Appendices (A-I)
```

---

# 1. Introduction

## 1.1 Background

Modern analytical software generally falls into one of three categories:

- interactive statistical tools,
- business intelligence platforms,
- artificial intelligence–assisted analytics.

While these systems provide powerful analytical capabilities, they generally require users to determine:

- which analyses should be performed,
- which statistical methods are appropriate,
- which visualisations should be generated,
- how analytical workflows should be constructed.

As a result, analytical outcomes often depend upon user expertise and subjective decision-making.

RASICA is designed to address a different problem.

Rather than functioning as an interactive analytical workbench, RASICA is designed as a deterministic analytical reasoning engine that autonomously determines valid analytical workflows based upon objective characteristics of the dataset and formally defined domain knowledge.

---

## 1.2 Scope

RASICA is responsible for:

- ingesting structured datasets,
- validating data integrity,
- constructing structural understanding,
- incorporating domain knowledge,
- determining applicable analytical operations,
- executing statistical and mathematical analyses,
- generating visualisations,
- producing explainable analytical reports.

RASICA is **not** responsible for:

- manual statistical experimentation,
- interactive data exploration,
- spreadsheet manipulation,
- arbitrary user-directed analyses,
- predictive reasoning based on machine learning,
- natural language reasoning,
- generative artificial intelligence.

---

## 1.3 Intended Use

RASICA is intended to serve as an analytical engine capable of supporting multiple domains through independently developed Domain Modules.

Potential application areas include:

- Business Analytics
- Finance
- Healthcare
- Manufacturing
- Retail
- Agriculture
- Scientific Research
- Engineering
- Public Policy
- Education

The analytical engine itself remains independent of every supported domain.

---

# 2. Vision

The vision of RASICA is to establish a new class of analytical software built upon deterministic reasoning rather than user-directed analysis or probabilistic artificial intelligence.

RASICA seeks to become a reusable analytical platform capable of transforming validated structured data into objective, reproducible, explainable, and mathematically defensible analytical outcomes.

The platform shall remain:

- deterministic,
- modular,
- extensible,
- domain-independent,
- reproducible,
- transparent,
- high-performance,
- maintainable.

Every architectural decision shall reinforce these characteristics.

---

# 3. Mission

RASICA exists to eliminate unnecessary subjectivity from structured data analysis.

Rather than requiring users to decide which analytical methods should be applied, RASICA shall determine the complete analytical workflow using:

- mathematical correctness,
- statistical validity,
- structural characteristics of the dataset,
- deterministic domain knowledge.

The platform shall provide analytical outcomes that are:

- objective,
- reproducible,
- explainable,
- complete,
- resistant to manipulation.

---

# 4. Design Goals

The following goals govern the design of the platform.

## 4.1 Determinism

> **[2.1]** This section previously asserted unconditional bit-identical output regardless of hardware, which is not achievable for floating-point computation and conflicted with the platform's parallel-execution goals (§4.6). Determinism is now defined precisely, in two tiers.

RASICA guarantees two distinct, independently verifiable forms of determinism:

**Logical Determinism (unconditional guarantee).** Given identical Dataset, Configuration, Domain Modules, and Engine Version, RASICA shall always:

- select the same analytical operations,
- apply the same rules in the same order,
- construct an isomorphic Analysis Graph,
- reach the same analytical conclusions,
- classify diagnostics identically.

Logical determinism holds regardless of execution environment, processor count, thread scheduling, or operating system. It does not depend on floating-point evaluation order and is therefore preserved unconditionally.

**Numeric Determinism (scoped guarantee).** Given identical Dataset, Configuration, Domain Modules, and Engine Version, and given a fixed target numeric precision profile (§12.10), RASICA shall produce bit-identical floating-point results across executions on the same target profile. Numeric determinism is achieved through the deterministic reduction strategy defined in §12.10, and is guaranteed within a single numeric precision profile — it is not claimed across profiles that use different hardware floating-point behaviour (e.g. differing SIMD width or fused-multiply-add availability) unless that profile is explicitly selected and pinned for the execution.

This distinction exists so that reproducibility can be verified layer by layer: logical determinism is verified by comparing Analysis Graphs; numeric determinism is verified by comparing computed values within a declared precision profile.

Performance optimisations shall never compromise logical determinism. Performance optimisations may only affect numeric determinism insofar as they change which precision profile is active, and any such change shall be an explicit, audited configuration decision rather than an incidental side effect of scheduling.

---

## 4.2 Correctness

Mathematical and statistical correctness take precedence over convenience, performance, and feature count.

When conflicts arise, correctness shall always prevail.

---

## 4.3 Explainability

Every analytical conclusion shall be traceable to:

- input data,
- structural inference,
- domain knowledge,
- analytical rules,
- mathematical principles.

No result shall exist without a documented chain of reasoning.

---

## 4.4 Reproducibility

Independent executions performed under identical conditions shall generate identical:

- metadata,
- analytical graphs,
- computations,
- visualisations,
- reports,
- diagnostics,
- audit records.

---

## 4.5 Extensibility

The architecture shall support extension through independent modules rather than modification of existing components.

Support for new domains, data sources, renderers, or analytical capabilities shall not require redesign of the Core Engine.

---

## 4.6 Performance

The platform shall be designed to support:

- efficient memory usage,
- scalable execution,
- parallel computation,
- deterministic scheduling,
- predictable performance.

Performance optimisations shall never compromise determinism or correctness.

---

## 4.7 Maintainability

The architecture shall promote:

- clear module boundaries,
- minimal coupling,
- high cohesion,
- explicit interfaces,
- comprehensive testing,
- stable public APIs.

---

# 5. Foundational Principles

The following principles are mandatory architectural constraints.

These principles define the identity of RASICA.

No implementation may violate them.

## Principle 1 — RASICA is Deterministic

RASICA is a deterministic analytical reasoning engine.

Every analytical outcome shall be produced through deterministic computation.

Randomized or probabilistic reasoning shall not influence analytical conclusions.

---

## Principle 2 — RASICA is not AI-dependent

Artificial Intelligence is not a dependency of the analytical pipeline.

The Core Engine shall never require:

- Large Language Models,
- Machine Learning,
- Neural Networks,
- Generative AI,
- probabilistic inference.

Future AI integrations, if introduced, shall exist only as optional external consumers or advisors and shall never modify deterministic analytical outcomes.

---

## Principle 3 — RASICA is Domain-independent

The Core Engine understands:

- structure,
- mathematics,
- statistics,
- execution.

The Core Engine does **not** understand:

- business,
- finance,
- healthcare,
- manufacturing,
- agriculture,
- or any other application domain.

Domain understanding exists exclusively within Domain Modules.

---

## Principle 4 — Knowledge and Reasoning are Separate

Knowledge and reasoning are independent architectural concerns.

Domain Modules produce knowledge.

The Rule Engine reasons over that knowledge.

This separation ensures that domain expertise remains declarative while analytical reasoning remains centralized, deterministic, and reusable.

---

## Principle 5 — Users Supply Data, Not Decisions

Users are responsible for providing:

- datasets,
- configuration,
- domain modules.

Users are **not** responsible for selecting analytical methods.

Once validation succeeds, RASICA autonomously determines the analytical workflow.

---

## Principle 6 — Every Decision Must Be Explainable

Every inference, recommendation, computation, visualisation, and report shall possess a complete chain of reasoning that can be reconstructed independently.

---

## Principle 7 — Everything is Auditable

Every execution shall produce sufficient information to reconstruct:

- what data was analysed,
- which rules were applied,
- which computations were performed,
- why conclusions were reached.

---

## Principle 8 — Immutable Processing

Once validation has completed successfully:

- datasets become immutable,
- metadata becomes immutable,
- analysis graphs become immutable,
- execution plans become immutable.

Any modification requires construction of a completely new analytical execution.

# 6. Core Architectural Objects

## 6.1 Purpose

Every architectural component within RASICA operates on a well-defined set of immutable architectural objects.

These objects represent the language of the platform.

Every future specification, implementation, test, and extension shall reference these objects rather than introducing alternative terminology.

The Core Architectural Objects constitute the canonical vocabulary of RASICA.

---

## 6.2 Design Principles

Every Core Architectural Object shall satisfy the following characteristics:

- Clearly defined responsibility.
- Single source of truth.
- Assigned to exactly one Mutability Tier, as defined below, and consistent with that tier for its entire lifetime.
- Independent of presentation.
- Independent of implementation language.
- Traceable throughout execution.
- Serializable where appropriate.
- Testable in isolation.

Objects communicate through explicit interfaces rather than direct implementation dependencies.

---

## 6.2A Mutability Tiers

> **[2.1]** Previous revisions used a single undifferentiated term, "immutable," for objects with materially different mutation semantics (e.g. Audit Records versus the Execution Context versus intermediate caches). This produced an apparent contradiction between the Immutability principle and caching (§12.16). Every Core Architectural Object now declares which of three tiers it belongs to, and no object may exhibit mutation behaviour outside its declared tier.

**Tier 1 — Immutable.** The object is fully constructed once and never modified afterward for the remainder of the process. Any change requires constructing a new object with a new identity. Applies to: Dataset, Metadata, Validation Report, Structural Knowledge, Knowledge Graph, Domain Facts, Capability Registry, Rules, Analysis Graph, Audit Record.

**Tier 2 — Append-Only.** The object may receive additional entries over the course of an execution, but existing entries are never altered or removed once written. The object is treated as immutable by every consumer that reads a snapshot of it. Applies to: Diagnostics.

**Tier 3 — Scoped-Mutable.** The object is mutable only within the bounded lifetime of a single execution, is owned exclusively by one subsystem during that lifetime, is never shared as a mutable reference across subsystem boundaries, and is discarded (never persisted as authoritative state) at the end of the execution. Applies to: Execution Context, and internal Execution Engine caches of intermediate results.

Rules governing Tier 3 objects:

- A Scoped-Mutable object shall never be the source of truth for an analytical conclusion; conclusions are always derived from Tier 1 objects.
- Caching intermediate results (§12.16) is a Tier 3 concern: cached values are a performance optimisation over already-deterministic Tier 1 computations, are always keyed by a deterministic fingerprint of their inputs, and their presence or absence shall never change the analytical result, only the time taken to produce it.
- No object may be promoted from Tier 3 to Tier 1 by aliasing; a Tier 1 object referencing Tier 3-derived data must copy the data at the point of construction.

---

# 6.3 Architectural Object Hierarchy

```text
                           Dataset
                               │
                 ┌─────────────┴─────────────┐
                 │                           │
                 ▼                           ▼
           Metadata                  Validation Report
                 │
                 ▼
         Structural Knowledge
                 │
                 ▼
          Knowledge Graph
                 │
        ┌────────┴────────┐
        ▼                 ▼
 Domain Facts      Capability Registry
        │                 │
        └────────┬────────┘
                 ▼
            Rule Engine
                 │
                 ▼
          Analysis Graph
                 │
                 ▼
         Execution Context
                 │
        ┌────────┴─────────┐
        ▼                  ▼
 Diagnostics         Audit Record
        │                  │
        └────────┬─────────┘
                 ▼
               Report
```

This hierarchy represents the conceptual lifecycle of analytical information.

---

# 6.4 Dataset

## Definition

A Dataset is the immutable internal representation of ingested data.

Every supported external format shall be transformed into a Dataset before any analytical operation begins.

Examples of supported external sources include:

- CSV
- Excel
- JSON
- SQL
- Apache Arrow
- Apache Parquet

Regardless of origin, all analytical operations operate exclusively upon the Dataset object.

---

## Responsibilities

The Dataset is responsible for representing:

- rows
- columns
- values
- identifiers
- source metadata

The Dataset is **not** responsible for:

- validation
- semantic interpretation
- statistics
- mathematical computation
- visualisation

---

## Architectural Rules

A Dataset:

- shall be immutable after validation (Tier 1, §6.2A),
- shall not contain domain knowledge,
- shall remain independent of analytical operations,
- shall never store derived analytical results.

> **[2.1]** Immutability of the Dataset is a **logical** guarantee, not a physical one: it constrains what callers may observe (a Dataset never appears to change after validation), not how the engine physically stores the underlying data. A conforming implementation may back a Dataset with a single in-memory buffer, or with a chunked/paged representation that materialises rows lazily from an external source, provided that every observer sees a consistent, unchanging logical view. This distinction exists specifically so that streaming and out-of-core datasets (Appendix F) can be introduced later as an alternative Dataset backing without violating this section or requiring redesign of any consumer of the Dataset object.

---

# 6.5 Metadata

## Definition

Metadata is the structural description of a Dataset.

Metadata describes the characteristics of data without interpreting its domain meaning.

Examples include:

- datatype
- nullability
- uniqueness
- cardinality
- distribution
- scale
- temporal properties

---

## Responsibilities

Metadata provides the structural foundation upon which all later reasoning is performed.

It answers questions such as:

- What type of information exists?
- How is it represented?
- Which mathematical operations are possible?

---

## Architectural Rules

Metadata:

- is derived solely from the Dataset,
- contains no domain semantics,
- becomes immutable after creation.

---

# 6.6 Validation Report

## Definition

A Validation Report records every validation activity performed on a Dataset.

Validation is considered an independent architectural concern.

---

## Responsibilities

The Validation Report records:

- successful validations,
- failed validations,
- warnings,
- recommendations,
- assumptions.

---

## Architectural Rules

The Validation Report:

- never modifies the Dataset,
- never contains analytical conclusions,
- is always preserved as part of the execution record.

---

# 6.7 Structural Knowledge

## Definition

Structural Knowledge represents everything the Core Engine can determine about a Dataset without consulting Domain Modules.

Examples include:

- numerical variables,
- categorical variables,
- identifiers,
- timestamps,
- distributions,
- relationships,
- missing value characteristics.

---

## Purpose

Structural Knowledge provides the factual basis upon which semantic reasoning later operates.

It contains no interpretation.

---

# 6.8 Knowledge Graph

## Definition

The Knowledge Graph is the central semantic representation of RASICA.

It represents relationships discovered throughout the analytical process.

Unlike Metadata, which describes isolated characteristics, the Knowledge Graph describes how objects relate to one another.

---

## Responsibilities

The Knowledge Graph stores:

- entities,
- relationships,
- dependencies,
- hierarchies,
- inferred associations.

Examples include:

```text
Revenue
    │
generated_by
    │
Customer

Revenue
    │
measured_over
    │
Time

Product
    │
belongs_to
    │
Category
```

---

## Architectural Rules

The Knowledge Graph:

- never performs computation,
- never executes rules,
- stores knowledge only,
- remains immutable after construction.

---

# 6.9 Domain Facts

## Definition

Domain Facts represent semantic knowledge contributed by Domain Modules.

Examples include:

- Revenue
- Cost
- Profit
- Patient
- Temperature
- Inventory
- Machine
- Experiment

Domain Facts extend Structural Knowledge with domain meaning.

---

## Responsibilities

A Domain Fact may describe:

- entities,
- metrics,
- dimensions,
- KPIs,
- business concepts,
- scientific concepts,
- engineering concepts.

---

## Architectural Rules

Domain Facts:

- originate exclusively from Domain Modules,
- never modify the Dataset,
- remain independent of statistical computation.

---

# 6.10 Capability Registry

## Definition

The Capability Registry records every analytical operation that is valid for every discovered object.

Capabilities are determined using:

- structural knowledge,
- domain knowledge,
- mathematical validity.

---

## Examples

Revenue may support:

- trend analysis,
- growth analysis,
- moving averages,
- forecasting,
- contribution analysis.

Categorical variables may support:

- frequency distributions,
- mode,
- chi-square analysis.

---

## Architectural Rules

Capabilities describe **what may be performed**.

They never determine **what shall be performed**.

That responsibility belongs to the Rule Engine.

---

# 6.11 Rule

## Definition

A Rule is a deterministic statement describing analytical reasoning.

Rules transform knowledge into analytical decisions.

Example (conceptually):

```text
IF

Revenue exists

AND

Date exists

THEN

Recommend Trend Analysis
```

---

## Responsibilities

Rules determine:

- analytical recommendations,
- execution prerequisites,
- visualisation eligibility,
- dependency relationships.

---

## Architectural Rules

Rules:

- are deterministic,
- are declarative,
- contain no procedural execution logic,
- remain independently testable.

---

# 6.12 Analysis Graph

## Definition

The Analysis Graph is the immutable representation of the complete analytical workflow.

It is conceptually similar to an Abstract Syntax Tree within a compiler.

The Analysis Graph defines:

- operations,
- dependencies,
- execution order,
- prerequisites.

---

## Responsibilities

The Analysis Graph answers:

- What shall be executed?
- Why shall it be executed?
- In what order?
- What depends upon what?

---

## Architectural Rules

The Analysis Graph:

- is immutable,
- deterministic,
- reproducible,
- independent of execution.

Execution engines consume the graph.

They never construct it.

---

# 6.13 Execution Context

## Definition

The Execution Context represents the runtime environment for one analytical execution.

It records execution-specific information without modifying analytical objects.

---

## Responsibilities

Examples include:

- execution identifier,
- configuration,
- resource allocation,
- active Domain Modules,
- timing information.

---

## Architectural Rules

The Execution Context exists only during execution.

It is never used for analytical reasoning.

---

# 6.14 Diagnostic

## Definition

A Diagnostic is a structured description of an informational event, warning, error, or failure.

Diagnostics describe system behaviour.

They never modify it.

---

## Responsibilities

Diagnostics communicate:

- validation outcomes,
- execution issues,
- assumptions,
- recommendations,
- failures.

---

# 6.15 Audit Record

## Definition

The Audit Record is the immutable historical record of an analytical execution.

Unlike Diagnostics, which describe events, the Audit Record documents the complete analytical journey.

---

## Responsibilities

The Audit Record records:

- Dataset fingerprint,
- Metadata fingerprint,
- Domain Modules,
- Rules evaluated,
- Analyses executed,
- Visualisations generated,
- Diagnostics emitted,
- Timing,
- Software versions.

---

## Architectural Rules

Every execution produces exactly one Audit Record.

Audit Records are immutable.

---

# 6.16 Report

## Definition

A Report is the final presentation artifact produced by RASICA.

Reports communicate analytical results.

They do not influence analysis.

---

## Responsibilities

Reports integrate:

- analytical findings,
- visualisations,
- diagnostics,
- audit summaries,
- metadata,
- recommendations.

---

## Architectural Rules

Reports are consumers of analytical objects.

They never modify them.

---

# 6.17 Object Ownership Matrix

> **[2.1]** The "Mutability Tier" column now references §6.2A explicitly, replacing the previous ad hoc Yes/No/Append-Only values, so this matrix cannot drift out of sync with the mutability model.

| Object               | Owner                 | Mutability Tier                                                                            | Consumer            |
| --------------------- | ---------------------- | -------------------------------------------------------------------------------------------- | -------------------- |
| Dataset               | Dataset Engine         | Tier 1 — Immutable                                                                            | Validation           |
| Metadata               | Structural Inference   | Tier 1 — Immutable                                                                            | Knowledge Graph      |
| Validation Report      | Validation Engine      | Tier 1 — Immutable                                                                            | Diagnostics          |
| Structural Knowledge   | Structural Inference   | Tier 1 — Immutable                                                                            | Knowledge Graph      |
| Knowledge Graph        | Knowledge Engine       | Tier 1 — Immutable                                                                            | Rule Engine          |
| Domain Facts           | Domain Modules         | Tier 1 — Immutable                                                                            | Knowledge Graph      |
| Capability Registry    | Capability Engine      | Tier 1 — Immutable                                                                            | Rule Engine          |
| Rules                  | Rule Engine            | Tier 1 — Immutable                                                                            | Analysis Planner     |
| Analysis Graph         | Analysis Planner       | Tier 1 — Immutable                                                                            | Execution Engine     |
| Execution Context      | Execution Engine       | Tier 3 — Scoped-Mutable                                                                       | Diagnostics, Audit   |
| Diagnostics            | Diagnostics Engine     | Tier 2 — Append-Only                                                                          | Report               |
| Audit Record           | Audit Engine           | Tier 1 — Immutable                                                                            | Report               |
| Report                 | Reporting Engine       | Tier 3 — Scoped-Mutable while under construction; becomes Tier 1 — Immutable once returned    | User                 |

---

# 6.18 Architectural Principle

The Core Architectural Objects form the semantic foundation of RASICA.

Every module within the platform shall operate by creating, transforming, consuming, or preserving these objects.

No module shall introduce alternative architectural concepts that duplicate the responsibilities of an existing Core Architectural Object.

Maintaining the integrity of this object model is fundamental to preserving the determinism, modularity, and long-term maintainability of the RASICA architecture.

---

# 7. System Architecture

## 7.1 Overview

RASICA is architected as a deterministic analytical platform composed of independent subsystems.

Each subsystem has a single, clearly defined responsibility.

Subsystems communicate only through well-defined architectural objects and public interfaces.

No subsystem shall directly manipulate the internal state of another subsystem.

This architectural separation ensures:

- deterministic execution,
- low coupling,
- high cohesion,
- independent testing,
- long-term maintainability,
- modular extensibility.

---

## 7.2 High-Level Architecture

```text
                         User
                           │
                           ▼
                      CLI Interface
                           │
                           ▼
                  Application Controller
                           │
                           ▼
──────────────────────────────────────────────────────────────
                     Core Engine
──────────────────────────────────────────────────────────────
│
├── Dataset Engine
├── Validation Engine
├── Structural Inference Engine
├── Knowledge Engine
├── Capability Engine
├── Rule Engine
├── Analysis Planner
├── Execution Engine
├── Statistics Engine
├── Mathematics Engine
├── Visualisation Planner
├── Reporting Engine
├── Diagnostics Engine
└── Audit Engine
──────────────────────────────────────────────────────────────
                           │
                           ▼
──────────────────────────────────────────────────────────────
                  Domain Module Framework
──────────────────────────────────────────────────────────────
│
├── Business Domain
├── Finance Domain
├── Healthcare Domain
├── Manufacturing Domain
├── Scientific Domain
└── User Defined Domains
──────────────────────────────────────────────────────────────
                           │
                           ▼
──────────────────────────────────────────────────────────────
                       Renderers
──────────────────────────────────────────────────────────────
│
├── Terminal
├── Markdown
├── HTML
├── SVG
├── PNG
├── PDF
└── JSON
```

> **Note:** The Domain Module Framework row above shows a representative, non-exhaustive subset of Domain Modules for illustration. §1.3 lists the full range of potential application areas RASICA is intended to support; this diagram is not a competing or exhaustive enumeration, and adding a Domain Module for any area listed in §1.3 requires no change to the Core Engine (§4.5).

---

# 7.3 Architectural Characteristics

The architecture shall satisfy the following characteristics.

| Characteristic | Requirement                                                              |
| -------------- | ------------------------------------------------------------------------ |
| Deterministic  | Every execution shall produce identical results for identical inputs.    |
| Immutable      | Core analytical objects become immutable after creation.                 |
| Modular        | Components may evolve independently.                                     |
| Extensible     | New functionality is introduced through extension, not modification.     |
| Explainable    | Every analytical decision is traceable.                                  |
| Testable       | Every subsystem can be verified independently.                           |
| Replaceable    | Internal implementations may change without affecting dependent modules. |

---

# 7.4 Architectural Layers

RASICA is divided into five logical layers.

```text
Presentation Layer

↓

Application Layer

↓

Analytical Layer

↓

Knowledge Layer

↓

Infrastructure Layer
```

Each layer depends only upon layers beneath it.

Reverse dependencies are prohibited.

> **Note:** This five-layer diagram describes the general case. Two Analytical Layer subsystems — Validation and Structural Inference (§7.7) — are the sole exception: they execute before the Knowledge Layer is constructed and their output becomes the Knowledge Layer's input, while other Analytical Layer subsystems (Rule Engine, Analysis Planner, Execution Engine, Statistics Engine, Mathematics Engine, Visualisation Planner) execute after the Knowledge Layer and depend downward on it in the ordinary way. This does not create a dependency cycle: no subsystem ever depends, directly or transitively, on a subsystem that itself depends on it. §8.3 defines the authoritative, acyclic, subsystem-level dependency graph; where the layer diagram above and §8.3 appear to differ, §8.3 governs.

---

# 7.5 Presentation Layer

The Presentation Layer provides user interaction.

Responsibilities include:

- CLI interaction
- output formatting
- progress reporting
- report presentation

The Presentation Layer shall never:

- perform inference,
- execute statistics,
- interpret datasets,
- construct analytical workflows.

---

# 7.6 Application Layer

The Application Layer coordinates execution.

Responsibilities include:

- execution lifecycle,
- configuration,
- module loading,
- orchestration,
- workflow management.

The Application Layer does not perform analytical reasoning.

It coordinates analytical components.

---

# 7.7 Analytical Layer

The Analytical Layer contains the computational intelligence of RASICA.

Subsystems include:

- Validation
- Structural Inference
- Capability Engine
- Rule Engine
- Analysis Planner
- Execution Engine
- Statistics Engine
- Mathematical Engine
- Visualisation Planner

Every analytical decision originates within this layer.

---

# 7.8 Knowledge Layer

The Knowledge Layer represents semantic understanding.

It contains:

- Knowledge Graph
- Domain Facts
- Capability Registry

This layer answers:

"What is known?"

It never answers:

"What should be executed?"

---

# 7.9 Infrastructure Layer

The Infrastructure Layer manages external interaction.

Examples include:

- file systems,
- databases,
- logging,
- configuration,
- rendering,
- plugins.

Infrastructure shall remain completely independent of analytical reasoning.

---

# 8. Dependency Rules

## 8.1 Purpose

Dependency rules preserve architectural integrity.

They prevent accidental coupling between unrelated modules.

Violation of these rules constitutes an architectural defect.

---

# 8.2 General Rule

Dependencies flow in one direction only.

```text
Presentation

↓

Application

↓

Analytical

↓

Knowledge

↓

Infrastructure
```

No lower layer may depend upon a higher layer.

---

# 8.3 Core Dependency Graph

> **[2.1]** Revision 2.0 presented this graph as a single linear chain (`Planner → Rule Engine → Capability Engine → Knowledge Graph`), which contradicted §7.7, where the Analysis Planner, Rule Engine, and Capability Engine are declared as peer subsystems within the same Analytical Layer. A strict chain implies each subsystem calls the next in sequence; the actual relationship is that several Analytical Layer subsystems each depend on the Knowledge Layer independently, and depend on each other only where real data flow requires it. This section now shows the authoritative fine-grained dependency graph, and §8.2's layer diagram is a coarse-grained projection of exactly this graph — the two are required to stay consistent, and any future edit to one requires the corresponding edit to the other.

```text
                         CLI  (Presentation)
                           │
                           ▼
           Application Controller  (Application)
                           │
                           ▼
        ┌──────────────────────────────────────────┐
        │            Analytical Layer               │
        │                                            │
        │   Analysis Planner ──► Rule Engine         │
        │          │                  │              │
        │          ▼                  ▼              │
        │   Execution Engine    Capability Engine     │
        │          │                                  │
        │          ├──► Statistics Engine              │
        │          └──► Mathematics Engine              │
        │                                            │
        │   (Validation, Structural Inference sit    │
        │    earlier in the pipeline — see below)     │
        └──────────────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────────────┐
        │             Knowledge Layer                │
        │                                            │
        │        Knowledge Graph ◄── Domain Facts     │
        │              ▲                              │
        │              │                              │
        │      Structural Knowledge                   │
        │              ▲                              │
        │      Structural Inference Engine            │
        │              ▲                              │
        │         Validation Engine                   │
        └──────────────────────────────────────────┘
                           │
                           ▼
        ┌──────────────────────────────────────────┐
        │           Infrastructure Layer              │
        │                                            │
        │              Dataset Engine                 │
        │                     │                       │
        │                     ▼                       │
        │                 Core Types                  │
        └──────────────────────────────────────────┘
```

Reading this graph:

- The **Rule Engine** depends on the Knowledge Layer (Knowledge Graph, Capability Registry) — never on the Analysis Planner or Execution Engine (§8.5).
- The **Analysis Planner** depends on the Rule Engine's output and the Capability Registry, and produces the Analysis Graph consumed by the Execution Engine (§8.6). It does not depend on the Execution Engine.
- The **Capability Engine** depends only on the Knowledge Layer, not on the Rule Engine or Planner — it is queried by both, but calls neither.
- **Validation** and **Structural Inference** sit within the Analytical Layer's responsibilities (per §7.7) but execute earliest in the pipeline, immediately above the Infrastructure Layer's Dataset Engine, and their outputs become the inputs from which the Knowledge Layer is constructed — the single named exception to the general layer-dependency rule, explained in §7.4.
- No arrow in this graph may point upward or skip a layer boundary defined in §8.2. Any proposed dependency not shown here requires an Architecture Decision Record before implementation.

---

# 8.4 Domain Module Dependencies

Domain Modules may depend upon:

- Domain SDK
- Core Types
- Knowledge interfaces

Domain Modules shall never depend upon:

- Statistics Engine
- Planner
- Execution Engine
- Renderer
- Reporting Engine

Domain Modules provide knowledge.

They never control execution.

---

# 8.5 Rule Engine Dependencies

The Rule Engine depends upon:

- Knowledge Graph
- Capability Registry
- Domain Facts

It shall never depend upon:

- Execution Engine
- Renderer
- Reports

The Rule Engine reasons.

It does not execute.

---

# 8.6 Analysis Planner Dependencies

The Analysis Planner depends upon:

- Rule Engine
- Capability Registry

The Planner constructs Analysis Graphs.

It performs no computation.

---

# 8.7 Execution Engine Dependencies

The Execution Engine depends upon:

- Analysis Graph
- Statistics Engine
- Mathematics Engine

Execution never performs reasoning.

It executes decisions already made.

---

# 8.8 Renderer Dependencies

Renderers depend only upon:

- Reports
- Diagnostics
- Audit Records

Renderers never access:

- Dataset
- Knowledge Graph
- Rule Engine

Renderers present information.

They never generate it.

---

# 8.9 Forbidden Dependencies

The following dependencies are prohibited.

| Forbidden Dependency  | Reason                                                       |
| --------------------- | ------------------------------------------------------------ |
| Domain → Statistics   | Domain modules define meaning, not computation.              |
| Domain → Planner      | Domains must not control execution.                          |
| Renderer → Dataset    | Presentation must remain independent of data representation. |
| Statistics → Renderer | Mathematical computation must remain presentation-agnostic.  |
| Validation → Domain   | Validation is structural, not semantic.                      |
| CLI → Statistics      | CLI coordinates execution only.                              |

---

# 8.10 Architectural Independence

Each subsystem shall be independently:

- compilable,
- testable,
- benchmarkable,
- documentable.

Subsystems shall communicate through interfaces rather than implementation details.

---

# 9. Architectural Layers in Detail

## 9.1 Dataset Engine

### Purpose

The Dataset Engine is responsible for constructing immutable datasets from supported external sources.

### Inputs

- CSV
- Excel
- JSON
- SQL
- Arrow
- Parquet

### Outputs

- Dataset

### Responsibilities

- ingestion
- normalisation
- source abstraction
- internal representation

The Dataset Engine performs no validation.

---

## 9.2 Validation Engine

### Purpose

Verify structural correctness.

### Responsibilities

- schema validation
- datatype validation
- missing values
- duplicate detection
- constraints
- integrity

Outputs:

- Validation Report

---

## 9.3 Structural Inference Engine

### Purpose

Construct Structural Knowledge.

Responsibilities include:

- datatype inference
- identifiers
- categorical variables
- continuous variables
- temporal variables
- distributions
- relationships

Output:

- Structural Knowledge

---

## 9.4 Knowledge Engine

### Purpose

Construct the Knowledge Graph.

Responsibilities include:

- integrating Structural Knowledge,
- integrating Domain Facts,
- resolving relationships,
- maintaining semantic consistency.

Output:

- Knowledge Graph

---

## 9.5 Capability Engine

### Purpose

Determine mathematically valid analytical capabilities.

Responsibilities include:

- capability discovery,
- mathematical applicability,
- statistical applicability,
- visualisation eligibility.

Output:

- Capability Registry

---

## 9.6 Rule Engine

### Purpose

Transform knowledge into analytical intent.

Input:

- Knowledge Graph
- Capability Registry

Output:

- analytical decisions

The Rule Engine contains no executable mathematics.

---

## 9.7 Analysis Planner

### Purpose

Construct immutable Analysis Graphs.

Responsibilities:

- dependency resolution,
- execution ordering,
- optimisation,
- scheduling.

Output:

- Analysis Graph

---

## 9.8 Execution Engine

### Purpose

Execute Analysis Graphs.

Responsibilities:

- task scheduling,
- concurrency,
- execution,
- caching,
- resource coordination.

Outputs:

- analytical results,
- execution metrics.

---

## 9.9 Statistics Engine

### Purpose

Provide deterministic statistical computation.

Responsibilities:

- descriptive statistics,
- inferential statistics,
- regression,
- correlation,
- hypothesis testing,
- time-series analysis.

The Statistics Engine never interprets business meaning.

---

## 9.10 Mathematics Engine

### Purpose

Provide deterministic mathematical computation.

Responsibilities include:

- algebra,
- matrix operations,
- numerical methods,
- optimisation,
- interpolation.

The Mathematics Engine remains domain-agnostic.

---

## 9.11 Visualisation Planner

### Purpose

Determine the most appropriate visualisation strategy.

Inputs:

- Analysis Graph
- Analytical Results
- Capability Registry

Outputs:

- Visualisation Specification

The Visualisation Planner recommends visualisations.

It does not render them.

---

## 9.12 Reporting Engine

### Purpose

Construct complete analytical reports.

Reports integrate:

- results,
- diagnostics,
- audit summaries,
- visualisations,
- assumptions.

---

## 9.13 Diagnostics Engine

### Purpose

Collect and manage all diagnostics.

The Diagnostics Engine is the exclusive authority responsible for diagnostic presentation.

---

## 9.14 Audit Engine

### Purpose

Produce complete execution provenance.

The Audit Engine records:

- execution history,
- applied rules,
- computations,
- timings,
- software versions,
- reproducibility information.

---

# 9.15 Architectural Principle

Each subsystem has exactly one responsibility.

No subsystem shall duplicate the responsibility of another subsystem.

Responsibilities shall remain stable across future versions of the platform.

---

# 10. Knowledge and Reasoning Model

## 10.1 Purpose

The Knowledge and Reasoning Model is the intellectual core of RASICA.

Its purpose is to transform validated data into analytical decisions through deterministic reasoning.

Unlike conventional analytical software, RASICA separates:

- data,
- knowledge,
- reasoning,
- execution.

This separation is fundamental to maintaining determinism, explainability, extensibility, and long-term maintainability.

---

# 10.2 Separation of Concerns

RASICA distinguishes four independent concepts.

| Concept   | Question Answered                      |
| --------- | -------------------------------------- |
| Dataset   | What data exists?                      |
| Knowledge | What is known about the data?          |
| Reasoning | What conclusions can be drawn?         |
| Execution | How are those conclusions carried out? |

These concepts shall remain independent.

---

# 10.3 Knowledge Lifecycle

Knowledge evolves through a deterministic sequence.

```text
Dataset

↓

Validation

↓

Structural Knowledge

↓

Domain Knowledge

↓

Knowledge Graph

↓

Capability Discovery

↓

Reasoning

↓

Analysis Graph

↓

Execution
```

Each stage produces immutable outputs.

---

# 10.4 Structural Knowledge

Structural Knowledge is produced exclusively by the Core Engine.

It represents objective characteristics of the dataset.

Examples include:

- data types,
- nullability,
- identifiers,
- uniqueness,
- distributions,
- temporal fields,
- categorical variables,
- numerical variables,
- relationships inferred from structure.

Structural Knowledge never contains business semantics.

---

# 10.5 Domain Knowledge

Domain Knowledge is produced exclusively by Domain Modules.

Examples include:

- Revenue
- Profit
- Sales
- Customer
- Product
- Machine
- Temperature
- Blood Pressure
- Inventory

Domain Knowledge extends Structural Knowledge without modifying it.

---

# 10.6 Knowledge Graph

The Knowledge Graph is the canonical semantic representation of the analytical model.

Every discovered entity becomes a node.

Every relationship becomes an edge.

Example

```text
Revenue

│

generated_by

│

Customer



Revenue

│

measured_over

│

Date



Product

│

belongs_to

│

Category
```

The graph stores facts.

It performs no reasoning.

---

# 10.7 Knowledge Graph Principles

The Knowledge Graph shall satisfy the following principles.

### Immutable

The graph is immutable after construction.

---

### Deterministic

Identical datasets shall generate identical graphs.

---

### Domain Neutral

The graph stores domain knowledge.

It does not execute domain logic.

---

### Explainable

> **[2.1]** "Confidence" is replaced with "derivation strength" — a deterministic classification (e.g. `StructurallyCertain`, `DomainAsserted`, `Inferred`), not a probability estimate — for the same reason as §11.10: RASICA's principles prohibit probabilistic reasoning from influencing analytical conclusions, and an unqualified "confidence" value reads as exactly that.

Every relationship must identify:

- origin,
- derivation strength (a deterministic classification of how the relationship was established, not a probability),
- contributing rules,
- contributing metadata.

---

# 10.8 Knowledge Graph Responsibilities

The Knowledge Graph is responsible for representing:

- entities,
- metrics,
- dimensions,
- hierarchies,
- relationships,
- dependencies,
- semantic associations.

The graph is **not** responsible for:

- execution,
- statistics,
- mathematics,
- visualisation.

---

# 10.9 Capability Discovery

Knowledge alone does not determine analytical possibilities.

Capabilities describe what operations are valid.

Examples

Revenue

supports

- Trend
- Growth
- Moving Average
- Forecast
- Contribution Analysis

Customer

supports

- Segmentation
- Distribution
- Cohort Analysis

Age

supports

- Mean
- Median
- Variance
- Histogram
- Regression

Capabilities are derived from:

- structural properties,
- semantic properties,
- mathematical validity.

---

# 10.10 Capability Registry

The Capability Registry is the authoritative catalogue of analytical capabilities.

It answers one question:

> "What operations are valid?"

It does **not** answer:

> "Which operations should be executed?"

---

## Responsibilities

The Capability Registry stores:

- statistical capabilities,
- mathematical capabilities,
- transformation capabilities,
- visualisation capabilities.

---

# 10.11 Rule Engine

The Rule Engine is responsible for analytical reasoning.

It transforms knowledge into analytical intent.

The Rule Engine never performs computation.

---

## Inputs

The Rule Engine consumes:

- Knowledge Graph,
- Capability Registry,
- Domain Rules,
- Configuration.

---

## Outputs

The Rule Engine produces:

- analytical recommendations,
- execution prerequisites,
- visualisation recommendations,
- dependency relationships.

---

# 10.11A Rule Engine Evaluation Algorithm

> **[2.1]** Revision 2.0 stated that reasoning is "declarative" without specifying an evaluation algorithm, conflict resolution strategy, or termination guarantee. This was the single largest open design gap in the platform, since it is the mechanism §10.1 calls "the intellectual core of RASICA." This section closes that gap.

## Evaluation Strategy

The Rule Engine is a **deterministic, stratified, forward-chaining production system**. It evaluates to a fixed point in a bounded number of passes:

1. **Fact base initialisation.** The working fact base is initialised from the Knowledge Graph and Capability Registry. Every fact is an immutable, typed, addressable statement (e.g. `HasNumericColumn("Revenue")`, `HasTemporalColumn("Date")`, `EntityRelationship("Revenue", "generated_by", "Customer")`).
2. **Stratification at registration time.** Every Rule declares the fact types it reads (its condition) and the fact types it may produce (its action). At Domain Module registration (§11.8), the Rule Engine builds a dependency graph over fact types and verifies it is acyclic. A Rule whose action could re-satisfy its own or an earlier stratum's condition is rejected at registration with a diagnostic identifying the cycle. This guarantees termination: evaluation cannot loop, because no fact type may depend on itself, directly or transitively.
3. **Stratum-ordered evaluation.** Rules are grouped into strata by the dependency graph from step 2 (a standard topological stratification). The engine evaluates stratum 0 first (rules whose conditions depend only on the initial fact base), adds every produced fact to the working fact base, then evaluates stratum 1 (rules that may now also depend on stratum 0's output), and so on, until the final stratum is evaluated exactly once. No stratum is revisited.
4. **Within a stratum, deterministic ordering.** All Rules within the same stratum are evaluated in a single fixed order: ascending by `(priority, rule_id)`, where `priority` is a required, explicit `u16` declared on every Rule (§10.12) and `rule_id` is the Rule's globally unique, stable string identifier. This ordering is total — no two Rules in the same stratum may share both the same priority and the same identifier — so the evaluation order is fully determined by the Rule set alone, independent of Domain Module load order, thread count, or hash-map iteration order.
5. **Fixed point.** Evaluation is complete when the final stratum has been evaluated once. Because the fact-type dependency graph is acyclic (step 2), this is always reached in a number of passes bounded by the number of strata, which is itself bounded by the number of distinct fact types — not by dataset size or the number of active Domain Modules.

## Rule Grammar

A Rule is a value of the following canonical shape (see Appendix G for the corresponding Rust trait):

```text
Rule {
    id:        RuleId,            // globally unique, stable across versions
    priority:  u16,                // explicit; lower value evaluates first within a stratum
    reads:     Set<FactType>,      // condition fact types (stratification input)
    produces:  Set<FactType>,      // action fact types (stratification input)
    suppresses: Set<FactType>,     // declared contradiction relationships (see Conflict Resolution, below)
    condition: Predicate,          // pure, side-effect-free function over the fact base
    action:    FactTemplate,       // pure function producing zero or more new facts
}
```

`Predicate` and `FactTemplate` shall be pure functions: given the same fact base, they shall always evaluate to the same result, shall not perform I/O, and shall not depend on wall-clock time, random state, or thread-local state. This is what makes Rule Engine determinism a property of the Rule set itself, independently checkable by unit-testing a Rule against a fixed fact base (§14.13).

## Conflict Resolution

Two or more Rules may become simultaneously satisfied within the same stratum. This is not an error — RASICA permits multiple analytical recommendations to be produced from the same knowledge. "Conflict," for the purposes of this section, refers specifically to two Rules that would produce **contradictory** facts (e.g. one Rule recommending an analysis and another recommending its suppression for the same target). Contradictory fact types must be declared as such at registration (a `Suppresses(FactType)` relationship declared on the Rule). When a contradiction is detected during evaluation:

- the Rule with the lower `(priority, rule_id)` tuple wins, per the same total order defined in step 4;
- the suppressed fact and the winning fact are both recorded in the Audit Record, together with the identifiers of both contributing Rules, so the resolution is explainable (§4.3) rather than silent;
- this resolution is deterministic and requires no probabilistic weighting, satisfying Principle 1 and Principle 2.

## Multi-Domain Rule Interaction

Rules contributed by different Domain Modules are not evaluated in separate namespaces; they are merged into one fact-type dependency graph at registration (step 2). This means a Rule contributed by the Finance Domain may legitimately read a fact type produced by a Rule from the Business Domain, provided the resulting graph remains acyclic. This is the concrete mechanism behind the previously unspecified claim in §11.11 that "the Rule Engine reasons over the combined Knowledge Graph": it is stratified evaluation over a fact-type graph that is agnostic to which Domain Module contributed which Rule.

---

# 10.12 Rules

Rules are declarative: authors write the `condition` predicate and `action` template described in §10.11A, not an imperative evaluation order.

Conceptual example

```text
Rule {
    id: "business.revenue_trend",
    priority: 100,
    reads: { HasNumericColumn, HasTemporalColumn },
    produces: { RecommendedAnalysis },
    condition: HasNumericColumn("Revenue") AND HasTemporalColumn("Date"),
    action: emit RecommendedAnalysis("Revenue Trend Analysis")
}
```

Another example

```text
Rule {
    id: "business.profitability",
    priority: 100,
    reads: { HasNumericColumn },
    produces: { RecommendedAnalysis },
    condition: HasNumericColumn("Revenue") AND HasNumericColumn("Cost"),
    action: emit RecommendedAnalysis("Profitability Analysis")
}
```

Rules describe reasoning.

They never execute mathematics.

---

# 10.13 Rule Principles

Every Rule shall be:

- deterministic (pure `condition` and `action`, per §10.11A),
- declarative,
- assigned an explicit, stable `priority` and globally unique `id` (§10.11A),
- acyclic with respect to the fact-type dependency graph (verified at registration, §10.11A),
- independently testable against a fixed fact base,
- independently documentable,
- explainable,
- version controlled.

---

# 10.14 Rule Evaluation

Rule evaluation occurs after:

- validation,
- structural inference,
- domain inference,
- capability discovery.

Rule evaluation shall never occur before complete knowledge construction, and proceeds via the stratified, fixed-point algorithm defined in §10.11A.

---

# 10.14A Rule Engine and Knowledge Graph Indexing Requirements

> **[2.1]** This subsection closes a scalability gap: as the number of active Domain Modules and the width of a dataset grow, naive linear scanning of the Knowledge Graph and Capability Registry during Rule condition evaluation would degrade evaluation cost from the bound described in §10.11A step 5 into one that scales with dataset width and Domain Module count multiplicatively.

- The Knowledge Graph shall provide indexed lookup by fact type and by entity name with average-case complexity no worse than O(log n) in the number of facts of that type; linear full-graph scans per Rule condition are prohibited.
- The Capability Registry shall provide indexed lookup by entity and by capability category.
- A Rule's `condition` (§10.11A) shall express its dependencies declaratively enough that the engine can pre-filter candidate facts using these indexes rather than evaluating the predicate against the entire fact base.
- The Rule Engine shall track, as an Execution Metric (§13.15), the number of fact-base lookups performed per stratum, so that a Rule set or Domain Module combination that degrades toward linear-scan behaviour is visible in benchmarking (§14.15) rather than discovered only under production load.

---

# 10.15 Analysis Recommendation

Rules generate analytical intent.

Example

```text
Knowledge

↓

Rule Evaluation (stratified, fixed-point — §10.11A)

↓

Recommended Analyses

↓

Planner
```

The Rule Engine never determines execution order.

---

# 10.16 Analysis Planner

The Analysis Planner converts analytical intent into executable plans.

Responsibilities include:

- dependency discovery,
- execution ordering,
- optimisation,
- graph construction.

Output:

Analysis Graph.

---

# 10.17 Analysis Graph

The Analysis Graph represents the complete analytical workflow.

Conceptually

```text
Revenue Trend

↓

Moving Average

↓

Growth Rate

↓

Forecast

↓

Visualisation
```

Every node represents an analytical operation.

Every edge represents a dependency.

---

# 10.18 Analysis Graph Principles

The Analysis Graph shall be:

- immutable,
- deterministic,
- acyclic,
- explainable,
- reproducible.

Every node must identify:

- originating rule,
- originating capability,
- originating knowledge.

---

# 10.19 Event Bus

> **[2.1]** Revision 2.0 described events as though they triggered the next pipeline stage (e.g. "Structural Inference Begins" occurring *because of* an event), which would make the Event Bus a second, competing control-flow mechanism alongside the direct dependency graph in §8.3. RASICA has exactly one control-flow mechanism: the synchronous call chain defined by §8.3, orchestrated by the Application Controller. The Event Bus is an **observability side-channel**: every stage transition in that call chain additionally emits an event, but no subsystem waits on or is invoked by an event. This section is rewritten to make that explicit.

The Application Controller drives the Execution Lifecycle (§10.21) by calling each subsystem directly, in the order fixed by the dependency graph (§8.3). As each stage completes, the controller publishes a corresponding event to the Event Bus. Diagnostics, Audit, and progress-reporting subscribers consume these events; no analytical subsystem subscribes to the Event Bus as a trigger for its own execution.

Example (observability projection of the real, directly-invoked call sequence):

```text
Application Controller calls Validation Engine
        │
        ▼ (on completion, publish)
   Event: Validation Complete
        │
Application Controller calls Structural Inference Engine
        │
        ▼ (on completion, publish)
   Event: Knowledge Graph Complete
        │
Application Controller calls Rule Engine
        │
        ▼ (on completion, publish)
   Event: Rule Evaluation Complete
        │
Application Controller calls Analysis Planner
        │
        ▼ (on completion, publish)
   Event: Analysis Graph Ready
        │
Application Controller calls Execution Engine
```

Removing any subscriber from the Event Bus shall never change which analytical operations run, in what order, or with what result — only which observability information is available. This is the test used to verify that an event has not silently become a control-flow dependency.

---

# 10.20 Event Principles

Events shall be:

- immutable,
- ordered,
- timestamped,
- uniquely identified.

Events communicate state transitions for observability purposes only (Diagnostics, Audit, progress reporting).

They never contain analytical logic, and no subsystem shall condition its own execution on the presence, absence, or content of an event.

---

# 10.21 Execution Lifecycle

Every analytical execution follows the same lifecycle.

```text
Created

↓

Dataset Loaded

↓

Validation

↓

Structural Inference

↓

Domain Inference

↓

Knowledge Graph Complete

↓

Capability Discovery

↓

Rule Evaluation

↓

Planning

↓

Execution

↓

Visualisation Planning

↓

Reporting

↓

Completed
```

Backward transitions are prohibited.

---

# 10.22 Execution State Machine

Every execution shall occupy exactly one state.

Valid transitions are predefined.

Invalid transitions constitute architectural errors.

Example

```text
Created

↓

Loading

↓

Validating

↓

Planning

↓

Executing

↓

Completed
```

Transitions such as

Completed

↓

Validation

are invalid.

---

# 10.23 Deterministic Reasoning

Given identical:

- Dataset,
- Configuration,
- Domain Modules,
- Engine Version,

RASICA shall generate identical:

- Knowledge Graph,
- Capability Registry,
- Rule Evaluation (via the stratified algorithm of §10.11A),
- Analysis Graph,
- Execution Results (subject to the numeric precision profile defined in §4.1 and §12.10).

This deterministic chain defines the reasoning guarantees of the platform.

---

# 10.24 Architectural Principle

The analytical intelligence of RASICA is achieved by separating:

- knowledge acquisition,
- knowledge representation,
- capability discovery,
- reasoning,
- planning,
- execution.

Each stage has a single responsibility.

Each stage produces immutable outputs.

Each stage is independently testable.

This separation enables deterministic, explainable, and extensible analytical reasoning while ensuring that domain knowledge, mathematical correctness, and execution remain independent architectural concerns.

---

# 11. Domain Framework

## 11.1 Purpose

The Domain Framework enables RASICA to remain completely domain-independent while supporting unlimited domain-specific analytical capabilities.

The Core Engine shall never contain domain knowledge.

Instead, domain expertise shall be encapsulated within independent Domain Modules.

The Domain Framework defines the architecture governing the creation, registration, discovery, validation, execution, versioning, and lifecycle of these modules.

---

# 11.2 Architectural Philosophy

The Domain Framework exists to separate **knowledge** from **computation**.

The Core Engine understands:

- mathematics,
- statistics,
- execution,
- planning,
- reasoning.

Domain Modules understand:

- terminology,
- entities,
- business concepts,
- scientific concepts,
- industry relationships.

This separation shall never be violated.

---

# 11.3 Domain Independence

The Core Engine shall remain completely unaware of:

- Revenue
- Profit
- Customer
- Product
- Patient
- Temperature
- Inventory
- Machine
- Loan
- Portfolio

These concepts belong exclusively to Domain Modules.

The Core Engine reasons over abstract knowledge.

It never reasons over business terminology.

---

# 11.4 Domain Module Definition

A Domain Module is an independently deployable component that contributes semantic knowledge to the analytical process.

A Domain Module does not execute analysis.

Instead, it contributes:

- entities,
- metrics,
- dimensions,
- relationships,
- capabilities,
- rules,
- validation extensions,
- visualisation preferences.

---

# 11.5 Responsibilities

Every Domain Module is responsible for:

- semantic interpretation,
- terminology,
- entity discovery,
- metric identification,
- relationship definition,
- domain validation,
- domain capability contribution,
- analytical rule contribution.

A Domain Module shall never:

- execute mathematics,
- execute statistics,
- construct execution plans,
- render reports,
- perform scheduling.

---

# 11.6 Domain Module Lifecycle

Every Domain Module follows the same lifecycle.

```text
Discovery

↓

Validation

↓

Registration

↓

Activation

↓

Knowledge Contribution

↓

Rule Contribution

↓

Execution Complete

↓

Deactivation
```

Each stage shall be deterministic.

---

# 11.7 Domain Discovery

> **[2.1]** Revision 2.0 described "discovery" and "loading" without specifying a mechanism. In Rust, dynamically loading independently-versioned plugins (e.g. via `dylib`/`cdylib` shared libraries) is a well-known source of fragility, because Rust has no stable ABI across compiler versions — a mismatch can silently corrupt memory rather than fail cleanly. §11.18A makes the binding decision: Domain Modules are composed at **compile time**, not discovered from the filesystem at runtime. This section is restated accordingly; "discovery" now refers to build-time registration, not runtime file-system scanning.

At build time, every Domain Module crate registers itself with the Domain Registry using the static registration mechanism defined in §11.18A. "Discovery," for RASICA, is the process — performed once, at Domain Manager initialisation within a running process — of enumerating every Domain Module that was linked into the binary at compile time and verifying, before any dataset is processed:

- compatibility (declared engine version range, §11.17),
- version validity (semantic version well-formedness),
- dependency verification (declared dependencies on Core Types/Domain SDK are present),
- integrity (the module's static registration entry is well-formed and non-duplicate).

Modules failing verification shall not be activated for any execution in that process, and this failure is reported as a startup Diagnostic (§13), not a per-execution one, since the set of linked Domain Modules cannot change without rebuilding the binary.

---

# 11.8 Domain Registration

Validated modules are registered with the Domain Registry.

Registration records:

- module identifier,
- version,
- supported engine versions,
- supported capabilities,
- exported entities,
- exported rules.

Registration is immutable during execution.

---

# 11.9 Domain Activation

Not every registered Domain Module participates in every execution.

Activation occurs only when:

- configuration permits,
- compatibility requirements are satisfied,
- the module's deterministic Applicability Score (§11.10) meets the configured activation threshold.

Inactive modules consume no analytical resources.

---

# 11.10 Applicability Scoring

> **[2.1]** Revision 2.0 named this mechanism "Confidence Evaluation" and expressed it as a percentage (e.g. "98% confidence"), which reads as a probabilistic or ML-style judgment. This directly conflicted with Principle 1 ("Randomized or probabilistic reasoning shall not influence analytical conclusions") and Principle 2 ("no AI dependency"), since domain activation determines which facts and rules enter the Knowledge Graph and therefore does influence conclusions. This section replaces confidence with a fully deterministic, rule-based score, and renames the mechanism accordingly throughout this document.

Every Domain Module declares, as ordinary Rust code reviewed and version-controlled like any other Rule (§10.12), a fixed, deterministic **Applicability Predicate**: a pure function from Structural Knowledge to a score in a bounded integer range (e.g. `0..=100`), computed as an explicit, auditable formula over structural facts — for example, "the count of required entity-shaped columns present, divided by the count required, scaled to the declared range." The formula itself, not a learned or estimated quantity, is the specification; two independent implementations of the same Applicability Predicate against the same dataset shall always produce the same score.

Examples of declared Applicability Predicates (deterministic, not probabilistic):

```text
Business Domain Applicability
  = 100 × (required_business_columns_present / required_business_columns_total)
  → 98

Healthcare Domain Applicability
  = 100 × (required_healthcare_columns_present / required_healthcare_columns_total)
  → 12

Manufacturing Domain Applicability
  = 100 × (required_manufacturing_columns_present / required_manufacturing_columns_total)
  → 7
```

The Domain Manager activates only those modules whose Applicability Score meets or exceeds the configured activation threshold. This prevents irrelevant domains from influencing analysis, using a mechanism that is a pure deterministic function of Structural Knowledge — auditable, unit-testable in isolation against a fixed dataset fixture, and free of any probabilistic or learned component, in accordance with Principle 1 and Principle 2. The chosen threshold and every Domain Module's computed score for a given execution shall be recorded in the Audit Record, so activation is as explainable as any other analytical decision (Principle 6).

---

# 11.11 Multiple Domain Collaboration

RASICA supports simultaneous activation of multiple Domain Modules.

Example

```text
Business

+

Finance

+

Marketing
```

Each module contributes independent knowledge.

The Rule Engine reasons over the combined Knowledge Graph using the stratified evaluation algorithm defined in §10.11A.

No Domain Module may suppress another module's contributed **knowledge** (Domain Facts remain Tier 1 — Immutable, §6.2A, and are never removed or altered once contributed). What can be resolved is a conflict between **rule-derived recommendations** built from that knowledge — for example, two domains both recommending contradictory analyses for the same entity. That conflict is resolved centrally by the Rule Engine's declared `Suppresses` relation and `(priority, rule_id)` ordering (§10.11A), never by one Domain Module reaching into another's contribution.

---

# 11.12 Domain Isolation

Domain Modules shall remain isolated.

A Domain Module shall never:

- directly invoke another Domain Module,
- modify another module's knowledge,
- alter another module's rules,
- access internal implementation details of another module.

Communication occurs exclusively through the Core Engine.

---

# 11.13 Domain Knowledge Contribution

Domain Modules contribute knowledge only.

Examples include:

Entities

- Customer
- Supplier
- Product

Metrics

- Revenue
- Cost
- Profit

Dimensions

- Time
- Geography
- Business Unit

Relationships

- Customer purchases Product
- Product belongs to Category
- Revenue generated by Customer

This knowledge becomes part of the Knowledge Graph.

---

# 11.14 Domain Rules

Domain Modules contribute declarative rules.

Example

```text
Revenue

+

Date

↓

Revenue Trend Analysis
```

Another

```text
Inventory

+

Time

↓

Inventory Turnover Analysis
```

The Domain Module contributes the rule.

The Rule Engine evaluates the rule.

The Planner schedules execution.

---

# 11.15 Domain Validation

Domain Modules may contribute additional validation rules.

Example

Business Domain

- Revenue shall not be negative.

Healthcare Domain

- Patient age shall be non-negative.

Manufacturing Domain

- Machine identifier shall be unique.

Domain validation extends structural validation.

It never replaces it.

---

# 11.16 Domain Versioning

Each Domain Module shall possess an independent version.

Example

| Module     | Version |
| ---------- | ------- |
| Business   | 1.3.2   |
| Finance    | 2.1.0   |
| Healthcare | 4.0.0   |

Domain versions are independent of the Core Engine version.

---

# 11.17 Compatibility

Every Domain Module declares:

- minimum engine version,
- maximum engine version,
- supported SDK version.

Under the compile-time composition model (§11.18A), incompatibility is caught twice: first at build time, where Cargo's dependency resolution typically fails the build outright if a Domain Module's declared engine range excludes the Core Engine version it is compiled against; and again at process startup, where the Domain Manager's discovery check (§11.7) verifies the same declared range as a defence against a Domain Module that compiled successfully but declares a range inconsistent with the running binary's reported version. Modules failing either check shall not be activated.

---

# 11.18 Domain SDK

Every Domain Module shall be implemented exclusively using the Domain SDK.

The SDK defines:

- interfaces,
- contracts,
- lifecycle,
- event handling,
- knowledge contribution,
- rule contribution,
- validation contribution.

The SDK is the only supported extension mechanism.

---

# 11.18A Domain Module Composition Model

> **[2.1]** This subsection did not exist in revision 2.0. It records a binding architectural decision required before any Rust implementation can begin: how Domain Modules are actually loaded. Without it, `rasica-domain-sdk` and the Domain Registry have no concrete contract to implement against.

**Decision: static, compile-time composition.** A Domain Module is an ordinary Rust crate that:

1. Depends on `rasica-domain-sdk` and implements its `DomainModule` trait (Appendix G).
2. Registers itself into a process-wide static registry using a link-time inventory pattern (e.g. the `inventory` or `linkme` crate family), so that every `DomainModule` implementation linked into the final binary is automatically enumerable at startup without hand-maintained registration lists.
3. Is included in a given RASICA binary by being listed as a normal Cargo dependency of that binary's top-level crate (typically `rasica-cli`) — there is no runtime file-system plugin directory, and no `dlopen`-style dynamic loading, anywhere in the Core Engine.

**Consequences of this decision, made explicit so they are not rediscovered as surprises during implementation:**

- The set of available Domain Modules is fixed at build time. Adding a Domain Module requires adding a dependency and rebuilding; it cannot be done by dropping a file into a directory at runtime. This trades runtime extensibility for the elimination of an entire class of Rust ABI-mismatch failure modes.
- Because composition happens at compile time via the Rust type system, a Domain Module cannot violate the trait boundary defined by the Domain SDK — the compiler enforces the isolation described in §11.12 and §11.22, rather than that isolation being an unenforced convention.
- Domain Module "versioning" (§11.16) and "compatibility" (§11.17) are enforced by Cargo's own dependency and semantic-versioning resolution at build time, in addition to the explicit runtime check in §11.7; a Domain Module that is incompatible with the Core Engine version it is compiled against will typically fail to compile, which is a stronger and earlier guarantee than a runtime check alone.
- If a genuine runtime-loadable plugin model is required in the future (for example, to let third parties ship Domain Modules without access to the RASICA source tree), that is a separate, additive architectural capability — most plausibly implemented via a WASM component sandbox rather than native dynamic libraries, to sidestep the ABI problem — and is tracked as a Future Evolution item (Appendix F), not assumed by this document. It would require its own ADR and would not change the Core Engine's dependency graph (§8.3), because the WASM boundary would sit entirely within the Domain Module Framework layer.

---

# 11.19 Reference Domain

The Business Domain shall serve as the reference implementation.

Its purpose is to demonstrate:

- architecture,
- coding standards,
- testing,
- documentation,
- rule development,
- capability definition,
- visualisation recommendations.

Future domains shall follow this reference architecture.

---

# 11.20 Domain Verification

Every Domain Module shall pass an independent verification process.

Verification shall confirm:

- deterministic behaviour,
- rule correctness,
- knowledge correctness,
- capability correctness,
- compatibility,
- documentation,
- performance.

Unverified modules shall not be considered production ready.

---

# 11.21 Domain Testing

Every Domain Module shall include:

- unit tests,
- integration tests,
- rule verification,
- capability verification,
- benchmark datasets,
- regression tests.

Testing standards are identical across all domains.

---

# 11.22 Domain Security

> **[2.1]** Revision 2.0 expressed this section entirely as "shall not" statements with no enforcement mechanism — under a hypothetical dynamic-plugin model, nothing would have actually stopped a misbehaving module from doing these things. Under the compile-time composition model (§11.18A), enforcement is concrete rather than a convention, so this section now states both the rule and the mechanism that makes it true.

Domain Modules execute within the architectural constraints defined by the Core Engine, enforced as follows:

| Constraint | Enforcement Mechanism |
| --- | --- |
| Shall not bypass validation | The Domain SDK exposes no API path from a `DomainModule` implementation to the Execution Engine or Analysis Planner; the Rust type system makes such a call impossible to express, not merely disallowed by convention. |
| Shall not bypass planning | Domain Modules implement `DomainModule` (contributing facts and rules); they hold no reference to the Analysis Planner's types. |
| Shall not alter execution | The Execution Engine accepts only an immutable Analysis Graph (Tier 1, §6.2A) as input; Domain Modules have no handle to Execution Engine internals. |
| Shall not modify analytical results, diagnostics, or audit records | These are Tier 1 (Immutable) or Tier 2 (Append-Only) objects (§6.2A) owned exclusively by their respective engines (§6.17); the Domain SDK exposes no mutable reference to them. |

The Core Engine remains the authoritative execution environment. This trust model assumes Domain Module source code is compiled from within the organisation's build (the compile-time model in §11.18A implies Domain Modules are trusted collaborators, not untrusted third-party input). Should third-party, untrusted Domain Modules become a requirement, the WASM sandbox path noted in §11.18A is the mechanism that would provide isolation against genuinely adversarial code; the trait-boundary enforcement described here does not, by itself, defend against a Domain Module author deliberately trying to escape Rust's safety guarantees via `unsafe` code, which is why §14.5 requires a documented justification for any `unsafe` usage, including within Domain Modules.

---

# 11.23 Domain Governance

Every Domain Module shall provide:

- documentation,
- version history,
- compatibility declaration,
- changelog,
- architecture overview,
- verification report.

This ensures long-term maintainability.

---

# 11.24 Architectural Principle

Domain Modules provide **knowledge**, not **control**.

They describe the world.

They do not determine execution.

This distinction preserves the separation between:

- semantic understanding,
- analytical reasoning,
- execution planning,
- computation.

It is one of the fundamental architectural principles of RASICA.

---

# 12. Analysis and Execution Framework

## 12.1 Purpose

The Analysis and Execution Framework transforms analytical knowledge into deterministic computation.

It is responsible for converting the semantic understanding produced by the Knowledge Layer into an executable analytical workflow.

The framework separates:

- reasoning,
- planning,
- scheduling,
- execution,
- computation.

Each responsibility belongs to an independent subsystem.

---

# 12.2 Architectural Philosophy

RASICA performs analysis in four distinct stages.

```text
Reasoning

↓

Planning

↓

Scheduling

↓

Execution
```

Each stage consumes immutable inputs and produces immutable outputs.

No stage shall modify the output of a previous stage.

---

# 12.3 Analytical Lifecycle

Every execution follows the same lifecycle.

```text
Knowledge Graph

↓

Capability Registry

↓

Rule Evaluation

↓

Analysis Plan

↓

Execution Plan

↓

Task Scheduling

↓

Execution

↓

Results

↓

Visualisation Planning

↓

Report Generation
```

Each stage exists independently.

---

# 12.4 Analysis Planner

## Purpose

The Analysis Planner converts analytical intent into a deterministic execution strategy.

It answers the question:

> **What analytical operations must be performed?**

The Analysis Planner performs no mathematical computation.

---

## Responsibilities

The Analysis Planner is responsible for:

- selecting analytical operations,
- identifying dependencies,
- identifying reusable computations,
- removing duplicate analyses,
- validating analytical completeness,
- constructing the Analysis Graph.

---

## Inputs

The Analysis Planner consumes:

- Knowledge Graph
- Capability Registry
- Rule Engine Output
- Configuration

---

## Outputs

The Analysis Planner produces:

- Analysis Graph

---

# 12.5 Analysis Graph

## Purpose

The Analysis Graph is the canonical representation of analytical intent.

It contains every analytical operation that shall be executed.

---

## Graph Properties

The Analysis Graph shall be:

- immutable,
- deterministic,
- acyclic,
- reproducible,
- explainable.

---

## Graph Nodes

Each node represents a single analytical operation.

Examples

```text
Mean

Variance

Trend

Regression

Forecast

Histogram
```

---

## Graph Edges

Edges represent dependencies.

Example

```text
Revenue

↓

Moving Average

↓

Trend

↓

Forecast
```

Forecast cannot execute before Trend.

Trend cannot execute before Moving Average.

---

# 12.6 Analysis Optimisation

Before execution begins the planner shall optimise the graph.

Optimisations include:

- duplicate removal,
- dependency reduction,
- operation reuse,
- dead-node elimination,
- execution simplification.

Optimisation shall never change analytical meaning.

---

# 12.7 Execution Planner

The Execution Planner converts the Analysis Graph into an executable workflow.

It answers:

> **How should the analytical plan be executed?**

The Execution Planner performs no mathematics.

---

## Responsibilities

The Execution Planner determines:

- execution order,
- task grouping,
- concurrency,
- scheduling,
- resource allocation.

Output:

Execution Plan.

---

# 12.8 Execution Plan

The Execution Plan represents the operational form of the Analysis Graph.

Example

```text
Task 1

↓

Task 2

↓

Task 3

↓

Task 4
```

Tasks may execute sequentially or concurrently depending upon dependency analysis.

---

# 12.9 Scheduler

The Scheduler executes the Execution Plan.

Responsibilities include:

- dependency resolution,
- thread scheduling,
- workload balancing,
- deterministic ordering,
- execution monitoring.

---

# 12.10 Deterministic Scheduling and Deterministic Reduction

> **[2.1]** This section previously asserted identical outputs "regardless of processor count... execution timing" without a mechanism. Floating-point addition is not associative, so parallel reduction order genuinely affects bit-level results; without a defined strategy the claim was not implementable as stated. This section now defines the mechanism that makes both the Logical and Numeric Determinism guarantees of §4.1 achievable.

**Logical determinism under concurrency.** Concurrency (§4.6, §12.17) is permitted only between Analysis Graph nodes that dependency analysis has already proven independent. Because independence is a property of the immutable Analysis Graph (Tier 1, §6.2A) rather than of runtime timing, *which* operations run concurrently is itself deterministic and identical across executions regardless of processor count or operating system. This gives logical determinism unconditionally, as stated in §4.1.

**Numeric determinism under concurrency — Deterministic Reduction Strategy.** Where a single analytical operation aggregates values across a partition (e.g. summation, mean, variance) and that operation is itself parallelized internally, the Execution Engine shall not rely on whatever order threads happen to complete in. Instead:

1. Inputs to any reduction are first partitioned using a fixed, size-based, canonical partitioning scheme (partition boundaries are a pure function of input length and a configured partition size, never of thread scheduling).
2. Each partition is reduced independently, and partial results are combined pairwise in a fixed, canonical tree order determined by partition index — never in the order partitions happen to finish.
3. This produces one deterministic evaluation order for the reduction regardless of how many threads actually executed it, or in what order they completed, satisfying identical-inputs-produce-identical-outputs within a declared numeric precision profile (§4.1).

**Precision profiles.** A numeric precision profile identifies the floating-point behaviour of the target build (e.g. `f64` with no fused-multiply-add assumed, or a defined SIMD width). The Deterministic Reduction Strategy guarantees bit-identical results across runs *within* a pinned profile. It does not by itself guarantee bit-identical results across two builds compiled for different profiles — that stronger guarantee is out of scope unless a specific profile is mandated for release builds via ADR.

This section, together with §4.1, replaces the earlier unconditional cross-architecture bit-identical claim with a precise, implementable, and independently testable one.

---

# 12.11 Resource Manager

The Resource Manager controls computational resources.

Responsibilities include:

- CPU allocation,
- thread management,
- memory management,
- temporary storage,
- cache management.

The Resource Manager never performs analytical reasoning.

---

# 12.12 Execution Engine

## Purpose

The Execution Engine performs the analytical computations described by the Execution Plan.

It consumes:

- Execution Plan
- Statistics Engine
- Mathematics Engine

It produces:

- analytical results.

---

## Responsibilities

The Execution Engine shall:

- execute tasks,
- monitor progress,
- manage failures,
- coordinate resources,
- emit execution events,
- generate execution metrics.

---

# 12.13 Statistics Engine

The Statistics Engine is responsible exclusively for statistical computation.

Examples include:

- descriptive statistics,
- inferential statistics,
- correlation,
- regression,
- hypothesis testing,
- distributions,
- time-series analysis.

The Statistics Engine never:

- understands business,
- performs planning,
- constructs reports.

---

# 12.14 Mathematics Engine

The Mathematics Engine performs deterministic mathematical computation.

Examples include:

- linear algebra,
- numerical optimisation,
- interpolation,
- matrix operations,
- calculus-based methods,
- numerical solvers.

The Mathematics Engine shall remain domain-independent.

---

# 12.15 Computational Principles

All computational engines shall satisfy:

- deterministic behaviour,
- numerical correctness,
- reproducibility,
- independent verification,
- benchmark validation.

---

# 12.16 Intermediate Results

Intermediate analytical results may be cached.

Caching shall never affect:

- correctness,
- determinism,
- explainability.

Cached results shall always be identifiable.

---

# 12.17 Parallel Execution

Independent analytical operations may execute concurrently.

Example

```text
Revenue Statistics

─────────────┐

             ├── Parallel

Customer Analysis

─────────────┘
```

Parallel execution is permitted only when dependency analysis confirms independence.

---

# 12.18 Execution Monitoring

The Execution Engine shall monitor:

- execution progress,
- task completion,
- failures,
- timing,
- resource consumption.

Monitoring information contributes to:

- Diagnostics,
- Audit Records,
- Performance Reports.

---

# 12.19 Failure Recovery

Recoverable failures shall be isolated whenever analytical integrity permits.

Examples include:

- renderer failures,
- optional visualisations,
- report export failures.

Analytical failures that compromise correctness shall terminate execution safely.

---

# 12.20 Execution Events

The Execution Engine publishes events throughout execution.

Examples

```text
Execution Started

↓

Task Scheduled

↓

Task Started

↓

Task Completed

↓

Task Failed

↓

Execution Finished
```

Events are consumed by:

- Diagnostics Engine,
- Audit Engine,
- Progress Reporting.

---

# 12.21 Execution Metrics

Every execution shall record:

- execution duration,
- memory usage,
- thread utilisation,
- task durations,
- cache utilisation,
- throughput.

These metrics are informational only.

They never influence analytical conclusions.

---

# 12.22 Deterministic Execution Guarantee

> **[2.1]** Restated in terms of the two-tier determinism model (§4.1) so this guarantee no longer overstates cross-architecture numeric identity.

The Execution Framework guarantees that, given identical Dataset, Configuration, Domain Modules, and Engine Version:

- RASICA shall select and execute identical analytical operations, in logically identical order, unconditionally (Logical Determinism, §4.1) — this holds regardless of thread scheduling, processor count, or operating system;
- RASICA shall produce bit-identical computed values within a pinned numeric precision profile (Numeric Determinism, §4.1), via the Deterministic Reduction Strategy (§12.10) — this holds regardless of thread scheduling or processor count, for builds targeting the same profile.

This guarantee remains valid regardless of implementation details such as thread scheduling. Cross-architecture bit-identical numeric output additionally requires pinning a numeric precision profile, as defined in §4.1 and §12.10.

---

# 12.23 Architectural Principle

The Analysis and Execution Framework separates analytical intent from computational execution.

Reasoning determines **what should happen**.

Planning determines **how it should be organised**.

Scheduling determines **when tasks should execute**.

Execution performs **the computation**.

Maintaining this separation ensures that analytical correctness, computational efficiency, and architectural clarity evolve independently.

---

# 13. Diagnostics, Auditing and Observability

## 13.1 Purpose

Diagnostics, auditing, and observability are first-class architectural subsystems within RASICA.

They exist to ensure that every execution is:

- explainable,
- reproducible,
- traceable,
- verifiable,
- auditable.

Unlike conventional applications where diagnostics are implementation concerns, RASICA treats them as analytical artefacts.

Every execution shall produce sufficient evidence to explain:

- what happened,
- why it happened,
- how it happened,
- what assumptions were made,
- what rules were applied,
- what conclusions were reached.

---

# 13.2 Observability Philosophy

Observability within RASICA is divided into four independent concerns.

| Concern     | Question Answered                |
| ----------- | -------------------------------- |
| Diagnostics | What happened?                   |
| Audit       | What exactly did the engine do?  |
| Metrics     | How efficiently was it executed? |
| Logging     | What technical events occurred?  |

These concerns shall remain independent.

---

# 13.3 Diagnostics Engine

## Purpose

The Diagnostics Engine is responsible for collecting, managing, classifying, and presenting all diagnostic information generated during execution.

Every subsystem reports diagnostic events.

Only the Diagnostics Engine communicates them to users.

---

## Responsibilities

The Diagnostics Engine shall:

- collect diagnostic events,
- classify severity,
- enrich context,
- correlate related events,
- remove duplicates,
- prioritise presentation,
- generate execution summaries,
- provide structured outputs.

---

## Diagnostic Sources

Diagnostics may originate from:

- Dataset Engine
- Validation Engine
- Structural Inference Engine
- Domain Framework
- Rule Engine
- Planner
- Execution Engine
- Statistics Engine
- Mathematics Engine
- Reporting Engine
- Renderer

All diagnostics are centralised before presentation.

---

# 13.4 Diagnostic Lifecycle

Every diagnostic follows the same lifecycle.

```text
Condition Detected

↓

Diagnostic Event

↓

Classification

↓

Context Enrichment

↓

Correlation

↓

Aggregation

↓

Presentation

↓

Archival
```

---

# 13.5 Diagnostic Severity

Diagnostics shall be classified according to severity.

| Severity          | Meaning                                          |
| ----------------- | ------------------------------------------------ |
| Information       | Contextual information                           |
| Suggestion        | Recommended improvement                          |
| Warning           | Potential issue that does not invalidate results |
| Recoverable Error | Partial recovery possible                        |
| Critical Error    | Analytical integrity compromised                 |
| Internal Failure  | Software defect                                  |

Severity classification is deterministic.

---

# 13.6 Diagnostic Structure

Every diagnostic shall include:

- unique identifier,
- originating subsystem,
- severity,
- category,
- summary,
- detailed description,
- probable cause,
- affected data,
- recommended action,
- execution context,
- timestamp,
- engine version.

No public diagnostic may omit these fields where applicable.

---

# 13.7 Diagnostic Categories

Diagnostics shall be categorised.

Categories include:

- Input
- Validation
- Structural
- Domain
- Capability
- Rule
- Planning
- Execution
- Statistical
- Mathematical
- Visualisation
- Rendering
- Internal

Future categories may be introduced without affecting existing identifiers.

---

# 13.8 Diagnostic Correlation

Multiple diagnostics originating from a common cause shall be correlated.

Example

```text
Missing Date Column

↓

Temporal Analysis Disabled

↓

Forecast Disabled

↓

Trend Analysis Skipped
```

Rather than displaying four unrelated messages, RASICA shall produce one correlated diagnostic chain.

---

# 13.9 User Diagnostics

User-facing diagnostics shall communicate:

- what happened,
- why,
- what is affected,
- whether execution can continue,
- recommended corrective action.

Messages shall avoid unnecessary implementation details.

---

# 13.10 Developer Diagnostics

Developer diagnostics may additionally include:

- subsystem,
- function,
- source location,
- execution stack,
- dependency chain,
- timing,
- resource usage,
- internal state.

Developer diagnostics are intended solely for debugging.

---

# 13.11 Diagnostic Outputs

Diagnostics shall support multiple presentation formats.

Examples include:

- Terminal
- JSON
- HTML
- Markdown
- PDF
- Structured Logs

Presentation format shall not affect diagnostic content.

---

# 13.12 Audit Engine

## Purpose

The Audit Engine records the complete analytical history of every execution.

Unlike Diagnostics, which explain events, the Audit Engine records the complete provenance of the analysis.

Every execution produces exactly one Audit Record.

---

# 13.13 Audit Record

The Audit Record shall include:

- execution identifier,
- dataset fingerprint,
- metadata fingerprint,
- knowledge graph fingerprint,
- analysis graph fingerprint,
- active Domain Modules,
- rule evaluations,
- executed analyses,
- generated visualisations,
- diagnostics,
- execution timings,
- software versions,
- configuration profile.

The Audit Record is immutable.

---

# 13.14 Fingerprinting

To guarantee reproducibility, RASICA shall generate deterministic fingerprints for critical architectural objects.

Examples include:

- Dataset Fingerprint
- Metadata Fingerprint
- Knowledge Graph Fingerprint
- Analysis Graph Fingerprint
- Report Fingerprint

Fingerprints uniquely identify analytical state.

---

# 13.15 Execution Metrics

Execution Metrics measure platform performance.

Examples include:

- execution duration,
- CPU utilisation,
- memory usage,
- allocations,
- cache efficiency,
- thread utilisation,
- throughput.

Metrics are informational.

They shall never influence analytical reasoning.

---

# 13.16 Logging

Logging records technical events occurring during execution.

Examples include:

- module loading,
- configuration,
- lifecycle transitions,
- resource allocation,
- infrastructure events.

Logging is intended for operational monitoring.

It is not an analytical artefact.

---

# 13.17 Event Bus

## Purpose

> **[2.1]** This section is the Diagnostics/Audit-facing view of the single Event Bus defined authoritatively in §10.19. It is restated here, consistent with §10.19, to avoid this chapter implying a second, independent coordination mechanism.

The Event Bus is the observability side-channel through which the Diagnostics Engine and Audit Engine observe execution progress. Subsystems do not invoke one another via events; control flow follows the direct call chain in §8.3, and the Application Controller publishes one event per stage transition for observability consumers.

Example (observability projection only — see §10.19 for the actual call sequence):

```text
Dataset Loaded

↓

Validation Started

↓

Validation Completed

↓

Knowledge Graph Created

↓

Analysis Planned

↓

Execution Started

↓

Execution Completed

↓

Report Generated
```

---

# 13.18 Event Principles

Every architectural event shall be:

- immutable,
- timestamped,
- uniquely identified,
- ordered,
- traceable.

Events communicate state, for observability purposes only.

They never contain analytical logic, and no subsystem shall condition its own execution on an event (§10.19–10.20).

---

# 13.19 Observability Pipeline

```text
Execution

↓

Events

↓

Diagnostics

↓

Audit

↓

Metrics

↓

Reports
```

Each subsystem contributes information independently.

---

# 13.20 Execution Summary

Every execution shall conclude with a structured execution summary.

The summary shall include:

- execution status,
- active Domain Modules,
- analyses executed,
- visualisations produced,
- diagnostics,
- execution duration,
- audit identifier.

This summary represents the official outcome of the execution.

---

# 13.21 Architectural Principle

Observability is an integral component of analytical integrity.

Every analytical conclusion must be:

- explainable,
- reproducible,
- independently verifiable.

Accordingly, Diagnostics, Auditing, Metrics, and Logging remain independent architectural subsystems whose sole responsibility is to document the analytical process without influencing it.

---

# 14. Engineering Principles and Software Standards

## 14.1 Purpose

This chapter defines the engineering principles governing the design, implementation, testing, maintenance, and evolution of RASICA.

While previous chapters define **what** RASICA is, this chapter defines **how** RASICA shall be engineered.

Every implementation shall comply with these standards.

---

# 14.2 Engineering Philosophy

RASICA shall be engineered as a long-lived analytical platform rather than a short-term software project.

Every design decision shall prioritise:

- correctness,
- maintainability,
- simplicity,
- extensibility,
- determinism,
- testability.

Convenience shall never take precedence over architectural integrity.

---

# 14.3 Software Architecture Principles

The implementation shall adhere to the following architectural principles.

| Principle              | Description                                                                 |
| ---------------------- | --------------------------------------------------------------------------- |
| Single Responsibility  | Every subsystem owns one responsibility.                                    |
| Separation of Concerns | Knowledge, reasoning, execution and presentation remain independent.        |
| Open for Extension     | New capabilities are introduced through extension rather than modification. |
| Dependency Inversion   | High-level components depend on abstractions rather than implementations.   |
| Explicit Interfaces    | Communication occurs only through public contracts.                         |
| Immutability           | Core analytical objects become immutable after creation.                    |

---

# 14.4 Architectural Governance

No implementation shall violate the architectural principles established in this specification.

Examples include:

- bypassing validation,
- bypassing the Rule Engine,
- modifying the Knowledge Graph during execution,
- introducing domain knowledge into the Core Engine,
- allowing presentation layers to influence analysis.

Architectural violations shall be treated as defects.

---

# 14.5 Rust Engineering Principles

RASICA shall follow the Rust API Guidelines and established Rust ecosystem best practices.

Implementation shall favour:

- ownership over shared mutability,
- composition over inheritance,
- traits over tightly coupled implementations,
- explicit error handling,
- exhaustive pattern matching,
- strong type safety,
- zero-cost abstractions.

Unsafe Rust shall be avoided unless a documented architectural justification exists.

---

# 14.6 Workspace Organisation

The implementation shall be organised as a Cargo Workspace.

Each major subsystem shall exist as an independent crate.

Illustrative structure:

```text
rasica-cli

rasica-core

rasica-dataset

rasica-validation

rasica-inference

rasica-knowledge

rasica-capabilities

rasica-rules

rasica-planner

rasica-execution

rasica-statistics

rasica-mathematics

rasica-visualisation

rasica-reporting

rasica-diagnostics

rasica-audit

rasica-domain-sdk

rasica-common
```

No crate shall contain unrelated responsibilities.

---

# 14.7 Dependency Management

Dependencies shall remain explicit.

The project shall avoid:

- circular dependencies,
- hidden dependencies,
- transitive coupling.

Every dependency shall have documented justification.

External libraries shall be selected according to:

- maturity,
- maintenance,
- licensing,
- performance,
- security,
- community adoption.

---

# 14.8 Public APIs

Every public API shall satisfy:

- stability,
- consistency,
- documentation,
- deterministic behaviour,
- backward compatibility where applicable.

Public interfaces shall change only through controlled versioning.

---

# 14.9 Error Handling

Errors are architectural artefacts.

Every subsystem shall expose structured error types.

Errors shall:

- be deterministic,
- preserve context,
- remain machine-readable,
- remain human-readable,
- support propagation without information loss.

Panics shall represent unrecoverable programming defects rather than expected execution conditions.

---

# 14.10 Configuration

Configuration shall remain external to analytical logic.

Configuration may influence:

- execution behaviour,
- performance,
- output formats,
- logging,
- enabled Domain Modules.

Configuration shall never alter mathematical correctness.

---

# 14.11 Documentation Standards

Every public component shall include documentation describing:

- purpose,
- responsibilities,
- inputs,
- outputs,
- constraints,
- examples where appropriate.

Documentation shall evolve alongside implementation.

Undocumented public interfaces are prohibited.

---

# 14.12 Code Review

Every change shall undergo review.

Reviews shall evaluate:

- architectural compliance,
- correctness,
- readability,
- testing,
- documentation,
- performance implications,
- security implications.

Review approval is mandatory before merging.

---

# 14.13 Testing Philosophy

Testing shall verify correctness rather than implementation.

Tests shall demonstrate that architectural behaviour conforms to specification.

Testing categories include:

- unit tests,
- integration tests,
- property-based tests,
- benchmark tests,
- regression tests,
- end-to-end tests.

---

# 14.14 Continuous Integration

Every repository change shall automatically execute:

- compilation,
- formatting,
- linting,
- documentation generation,
- unit tests,
- integration tests,
- benchmark regression checks,
- dependency audits,
- security audits.

Changes failing automated verification shall not be merged.

---

# 14.15 Benchmarking

Performance shall be measured continuously.

Benchmarks shall evaluate:

- ingestion,
- validation,
- inference,
- planning,
- execution,
- rendering.

Performance regressions shall be investigated before release.

---

# 14.16 Versioning

RASICA shall follow Semantic Versioning.

Major versions indicate:

- incompatible architectural changes.

Minor versions indicate:

- backwards-compatible functionality.

Patch versions indicate:

- corrections and maintenance.

Domain Modules and the Core Engine shall be versioned independently.

---

# 14.17 Security

Security considerations include:

- dependency integrity,
- plugin isolation,
- deterministic execution,
- configuration integrity,
- audit integrity.

Security mechanisms shall never compromise determinism.

---

# 14.18 Architecture Decision Records (ADR)

Significant architectural decisions shall be recorded using Architecture Decision Records.

Each ADR shall include:

- decision identifier,
- context,
- alternatives considered,
- chosen solution,
- rationale,
- consequences.

Examples include:

- Why RASICA is deterministic.
- Why Domain Modules are external.
- Why Analysis Graphs are immutable.
- Why the Rule Engine is centralised.
- Why AI is excluded from analytical reasoning.

ADRs provide historical context for future contributors.

---

# 14.19 Release Readiness

A release shall be considered ready only when:

- architectural compliance is verified,
- all acceptance tests pass,
- benchmarks meet targets,
- documentation is complete,
- known critical defects are resolved.

Feature completeness alone shall not constitute release readiness.

---

# 14.20 Architectural Principle

Engineering quality is a core feature of RASICA.

Software architecture, implementation quality, documentation, testing, and governance collectively determine the reliability of the analytical platform.

Accordingly, engineering excellence shall be treated as a functional requirement rather than a secondary concern.

---

# 15. Module Breakdown and Development Roadmap

## 15.1 Purpose

This chapter defines the implementation strategy for RASICA.

The purpose of the roadmap is to ensure that development proceeds in a controlled, deterministic, and architecturally consistent manner.

The roadmap defines:

- implementation phases,
- module dependencies,
- development order,
- milestone objectives,
- acceptance criteria,
- exit criteria.

No module shall begin implementation until all prerequisite milestones have been successfully completed.

---

# 15.2 Development Philosophy

RASICA shall be developed incrementally.

Each completed module becomes a stable foundation for the next.

Development shall prioritise:

- architectural stability,
- correctness,
- deterministic behaviour,
- comprehensive testing,
- complete documentation.

Feature development shall never outpace architectural maturity.

---

# 15.3 Module Dependency Hierarchy

Implementation shall follow the dependency hierarchy shown below.

```text
Core Foundation
       │
       ▼
Dataset Engine
       │
       ▼
Validation Engine
       │
       ▼
Structural Inference Engine
       │
       ▼
Knowledge Engine
       │
       ▼
Capability Engine
       │
       ▼
Rule Engine
       │
       ▼
Analysis Planner
       │
       ▼
Execution Planner
       │
       ▼
Execution Engine
       │
       ▼
Visualisation Planner
       │
       ▼
Reporting Engine
       │
       ▼
Renderers
```

Cross-layer implementation shall be avoided.

---

# 15.4 Phase 1 — Core Foundation

## Objective

Establish the foundational infrastructure upon which every other subsystem depends.

### Deliverables

- Cargo Workspace
- Common crate
- Core traits
- Primitive types
- Configuration framework
- Error framework
- Logging framework
- Testing framework
- Build pipeline

### Exit Criteria

- Project builds successfully.
- CI pipeline operational.
- Documentation framework established.
- Coding standards enforced.

---

# 15.5 Phase 2 — Dataset Engine

## Objective

Create the immutable internal dataset representation.

### Deliverables

- Dataset
- Row
- Column
- Schema
- Metadata containers

### Verification

Demonstrate representation of datasets entirely in memory.

### Exit Criteria

Every supported dataset structure can be represented without ambiguity.

---

# 15.6 Phase 3 — Data Ingestion

## Objective

Support external data sources.

### Initial Sources

- CSV
- Excel
- JSON

### Future Sources

- SQL
- Arrow
- Parquet

### Verification

Import benchmark datasets.

Verify:

- no data loss,
- correct typing,
- correct encoding,
- deterministic import.

### Exit Criteria

Imported datasets match source datasets exactly.

---

# 15.7 Phase 4 — Validation Engine

## Objective

Verify structural correctness.

### Deliverables

- datatype validation,
- schema validation,
- constraint validation,
- duplicate detection,
- null analysis.

### Verification

Inject known faults into benchmark datasets.

Confirm:

- every fault detected,
- no false positives,
- deterministic diagnostics.

### Exit Criteria

Validation accuracy confirmed across all benchmark datasets.

---

# 15.8 Phase 5 — Structural Inference

## Objective

Construct Structural Knowledge.

### Deliverables

Automatic identification of:

- identifiers,
- continuous variables,
- categorical variables,
- temporal variables,
- distributions,
- relationships.

### Verification

Benchmark against manually classified datasets.

### Exit Criteria

Structural inference achieves expected accuracy.

---

# 15.9 Phase 6 — Knowledge Engine

## Objective

Construct the Knowledge Graph.

### Deliverables

- entity graph,
- relationship graph,
- semantic graph.

### Verification

Knowledge graphs generated deterministically.

### Exit Criteria

Identical datasets generate identical Knowledge Graphs.

---

# 15.10 Phase 7 — Capability Engine

## Objective

Determine valid analytical capabilities.

### Deliverables

Capability Registry.

### Verification

Confirm that:

- valid operations are discovered,
- invalid operations are rejected,
- duplicate capabilities eliminated.

### Exit Criteria

Capability Registry verified against specification.

---

# 15.11 Phase 8 — Rule Engine

## Objective

Transform knowledge into analytical intent.

### Deliverables

- Rule evaluation
- Rule execution framework
- Rule verification

### Verification

Representative datasets shall produce expected analytical recommendations.

### Exit Criteria

Rule evaluation is deterministic and reproducible.

---

# 15.12 Phase 9 — Domain Framework

## Objective

Enable external Domain Modules.

### Deliverables

- Domain SDK
- Domain Registry
- Domain Manager (build-time discovery, verification, and activation — §11.7, §11.9, §11.10)

### Verification

Develop and execute a sample Business Domain Module.

### Exit Criteria

Domain Modules operate without modifications to the Core Engine.

---

# 15.13 Phase 10 — Analysis Planner

## Objective

Construct Analysis Graphs.

### Deliverables

- dependency analysis,
- graph construction,
- optimisation.

### Verification

Graphs shall be:

- deterministic,
- acyclic,
- complete,
- explainable.

### Exit Criteria

Analysis Graph accepted.

---

# 15.14 Phase 11 — Execution Planner

## Objective

Transform Analysis Graphs into executable workflows.

### Deliverables

- scheduling,
- dependency ordering,
- resource planning.

### Verification

Execution plans validated against analytical dependencies.

### Exit Criteria

Execution Plans are deterministic.

---

# 15.15 Phase 12 — Statistics Engine

## Objective

Implement deterministic statistical computation.

### Deliverables

Statistical library.

### Verification

Compare results against recognised statistical references.

### Exit Criteria

Numerical correctness confirmed.

---

# 15.16 Phase 13 — Mathematics Engine

## Objective

Implement mathematical algorithms.

### Deliverables

Mathematical library.

### Verification

Benchmark against recognised numerical references.

### Exit Criteria

Accuracy within documented tolerances.

---

# 15.17 Phase 14 — Execution Engine

## Objective

Execute analytical workflows.

### Deliverables

- scheduler,
- task execution,
- concurrency,
- monitoring.

### Verification

Execute representative Analysis Graphs.

### Exit Criteria

Deterministic execution confirmed.

---

# 15.18 Phase 15 — Visualisation Planner

## Objective

Recommend visualisations.

### Deliverables

Visualisation recommendation engine.

### Verification

Recommendations validated against specification.

### Exit Criteria

Visualisation recommendations reproducible.

---

# 15.19 Phase 16 — Reporting Engine

## Objective

Produce complete analytical reports.

### Deliverables

Report generation framework.

### Verification

Reports verified for:

- completeness,
- consistency,
- traceability.

### Exit Criteria

Reports require no manual intervention.

---

# 15.20 Phase 17 — Renderers

## Objective

Support multiple presentation formats.

### Initial Renderers

- Terminal
- Markdown
- HTML

### Secondary Renderers

- SVG
- PNG
- PDF
- JSON

### Verification

Identical reports rendered consistently.

### Exit Criteria

Renderer output verified.

---

# 15.21 Phase 18 — Diagnostics Engine

## Objective

Centralise diagnostics.

### Deliverables

- diagnostic framework,
- severity classification,
- correlation,
- aggregation.

### Verification

Diagnostic outputs remain consistent across renderers.

### Exit Criteria

Every subsystem reports through the Diagnostics Engine.

---

# 15.22 Phase 19 — Audit Engine

## Objective

Produce complete execution provenance.

### Deliverables

Audit framework.

### Verification

Every execution generates one immutable Audit Record.

### Exit Criteria

Audit reproducibility verified.

---

# 15.23 Phase 20 — Optimisation

## Objective

Prepare for production deployment.

### Activities

- profiling,
- benchmarking,
- memory optimisation,
- SIMD optimisation,
- cache optimisation,
- concurrency optimisation.

### Exit Criteria

Version 1.0 performance objectives achieved.

---

# 16. Milestones and Acceptance Gates

## 16.1 Purpose

Each development phase concludes with an acceptance gate.

The objective of an acceptance gate is to verify that implementation is complete, correct, stable, and architecturally compliant before development proceeds.

No milestone shall be considered complete until its acceptance gate has been approved.

---

# 16.2 Acceptance Gate Requirements

Every milestone shall satisfy all of the following:

- Functional requirements completed.
- Architectural review completed.
- Public APIs documented.
- Unit tests passing.
- Integration tests passing.
- Property-based tests passing (where applicable).
- Benchmarks recorded.
- Documentation complete.
- Code review approved.
- No critical defects remain.

---

# 16.3 Definition of Done

A module is considered complete only when:

- implementation is complete,
- verification tests pass,
- acceptance criteria are satisfied,
- documentation is approved,
- benchmarks recorded,
- public interfaces stabilised,
- architectural compliance confirmed.

Completion of code alone does not constitute completion of a milestone.

---

# 16.4 Architecture Freeze

Following acceptance, completed modules enter an Architecture Freeze state.

During this state:

- public interfaces are stable,
- architectural responsibilities are fixed,
- changes require formal review.

Enhancements shall occur through extension rather than redesign.

---

# 16.5 Architecture Decision Records (ADR)

Breaking architectural changes require an Architecture Decision Record.

Each ADR shall document:

- problem statement,
- alternatives considered,
- selected solution,
- rationale,
- consequences,
- compatibility impact.

No architectural change shall occur without an approved ADR.

---

# 16.6 Success Criteria

The first production release of RASICA shall satisfy the following conditions:

- All architectural milestones completed.
- All acceptance gates approved.
- Complete deterministic execution.
- Complete audit trail generation.
- Complete diagnostic reporting.
- Reference Business Domain operational.
- Public SDK available.
- Documentation complete.
- Benchmark targets achieved.
- Zero unresolved critical defects.

Only upon satisfying these criteria shall Version 1.0 be considered production-ready.

---

# 16.7 Architectural Principle

Development shall proceed according to architectural maturity rather than feature count.

Every completed milestone strengthens the foundation upon which subsequent modules are built.

The long-term maintainability and correctness of RASICA shall always take precedence over implementation speed.

---

# 17. Appendices

---

# Appendix A — Architectural Invariants

## Purpose

Architectural Invariants are permanent rules governing the RASICA platform.

Unlike implementation decisions, these rules shall remain unchanged throughout the lifetime of the project unless superseded through a formal Architecture Decision Record (ADR).

Every subsystem, module, contribution, and future enhancement shall comply with these invariants.

Violation of an Architectural Invariant constitutes an architectural defect.

---

## A.1 Core Engine Independence

The Core Engine shall remain completely independent of domain knowledge.

It shall never contain concepts such as:

- Revenue
- Profit
- Customer
- Product
- Patient
- Inventory
- Machine
- Temperature

Domain semantics belong exclusively to Domain Modules.

---

## A.2 Determinism

> **[2.1]** Restated against the two-tier model in §4.1 so this invariant does not overstate cross-hardware numeric identity.

RASICA shall remain deterministic.

Given identical:

- Dataset
- Configuration
- Domain Modules
- Software Version

the platform shall always produce identical:

- Knowledge Graph
- Capability Registry
- Rule Evaluation (Logical Determinism — unconditional, §4.1, §10.11A)
- Analysis Graph
- Execution Results (Numeric Determinism — within a pinned precision profile, §4.1, §12.10)
- Reports
- Diagnostics
- Audit Records

---

## A.3 Analytical Integrity

Users may initiate analysis.

Users shall never determine:

- analytical methods,
- execution order,
- statistical techniques,
- mathematical operations.

RASICA determines these autonomously.

---

## A.4 Mutability Tiers

> **[2.1]** Renamed from "Immutability" and restated against §6.2A, since Diagnostics (Tier 2) and the Execution Context (Tier 3) never fit a strict immutability rule; stating them as an unqualified exception list previously left the invariant self-contradictory alongside caching (§12.16).

Every Core Architectural Object belongs to exactly one Mutability Tier defined in §6.2A:

- **Tier 1 — Immutable** (never changes after construction): Dataset, Metadata, Structural Knowledge, Knowledge Graph, Domain Facts, Capability Registry, Rules, Analysis Graph, Audit Record.
- **Tier 2 — Append-Only** (entries added, never altered or removed): Diagnostics.
- **Tier 3 — Scoped-Mutable** (mutable only within one execution's lifetime, never the source of truth for a conclusion): Execution Context, intermediate Execution Engine caches.

Mutation of a Tier 1 object requires construction of a new object with a new identity; a Tier 1 object shall never be edited in place.

---

## A.5 Separation of Knowledge and Reasoning

Domain Modules contribute knowledge.

The Rule Engine performs reasoning.

The Planner performs planning.

The Execution Engine performs computation.

These responsibilities shall never overlap.

---

## A.6 Explainability

Every analytical decision shall possess a complete chain of reasoning.

Every result shall be traceable to:

- source data,
- inferred knowledge,
- rules,
- mathematical principles.

---

## A.7 Auditing

Every execution shall produce exactly one Audit Record.

No execution shall occur without complete provenance.

---

## A.8 Diagnostics

Every subsystem shall report diagnostics exclusively through the Diagnostics Engine.

No subsystem shall generate user-facing diagnostic output directly.

---

## A.9 Domain Isolation

Domain Modules shall never:

- execute analytical computation,
- modify analytical results,
- alter execution plans,
- communicate directly with one another.

All coordination occurs through the Core Engine, enforced by the compile-time trait boundary defined in §11.18A and the enforcement table in §11.22.

---

## A.10 AI Independence

Artificial Intelligence shall never participate in the deterministic analytical pipeline.

Future AI integrations, if introduced, shall operate solely as optional advisory systems external to the Core Engine.

---

# Appendix B — Design Principles Summary

The architecture of RASICA is governed by the following principles.

| Principle              | Description                                                                                                                         |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Determinism            | Identical inputs always produce identical logical outputs; numeric outputs are identical within a pinned precision profile (§4.1).  |
| Modularity             | Components evolve independently.                                                                                                    |
| Explainability         | Every conclusion is traceable.                                                                                                       |
| Reproducibility        | Every execution is repeatable.                                                                                                       |
| Separation of Concerns | Knowledge, reasoning, planning and execution remain independent.                                                                    |
| Domain Independence    | Domain knowledge exists only within Domain Modules.                                                                                  |
| Extensibility          | New capabilities are added through extension rather than modification.                                                              |
| Mutability Tiers       | Every Core Architectural Object is Tier 1 Immutable, Tier 2 Append-Only, or Tier 3 Scoped-Mutable (§6.2A).                            |
| Testability            | Every subsystem is independently verifiable.                                                                                         |
| Auditability           | Every execution produces complete provenance.                                                                                        |

---

# Appendix C — Core Terminology

The following definitions constitute the official vocabulary of the RASICA platform. Terms marked **(Object)** are Core Architectural Objects assigned a Mutability Tier under §6.2A; terms marked **(Subsystem)** are engines/components that create, consume, or transform those objects; the term marked **(Artifact)** is an internal operational artifact that is neither a Tier-classified object nor a subsystem.

| Term                 | Kind       | Definition                                                 |
| -------------------- | ---------- | ----------------------------------------------------------- |
| Dataset              | Object     | Immutable internal representation of ingested data.        |
| Metadata             | Object     | Structural description of a Dataset.                       |
| Validation Report    | Object     | Immutable record of every validation activity performed on a Dataset (§6.6). |
| Structural Knowledge | Object     | Facts inferred from dataset structure.                     |
| Domain Fact          | Object     | Semantic knowledge supplied by a Domain Module.             |
| Knowledge Graph      | Object     | Canonical semantic representation of analytical knowledge. |
| Capability           | Concept    | A mathematically valid analytical operation.                |
| Capability Registry  | Object     | Catalogue of supported analytical capabilities.             |
| Rule                 | Object     | Declarative reasoning statement.                            |
| Rule Engine          | Subsystem  | Deterministic reasoning subsystem that evaluates Rules (§10.11A). |
| Analysis Graph       | Object     | Immutable analytical workflow.                              |
| Execution Context    | Object     | Tier 3 — Scoped-Mutable runtime environment for one analytical execution (§6.13). |
| Execution Plan       | Artifact   | Operational representation of the Analysis Graph produced by the Execution Planner (§12.8) for scheduling purposes; not itself a Tier-classified Core Architectural Object under §6.2A. |
| Diagnostic           | Object     | Structured description of analytical events (Tier 2 — Append-Only as the Diagnostics collection, §6.2A). |
| Audit Record         | Object     | Immutable execution history.                                |
| Report               | Object     | Final analytical presentation.                              |

These definitions shall remain consistent across all future specifications.

---

# Appendix D — Repository Structure

The recommended repository organisation is shown below.

```text
rasica/

├── architecture/
│
├── specifications/
│
├── docs/
│
├── crates/
│   ├── rasica-cli/
│   ├── rasica-core/
│   ├── rasica-common/
│   ├── rasica-dataset/
│   ├── rasica-validation/
│   ├── rasica-inference/
│   ├── rasica-knowledge/
│   ├── rasica-capabilities/
│   ├── rasica-rules/
│   ├── rasica-planner/
│   ├── rasica-execution/
│   ├── rasica-statistics/
│   ├── rasica-mathematics/
│   ├── rasica-visualisation/
│   ├── rasica-reporting/
│   ├── rasica-diagnostics/
│   ├── rasica-audit/
│   └── rasica-domain-sdk/
│
├── domains/
│   ├── business/
│   ├── finance/
│   ├── healthcare/
│   ├── manufacturing/
│   └── examples/
│
├── datasets/
│
├── benchmarks/
│
├── tests/
│
└── tools/
```

The repository structure may evolve provided architectural boundaries remain intact.

> **Note:** The `domains/` folder above lists a starting subset of reference and example Domain Modules, not an exhaustive or authoritative list of supported domains. §1.3 defines the full range of potential application areas; new domains are added as new crates under `domains/` without modifying `crates/` (§4.5).

---

# Appendix E — Documentation Hierarchy

The RASICA documentation shall be organised as follows.

```text
00 Architecture Specification

01 Glossary

02 Software Requirements Specification

03 Core Object Model

04 Dataset Specification

05 Validation Specification

06 Structural Inference Specification

07 Knowledge Engine Specification

08 Capability Engine Specification

09 Rule Engine Specification

10 Domain SDK Specification

11 Analysis Planner Specification

12 Execution Planner Specification

13 Execution Engine Specification

14 Statistics Specification

15 Mathematics Specification

16 Visualisation Planner Specification

17 Reporting Specification

17A Renderer Specification

18 Diagnostics Specification

19 Audit Specification

20 Coding Standards

21 Testing Standards

22 Contributor Guide

23 Architecture Decision Records

24 Non-Functional Requirements & Benchmarking Specification
```

Each specification shall define one architectural concern only.

> **[2.1]** Item 24 is new in this revision, added to give Appendix H's Non-Functional Requirements Baseline and §14.15's Benchmarking a home of their own, distinct from Testing Standards (21), which governs correctness rather than performance.

> **[2.1]** Item 17A is new in this revision. Renderers are a distinct subsystem with their own dependency rules (§8.8) and their own roadmap phase (§15.20), but had no corresponding module specification, leaving their contract to be defined ad hoc inside the Reporting Specification (17) — the very subsystem §8.8 and §8.9 require Renderers to remain decoupled from. Item 17A is lettered rather than assigned the next whole number so that Items 18–24 do not need renumbering.

---

# Appendix F — Future Evolution

The architecture has been designed to support future capabilities without redesigning the Core Engine.

Potential future extensions include:

- Streaming datasets (permitted without redesign per the logical/physical immutability distinction in §6.4)
- Distributed execution
- Cloud-native deployment
- REST API
- GraphQL API
- Web interface
- Desktop interface
- Notebook integration
- GPU acceleration
- Distributed scheduling
- Real-time analytics
- Optional AI advisory services
- Additional Domain Modules (compiled in per §11.18A; see below for a runtime-loadable alternative)
- Runtime-loadable, sandboxed third-party Domain Modules via a WASM component model, as an additive capability alongside — not a replacement for — the compile-time model in §11.18A

Future enhancements shall preserve all Architectural Invariants.

---

# Appendix G — Canonical Trait Signatures

> **[2.1]** New in this revision. Section 6 defines the Core Architectural Objects conceptually and independently of implementation language, by design (§6.2). This appendix is not a contradiction of that principle — it is a non-normative, illustrative sketch showing how those concepts map onto Rust traits, provided so that the module specifications listed in Appendix E (particularly 09 Rule Engine Specification, 10 Domain SDK Specification, and 13 Execution Engine Specification) start from one shared vocabulary instead of each inventing its own. The authoritative types are defined in those module specifications; this appendix constrains them to be consistent with the concepts and tiers established here.

```rust
// rasica-domain-sdk (illustrative — see Domain SDK Specification for the authoritative contract)

/// Implemented by every Domain Module. Registered at compile time (§11.18A).
pub trait DomainModule: Send + Sync + 'static {
    fn id(&self) -> DomainModuleId;
    fn version(&self) -> SemVer;
    fn engine_compatibility(&self) -> EngineVersionRange;

    /// Pure, deterministic — see §11.10. No I/O, no randomness, no clock access.
    fn applicability(&self, structural_knowledge: &StructuralKnowledge) -> ApplicabilityScore;

    /// Contributes Tier 1 (Immutable) facts only; never mutates existing facts.
    fn contribute_knowledge(&self, ctx: &KnowledgeContributionContext) -> Vec<DomainFact>;

    /// Contributes Rules per the grammar and purity requirements in §10.11A / §10.12.
    fn contribute_rules(&self) -> Vec<Rule>;

    /// Optional additional structural validation constraints (§11.15).
    fn contribute_validation(&self) -> Vec<ValidationConstraint> { Vec::new() }
}

// rasica-rules (illustrative — see Rule Engine Specification for the authoritative contract)

pub struct RuleId(String);   // globally unique, stable across versions

pub struct Rule {
    pub id: RuleId,
    pub priority: u16,                    // total order tie-break: (priority, id) — §10.11A
    pub reads: HashSet<FactType>,
    pub produces: HashSet<FactType>,
    pub suppresses: HashSet<FactType>,     // declared contradiction relationships — §10.11A
    pub condition: Box<dyn Fn(&FactBase) -> bool + Send + Sync>,   // pure
    pub action: Box<dyn Fn(&FactBase) -> Vec<Fact> + Send + Sync>, // pure
}

// rasica-core (illustrative — see Core Object Model Specification for the authoritative contract)

/// Marker trait for every Tier 1 Core Architectural Object (§6.2A).
/// Implementors provide no public API capable of mutating `self` after construction.
pub trait Immutable: Send + Sync {}

/// Marker trait for the one Tier 2 object (Diagnostics, §6.2A).
/// The only mutating operation permitted is `append`.
pub trait AppendOnly: Send + Sync {
    type Entry;
    fn append(&mut self, entry: Self::Entry);
}

/// Marker trait for Tier 3 objects (Execution Context, caches, §6.2A).
/// Implementors shall never be reachable from a Tier 1 object's public API.
pub trait ScopedMutable: Send {}
```

These signatures are illustrative rather than final; the module specifications in Appendix E own the authoritative versions. They are included here only so that "deterministic," "pure," "Tier 1," and "Rule" mean the same thing in every downstream document.

## Type Authority Policy

This policy governs how the module specifications in Appendix E (particularly 09 Rule Engine Specification, 10 Domain SDK Specification, and 03 Core Object Model Specification) may relate to the signatures above, so that this appendix cannot silently drift out of sync with the specifications it exists to align — the same failure mode previously found and corrected in the Phase 9 roadmap's "Domain Loader" (§15.12).

- **Invariant properties — copy, do not relitigate.** The Mutability Tier of each type, the purity and determinism requirements on `condition`/`action`/`applicability`, the stratified evaluation order, and the existence and meaning of `suppresses` are architectural decisions made in §6.2A, §10.11A, and §11.10. A module specification shall not narrow, loosen, or omit these; doing so is an architectural change requiring an ADR (§14.18) against this document, not a module-spec-level design choice.
- **Implementation detail — expected to evolve.** Concrete field types (e.g. `HashSet` vs. a different set implementation), whether `condition`/`action` are boxed closures or an enum-based DSL, error handling, derives, and builder ergonomics are left open by this appendix and may be refined freely by the module specification that owns the authoritative type.
- **Promotion is the default path.** A module specification should begin by adopting the relevant signature from this appendix verbatim, then modify only what implementation requires. Starting from a clean-sheet redesign is discouraged, since it re-derives decisions already made elsewhere in this document without benefit.
- **Divergence must be backported, not left to accumulate.** When a module specification changes a signature from what appears here for a reason permitted by the second bullet above, the author shall update this appendix in the same change so it reflects the authoritative version's current shape, together with a one-line rationale in the module specification for why this appendix's version was insufficient. This appendix is a live shared vocabulary, not a historical snapshot; it shall never be allowed to describe a contract the authoritative specification has since abandoned.

---

# Appendix H — Non-Functional Requirements Baseline

> **[2.1]** New in this revision. Sections throughout this document describe RASICA as "high-performance," "scalable," and "efficient" (§4.6, §14.15, and elsewhere) without a measurable target, which left Benchmarking (§14.15) with nothing concrete to check regressions against. This appendix establishes a baseline; it is expected to be refined by ADR as real workloads are characterised, but it exists so no release ships without an explicit target.

| Dimension | Baseline Target | Notes |
| --- | --- | --- |
| Dataset size, in-memory profile | Up to 10,000,000 rows × 200 columns processed within available system memory | Beyond this, the chunked/paged Dataset backing (§6.4) is expected to be required. |
| End-to-end pipeline latency | A dataset at the baseline size above completes Validation → Structural Inference → Knowledge Graph → Rule Evaluation → Analysis Graph construction in under 60 seconds on a defined reference machine (to be specified in the Benchmarking Specification, §24). | Excludes Execution (statistical computation) and Rendering, which are measured separately because their cost is capability-dependent. |
| Memory ceiling | Peak resident memory shall not exceed 4× the on-disk size of the input Dataset for the in-memory profile. | Tracked as an Execution Metric (§13.15). |
| Rule Engine evaluation cost | Bounded by the number of distinct fact types and strata (§10.11A), independent of dataset row count for a fixed schema shape. | Verified via the fact-base lookup counter defined in §10.14A. |
| Knowledge Graph / Capability Registry lookup | O(log n) average case per lookup, per §10.14A. | Enforced by the indexing requirement; violated by any linear-scan implementation. |
| Concurrency scaling | Independent Analysis Graph nodes shall show near-linear speedup up to the reference machine's physical core count, subject to the Deterministic Reduction Strategy (§12.10). | Measured, not assumed; regressions block release per §14.15. |

Every numeric target in this table is a baseline for the reference machine and dataset shape defined in the Benchmarking Specification (Appendix E, §24), not a universal guarantee for arbitrary hardware or dataset shapes. Targets shall be revisited by ADR as real workloads are characterised, per §14.15 and §14.18.

---

# Appendix I — Closing Statement

RASICA is designed as a deterministic analytical reasoning platform.

Its architecture separates:

- data,
- knowledge,
- reasoning,
- planning,
- execution,
- presentation.

This separation enables the platform to remain:

- deterministic,
- explainable,
- reproducible,
- extensible,
- domain-independent,
- maintainable.

Every future specification, implementation, and contribution shall preserve these principles.

The long-term success of RASICA depends not only upon the correctness of its implementation, but also upon continued adherence to the architectural philosophy established within this specification.

This document serves as the constitutional reference for the RASICA platform.
