//! Deterministic column-type inference and widening, shared by every reader
//! in this crate (§1.4 Note 3 of the Phase 3 Implementation Specification).
//!
//! Each source format observes its cells in whatever native representation
//! that format provides (raw text for CSV, `serde_json::Value` for JSON,
//! `calamine::DataType` for Excel). [`NaturalType`] is the one common
//! vocabulary every format's observations are translated into before this
//! module's widening rule is applied, so the rule itself is written once.

use rasica_dataset::schema::ColumnType;

/// The representational type of a single observed, non-null value, prior to
/// being reconciled against the rest of its column.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum NaturalType {
    /// A value recognised unambiguously as boolean by the source format's
    /// own type system (never inferred from a text literal such as `"1"`,
    /// which would be ambiguous with [`NaturalType::Integer`]).
    Boolean,
    /// A value representable exactly as a 64-bit signed integer.
    Integer,
    /// A value requiring floating-point representation.
    Float,
    /// Any value not covered by the above — including every value once any
    /// sibling in its column has forced widening past what the above three
    /// variants can jointly represent.
    Text,
}

/// Combines two [`NaturalType`]s observed in the same column into the
/// narrowest type able to represent both, without loss.
///
/// This operation is commutative and associative — `join` may therefore be
/// folded over a column's values in any order and still produce a
/// deterministic result, which is what allows §4.5's, §4.6's, and §4.7's
/// readers to share one accumulator (below) regardless of each format's own
/// row-iteration order.
///
/// | ⊔        | Boolean | Integer | Float | Text |
/// |----------|---------|---------|-------|------|
/// | Boolean  | Boolean | Text    | Text  | Text |
/// | Integer  | Text    | Integer | Float | Text |
/// | Float    | Text    | Float   | Float | Text |
/// | Text     | Text    | Text    | Text  | Text |
///
/// Boolean is never widened into Integer or Float: RASICA does not treat
/// `true`/`1` as interchangeable, since doing so would make a genuinely
/// boolean column and a genuinely integer column containing only `0`/`1`
/// indistinguishable, which is exactly the kind of representational
/// ambiguity §15.6's "correct typing" verification item exists to prevent.
#[must_use]
pub(crate) const fn join(a: NaturalType, b: NaturalType) -> NaturalType {
    use NaturalType::{Boolean, Float, Integer, Text};
    match (a, b) {
        (Boolean, Boolean) => Boolean,
        (Integer, Integer) => Integer,
        (Float | Integer, Float) | (Float, Integer) => Float, // ← this line, ~line 57
        _ => Text,
    }
}

/// Folds a column's observed [`NaturalType`]s into one resolved
/// [`ColumnType`], one value at a time, in a single forward pass.
///
/// A column containing only null values (or, degenerately, zero rows) has
/// no observation to resolve from; such a column resolves to
/// [`ColumnType::Text`], the widest and therefore safest representation for
/// a column about which nothing else is known. This mirrors `join`'s own
/// behaviour of resolving any genuine ambiguity to `Text` rather than
/// guessing.
#[derive(Debug, Clone, Copy, Default)]
pub(crate) struct ColumnTypeAccumulator {
    resolved: Option<NaturalType>,
}

impl ColumnTypeAccumulator {
    /// Starts a fresh accumulator with no observations yet.
    #[must_use]
    pub(crate) const fn new() -> Self {
        Self { resolved: None }
    }

    /// Folds in one observed value's [`NaturalType`]. Pass `None` for a
    /// null cell: nulls do not participate in type resolution, matching
    /// `rasica_dataset`'s treatment of [`rasica_dataset::value::Value::Null`]
    /// as agreeing with every [`ColumnType`] (Document 00B §4.6).
    pub(crate) fn observe(&mut self, natural_type: Option<NaturalType>) {
        let Some(observed) = natural_type else {
            return;
        };
        self.resolved = Some(match self.resolved {
            None => observed,
            Some(current) => join(current, observed),
        });
    }

    /// Resolves the final [`ColumnType`] for this column.
    #[must_use]
    pub(crate) fn finish(self) -> ColumnType {
        match self.resolved {
            Some(NaturalType::Boolean) => ColumnType::Boolean,
            Some(NaturalType::Integer) => ColumnType::Integer,
            Some(NaturalType::Float) => ColumnType::Float,
            Some(NaturalType::Text) | None => ColumnType::Text,
        }
    }
}

/// Classifies a raw CSV/text cell's [`NaturalType`], used by §4.5's CSV
/// reader during its type-resolution pass.
///
/// Recognition is deliberately strict and case-sensitive-only for booleans
/// (`"true"`/`"false"`, exactly) to avoid the ambiguity a looser match
/// (`"1"`, `"yes"`, `"T"`, ...) would introduce against [`NaturalType::Integer`]
/// and [`NaturalType::Text`] alike.
#[must_use]
pub(crate) fn classify_text(raw: &str) -> NaturalType {
    if raw == "true" || raw == "false" {
        NaturalType::Boolean
    } else if raw.parse::<i64>().is_ok() {
        NaturalType::Integer
    } else if raw.parse::<f64>().is_ok() {
        NaturalType::Float
    } else {
        NaturalType::Text
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn join_is_commutative_for_every_pair() {
        let variants =
            [NaturalType::Boolean, NaturalType::Integer, NaturalType::Float, NaturalType::Text];
        for &a in &variants {
            for &b in &variants {
                assert_eq!(join(a, b), join(b, a));
            }
        }
    }

    #[test]
    fn integer_and_float_widen_to_float() {
        assert_eq!(join(NaturalType::Integer, NaturalType::Float), NaturalType::Float);
    }

    #[test]
    fn boolean_and_integer_widen_to_text() {
        assert_eq!(join(NaturalType::Boolean, NaturalType::Integer), NaturalType::Text);
    }

    #[test]
    fn all_null_column_resolves_to_text() {
        let mut acc = ColumnTypeAccumulator::new();
        acc.observe(None);
        acc.observe(None);
        assert_eq!(acc.finish(), ColumnType::Text);
    }

    #[test]
    fn classify_text_does_not_treat_zero_or_one_as_boolean() {
        assert_eq!(classify_text("1"), NaturalType::Integer);
        assert_eq!(classify_text("0"), NaturalType::Integer);
    }

    proptest::proptest! {
        #[test]
        fn accumulator_result_is_independent_of_observation_order(
            a in 0..4usize, b in 0..4usize, c in 0..4usize,
        ) {
            let variants = [
                NaturalType::Boolean,
                NaturalType::Integer,
                NaturalType::Float,
                NaturalType::Text,
            ];
            let observations = [variants[a], variants[b], variants[c]];

            let mut forward = ColumnTypeAccumulator::new();
            for &o in &observations {
                forward.observe(Some(o));
            }

            let mut reversed = ColumnTypeAccumulator::new();
            for &o in observations.iter().rev() {
                reversed.observe(Some(o));
            }

            proptest::prop_assert_eq!(forward.finish(), reversed.finish());
        }
    }
}
