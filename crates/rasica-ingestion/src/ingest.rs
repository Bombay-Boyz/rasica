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
        FormatOptions::Excel(excel_options) => excel::read(path, &excel_options),
        FormatOptions::Json => {
            let file = File::open(path).map_err(|cause| IngestionError::SourceUnreadable {
                origin: origin.clone(),
                cause,
            })?;
            json::read(BufReader::new(file), origin)
        }
    }
}
