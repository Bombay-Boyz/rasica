//! A single cell value, typed according to `ColumnType` (§4.3 of this
//! document).

use rasica_core::prelude::DeterministicFingerprint;

/// One value in one cell of a [`crate::row::Row`].
///
/// `Value::Null` is a distinct variant, not the absence of a `Value`,
/// because nullability itself is a fact `Metadata` (§4.5) records per
/// column — a `Row` must therefore be able to represent "this cell is
/// null" explicitly rather than by omission.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    /// No value is present.
    Null,
    /// A 64-bit signed integer.
    Integer(i64),
    /// A 64-bit floating-point number.
    ///
    /// Equality on this variant follows `PartialEq` on `f64`, including
    /// `NaN != NaN`; no domain semantics (e.g. "treat NaN as missing") are
    /// applied here (Architecture Spec §6.4: the Dataset is not responsible
    /// for semantic interpretation).
    Float(f64),
    /// A boolean.
    Boolean(bool),
    /// UTF-8 text.
    Text(String),
}

impl DeterministicFingerprint for Value {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        // Each variant is prefixed with a distinct tag byte so that, e.g.,
        // `Integer(0)` and `Boolean(false)` — which could otherwise collide
        // on their payload bytes alone — fingerprint differently. This is
        // the same "injective with respect to logical equality" contract
        // Document 00A §5.4 places on every `DeterministicFingerprint`
        // implementation.
        match self {
            Self::Null => vec![0u8],
            Self::Integer(v) => [&[1u8][..], &v.to_le_bytes()].concat(),
            Self::Float(v) => [&[2u8][..], &v.to_le_bytes()].concat(),
            Self::Boolean(v) => vec![3u8, u8::from(*v)],
            Self::Text(v) => [&[4u8][..], v.as_bytes()].concat(),
        }
    }
}
