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
