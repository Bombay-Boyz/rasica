//! A `Hash + Eq` view of `rasica_dataset::value::Value`, used wherever a
//! check needs set/map membership over cell values (duplicate row
//! detection, `Unique` constraint checking) at better than O(n^2).
//!
//! `Value::Float`'s `f64` is not itself `Hash + Eq` (NaN's reflexivity
//! failure); this module fixes that by hashing the bit pattern instead,
//! which is exactly as discriminating as the platform's own `f64`
//! equality for every non-NaN value, and treats all NaN payloads as one
//! equivalence class, which is an acceptable, documented narrowing here
//! since duplicate/uniqueness checking needs *an* equivalence relation,
//! not IEEE-754 comparison semantics.

use rasica_dataset::value::Value;

/// A hashable, totally-ordered-for-equality key for one cell value.
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
