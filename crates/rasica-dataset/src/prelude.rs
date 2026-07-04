//! Convenience re-export of the types most consumers of `rasica-dataset`
//! need, following the same convention as `rasica_core::prelude`
//! (Document 00A §5.6).

pub use crate::{
    dataset::{Dataset, DatasetBuilder, DatasetMarker},
    error::DatasetError,
    metadata::{ColumnMetadata, Metadata},
    row::Row,
    schema::{Column, ColumnType, Schema, SchemaError},
    source::{SourceFormat, SourceMetadata},
    value::Value,
};
