//! `rasica-core`: the Mutability Tier, identity, and deterministic
//! fingerprinting vocabulary shared by every Core Architectural Object
//! (Architecture Spec §6).
//!
//! This crate defines no Core Architectural Object itself — `Dataset`,
//! `Rule`, and the rest are introduced by the phase specifications that
//! implement Architecture Spec §6.4 onward. It defines only the vocabulary
//! those objects share.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod fingerprint;
pub mod identity;
pub mod mutability;
pub mod prelude;
