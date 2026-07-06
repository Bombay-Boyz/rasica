//! A `Hash + Eq` view of `rasica_dataset::value::Value`, used wherever
//! this crate needs set/map membership over cell values — distinct-value
//! counting (§5.2-§5.4), duplicate temporal-parse tallying (§5.5), and
//! candidate-key subset evidence (§5.7) — at better than O(n^2).
//!
//! This is a direct copy of `rasica-validation`'s own `value_key.rs`
//! (Phase 4): `Value::Float`'s `f64` is not itself `Hash + Eq` (NaN's
//! reflexivity failure), so this module hashes the bit pattern instead,
//! which is exactly as discriminating as the platform's own `f64`
//! equality for every non-NaN value, and treats all NaN payloads as one
//! equivalence class — an acceptable, documented narrowing for the
//! set-membership purposes this crate needs, for the same reasons Phase
//! 4 documents.

use rasica_dataset::value::Value;

/// A hashable, equality-comparable key for one cell value.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub(crate) enum ValueKey {
    Null,
    Boolean(bool),
    Integer(i64),
    /// Bit-pattern of the `f64`, not its numeric value — see module docs.
    Float(u64),
    Text(String),
}

impl From<&Value> for ValueKey {
    fn from(value: &Value) -> Self {
        match value {
            Value::Null => Self::Null,
            Value::Boolean(b) => Self::Boolean(*b),
            Value::Integer(i) => Self::Integer(*i),
            Value::Float(f) => Self::Float(f.to_bits()),
            Value::Text(s) => Self::Text(s.clone()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn equal_values_produce_equal_keys() {
        assert_eq!(ValueKey::from(&Value::Integer(3)), ValueKey::from(&Value::Integer(3)));
        assert_eq!(
            ValueKey::from(&Value::Text("a".into())),
            ValueKey::from(&Value::Text("a".into()))
        );
        assert_eq!(ValueKey::from(&Value::Null), ValueKey::from(&Value::Null));
    }

    #[test]
    fn distinct_values_produce_distinct_keys() {
        assert_ne!(ValueKey::from(&Value::Integer(3)), ValueKey::from(&Value::Integer(4)));
        assert_ne!(ValueKey::from(&Value::Integer(1)), ValueKey::from(&Value::Boolean(true)));
    }
}
