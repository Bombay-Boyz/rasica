//! Errors produced while ingesting an external source (Architecture Spec
//! §14.9; Document 00A §4.4).

use thiserror::Error;

use rasica_common::error::{ErrorCode, ErrorSeverity, RasicaError};
use rasica_dataset::{error::DatasetError, schema::SchemaError};

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
            Self::DatasetConstructionFailed(_) => {
                ErrorCode("ingestion::dataset_construction_failed")
            }
        }
    }

    fn severity(&self) -> ErrorSeverity {
        // Every condition is caught before `DatasetBuilder::build` is
        // called, i.e. before any Tier 1 `Dataset` exists — matching
        // `DatasetError`'s rationale in Document 00B §4.7.
        ErrorSeverity::Recoverable
    }
}
