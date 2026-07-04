//! The closed, ordered column list a `Dataset` conforms to
//! (Architecture Spec §6.4, "columns").

use std::collections::HashSet;

use thiserror::Error;

/// The declared type of every value in a [`Column`].
///
/// This is a closed, structural vocabulary — the exact type a value is
/// *represented as* — and carries no semantic interpretation. Whether an
/// `Integer` column is actually a categorical code, or a `Text` column is
/// actually a date, is a Structural Inference concern (Architecture Spec
/// §6.7, Phase 5), not a Schema concern.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ColumnType {
    /// A 64-bit signed integer value.
    Integer,
    /// A 64-bit floating-point value.
    Float,
    /// A boolean value.
    Boolean,
    /// A UTF-8 text value.
    Text,
}

/// One column's name and declared type.
///
/// `Column` does not carry a value; it describes a position in every
/// [`crate::row::Row`] belonging to a [`Schema`] that includes it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Column {
    name: String,
    column_type: ColumnType,
}

impl Column {
    /// Declares a new column with the given name and type.
    #[must_use]
    pub fn new(name: impl Into<String>, column_type: ColumnType) -> Self {
        Self { name: name.into(), column_type }
    }

    /// Returns the column's name.
    #[must_use]
    pub fn name(&self) -> &str {
        &self.name
    }

    /// Returns the column's declared type.
    #[must_use]
    pub const fn column_type(&self) -> ColumnType {
        self.column_type
    }
}

/// Errors that can occur while constructing a [`Schema`].
#[derive(Debug, Error, PartialEq, Eq)]
pub enum SchemaError {
    /// Two or more columns were declared with the same name.
    #[error("duplicate column name '{name}'")]
    DuplicateColumnName {
        /// The name that appeared more than once.
        name: String,
    },
    /// A schema with zero columns was constructed.
    ///
    /// A `Dataset` "represents rows, columns, \[and\] values" (Architecture
    /// Spec §6.4); a schema with no columns can represent no values, so it
    /// is rejected as a structural malformation rather than as a valid
    /// zero-column dataset.
    #[error("a schema must declare at least one column")]
    Empty,
}

/// The closed, ordered list of [`Column`]s every [`crate::row::Row`] in a
/// [`Dataset`](crate::dataset::Dataset) conforms to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Schema {
    columns: Vec<Column>,
}

impl Schema {
    /// Constructs a `Schema` from an ordered list of columns.
    ///
    /// # Errors
    ///
    /// Returns [`SchemaError::Empty`] if `columns` is empty, or
    /// [`SchemaError::DuplicateColumnName`] if any two columns share a name.
    pub fn new(columns: Vec<Column>) -> Result<Self, SchemaError> {
        if columns.is_empty() {
            return Err(SchemaError::Empty);
        }

        let mut seen = HashSet::with_capacity(columns.len());
        for column in &columns {
            if !seen.insert(column.name()) {
                return Err(SchemaError::DuplicateColumnName { name: column.name().to_owned() });
            }
        }

        Ok(Self { columns })
    }

    /// Returns the number of columns in this schema.
    #[must_use]
    pub fn arity(&self) -> usize {
        self.columns.len()
    }

    /// Returns the columns in declaration order.
    #[must_use]
    pub fn columns(&self) -> &[Column] {
        &self.columns
    }

    /// Returns the ordinal position of the column named `name`, if present.
    #[must_use]
    pub fn position_of(&self, name: &str) -> Option<usize> {
        self.columns.iter().position(|c| c.name() == name)
    }
}
use rasica_core::prelude::DeterministicFingerprint;

impl DeterministicFingerprint for ColumnType {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        // One tag byte per variant — same "distinct tag per variant"
        // convention `Value`'s DeterministicFingerprint impl uses.
        match self {
            Self::Integer => vec![0u8],
            Self::Float => vec![1u8],
            Self::Boolean => vec![2u8],
            Self::Text => vec![3u8],
        }
    }
}

impl DeterministicFingerprint for Column {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        let mut bytes = self.name.fingerprint_bytes();
        bytes.extend(self.column_type.fingerprint_bytes());
        bytes
    }
}

impl DeterministicFingerprint for Schema {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        self.columns.iter().flat_map(DeterministicFingerprint::fingerprint_bytes).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_empty_schema() {
        assert_eq!(Schema::new(vec![]), Err(SchemaError::Empty));
    }

    #[test]
    fn rejects_duplicate_column_names() {
        let result = Schema::new(vec![
            Column::new("a", ColumnType::Integer),
            Column::new("a", ColumnType::Text),
        ]);
        assert_eq!(result, Err(SchemaError::DuplicateColumnName { name: "a".into() }));
    }

    #[test]
    #[allow(clippy::expect_used)]
    fn accepts_well_formed_schema() {
        let schema = Schema::new(vec![
            Column::new("id", ColumnType::Integer),
            Column::new("label", ColumnType::Text),
        ])
        .expect("two distinctly named columns is a well-formed schema");
        assert_eq!(schema.arity(), 2);
        assert_eq!(schema.position_of("label"), Some(1));
    }
}
