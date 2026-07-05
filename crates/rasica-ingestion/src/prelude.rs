//! Convenience re-export of the types most consumers of `rasica-ingestion`
//! need, following the same convention as `rasica_dataset::prelude`
//! (Document 00B §4.8).

pub use crate::{
    csv::CsvOptions,
    error::IngestionError,
    excel::ExcelOptions,
    ingest::{ingest_path, FormatOptions},
};
