//! The three Mutability Tiers every Core Architectural Object belongs to
//! for its entire lifetime (Architecture Spec §6.2A).
//!
//! These traits are markers: they carry no methods of their own beyond what
//! each tier's contract requires (`AppendOnly::append`). Their purpose is to
//! make an object's tier a checkable part of its public type, not a comment.

/// Tier 1 — Immutable (§6.2A).
///
/// The object is fully constructed once and never modified afterward for the
/// remainder of the process. Any change requires constructing a new object
/// with a new identity.
///
/// Implementors provide no public API capable of mutating `self` after
/// construction. This is a documentation contract this trait cannot enforce
/// mechanically for arbitrary interior mutability (e.g. `Cell`); reviewers
/// checking §14.12 compliance for a new `Immutable` implementor shall verify
/// by inspection that no such backdoor exists.
///
/// Applies, per §6.2A, to: Dataset, Metadata, Validation Report, Structural
/// Knowledge, Knowledge Graph, Domain Facts, Capability Registry, Rules,
/// Analysis Graph, Audit Record. None of these types exist yet in Phase 1;
/// this trait is defined now so their specifications (Appendix E items
/// 03–13) have it available from their first line of code.
pub trait Immutable: Send + Sync {}

/// Tier 2 — Append-Only (§6.2A).
///
/// The object may receive additional entries over the course of an
/// execution, but existing entries are never altered or removed once
/// written. Every consumer that reads a snapshot of it treats it as
/// immutable at the point of reading.
///
/// The only mutating operation permitted is [`AppendOnly::append`].
/// Applies, per §6.2A, to: Diagnostics.
pub trait AppendOnly: Send + Sync {
    /// The type of a single entry appended to this object.
    type Entry;

    /// Appends `entry`. Implementors shall never remove, reorder, or modify
    /// any previously appended entry as a side effect of this call.
    fn append(&mut self, entry: Self::Entry);
}

/// Tier 3 — Scoped-Mutable (§6.2A).
///
/// The object is mutable only within the bounded lifetime of a single
/// execution, is owned exclusively by one subsystem during that lifetime,
/// is never shared as a mutable reference across subsystem boundaries, and
/// is discarded — never persisted as authoritative state — at the end of
/// the execution.
///
/// Three rules govern every `ScopedMutable` implementor (§6.2A) and are not
/// mechanically enforced by this trait; they are checked in review (§14.12)
/// and, where practical, by the integration tests of the crate that owns the
/// implementor:
///
/// 1. A `ScopedMutable` object shall never be the source of truth for an
///    analytical conclusion; conclusions are always derived from `Immutable`
///    (Tier 1) objects.
/// 2. Caching intermediate results is a Tier 3 concern: cached values are a
///    performance optimisation over already-deterministic Tier 1
///    computations, are always keyed by a value implementing
///    [`crate::fingerprint::DeterministicFingerprint`] over their inputs, and
///    their presence or absence shall never change the analytical result,
///    only the time taken to produce it.
/// 3. No object may be promoted from Tier 3 to Tier 1 by aliasing; an
///    `Immutable` object referencing Tier 3-derived data must copy the data
///    at the point of construction.
///
/// Applies, per §6.2A, to: Execution Context, and internal Execution Engine
/// caches of intermediate results.
pub trait ScopedMutable: Send {}
