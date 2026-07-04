//! Provenance information about where a Dataset's content came from
//! (Architecture Spec §6.4, "source metadata").

/// The external format a `Dataset`'s content was constructed from, or
/// [`SourceFormat::InMemory`] if it was constructed directly.
///
/// This is a closed enumeration matching Architecture Spec §6.4's example
/// list of supported external sources exactly. Phase 2 defines the
/// vocabulary; Phase 3 (Data Ingestion, §15.6) implements a reader for each
/// variant other than `InMemory`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SourceFormat {
    /// Comma-separated values.
    Csv,
    /// A Microsoft Excel workbook.
    Excel,
    /// JSON.
    Json,
    /// A SQL query result set.
    Sql,
    /// Apache Arrow.
    Arrow,
    /// Apache Parquet.
    Parquet,
    /// Constructed directly in-process, with no external source.
    InMemory,
}

/// Provenance information attached to a [`Dataset`](crate::dataset::Dataset).
///
/// `SourceMetadata` is deliberately excluded from `Dataset`'s
/// `DeterministicFingerprint` (§4.6): two datasets with byte-identical
/// schema and rows are the same *content* regardless of which format they
/// happened to be read from, and a Tier 3 cache keyed on that fingerprint
/// (Architecture Spec §6.2A) should treat them as the same cache key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourceMetadata {
    format: SourceFormat,
    origin: String,
}

impl SourceMetadata {
    /// Records that a `Dataset` came from `format`, originating at
    /// `origin` (a file path, URI, connection descriptor, or `"in-memory"`
    /// — the exact convention is owned by whichever Phase 3 reader
    /// populates it; Phase 2 imposes no structure on the string itself).
    #[must_use]
    pub fn new(format: SourceFormat, origin: impl Into<String>) -> Self {
        Self { format, origin: origin.into() }
    }

    /// Returns the source format.
    #[must_use]
    pub const fn format(&self) -> SourceFormat {
        self.format
    }

    /// Returns the origin descriptor.
    #[must_use]
    pub fn origin(&self) -> &str {
        &self.origin
    }
}
