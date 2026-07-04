//! `rasica-dataset`: the immutable internal Dataset representation
//! (Architecture Spec §6.4) and its supporting Schema, Row, Value, Source,
//! and Metadata types.

#![forbid(unsafe_code)]
#![warn(missing_docs)]

pub mod dataset;
pub mod error;
pub mod metadata;
pub mod prelude;
pub mod row;
pub mod schema;
pub mod source;
pub mod value;

use crate::{schema::ColumnType, value::Value};

/// Returns whether `value` agrees with `column_type`, treating
/// [`Value::Null`] as agreeing with every type (nullability is a
/// per-column fact recorded by [`crate::metadata::Metadata`], not a
/// per-value type violation).
pub(crate) fn value_matches_type(value: &Value, column_type: ColumnType) -> bool {
    matches!(
        (value, column_type),
        (Value::Null, _)
            | (Value::Integer(_), ColumnType::Integer)
            | (Value::Float(_), ColumnType::Float)
            | (Value::Boolean(_), ColumnType::Boolean)
            | (Value::Text(_), ColumnType::Text)
    )
}
