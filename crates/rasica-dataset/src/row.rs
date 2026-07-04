//! A single row: one [`Value`] per column of the [`crate::schema::Schema`]
//! it was constructed against.

use rasica_core::prelude::DeterministicFingerprint;

use crate::value::Value;

/// One row of a [`Dataset`](crate::dataset::Dataset).
///
/// A `Row` does not carry its own copy of the [`crate::schema::Schema`] it
/// belongs to (that would duplicate the schema once per row, contradicting
/// Architecture Spec §6.4's "columns" being a Dataset-level, not row-level,
/// responsibility). Arity is checked once, at
/// [`DatasetBuilder::push_row`](crate::dataset::DatasetBuilder::push_row)
/// time, against the `Dataset`'s single `Schema`.
#[derive(Debug, Clone, PartialEq)]
pub struct Row(Vec<Value>);

impl Row {
    /// Constructs a row from an ordered list of values.
    ///
    /// This constructor performs no arity or type checking against any
    /// schema; that check is the responsibility of
    /// [`DatasetBuilder::push_row`](crate::dataset::DatasetBuilder::push_row),
    /// the single point at which a `Row` and a `Schema` are brought
    /// together.
    #[must_use]
    pub fn new(values: Vec<Value>) -> Self {
        Self(values)
    }

    /// Returns the number of values in this row.
    #[must_use]
    pub fn arity(&self) -> usize {
        self.0.len()
    }

    /// Returns the value at `position`, if present.
    #[must_use]
    pub fn get(&self, position: usize) -> Option<&Value> {
        self.0.get(position)
    }

    /// Returns the row's values in order.
    #[must_use]
    pub fn values(&self) -> &[Value] {
        &self.0
    }
}

impl DeterministicFingerprint for Row {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        self.0.iter().flat_map(DeterministicFingerprint::fingerprint_bytes).collect()
    }
}
