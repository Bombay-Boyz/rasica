//! Convenience re-export of the vocabulary every Core Architectural Object
//! implementation needs. Later crates are expected to write
//! `use rasica_core::prelude::*;` rather than importing each item
//! individually.

pub use crate::{
    fingerprint::{DeterministicFingerprint, Fingerprint},
    identity::Identifiable,
    mutability::{AppendOnly, Immutable, ScopedMutable},
};
