//! `rasica-common`: shared primitives, error framework, configuration
//! framework, and logging framework for every RASICA crate.
//!
//! This crate implements no analytical, statistical, or domain logic
//! (Architecture Spec §14.6: "no crate shall contain unrelated
//! responsibilities"). Every other RASICA crate may depend on it
//! unconditionally; it depends on nothing internal to RASICA itself.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod config;
pub mod error;
pub mod id;
pub mod logging;
pub mod version;

pub use error::{ErrorCode, ErrorSeverity, RasicaError};
pub use id::Id;
pub use version::{EngineVersion, EngineVersionRange, SemVer};
