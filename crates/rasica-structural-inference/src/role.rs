//! `VariableRole` (§4.1) and the per-column classification decision list
//! (§5).

use rasica_dataset::{schema::ColumnType, value::Value};

use crate::temporal_format::parses_as_temporal;

/// The structural role §6.7/§9.3 assigns to a single column, determined
/// solely from the column's own declared type and values — never from its
/// name, and never from any Domain Module (§6.7: "without consulting
/// Domain Modules").
///
/// Column *names* are deliberately excluded from every heuristic in this
/// crate, even though a name like `"customer_id"` is a strong informal
/// signal: using it would make classification depend on naming
/// convention rather than on structure, which is exactly the
/// structural/semantic boundary §6.7 draws. A column named `"x"` and a
/// column named `"customer_id"` containing identical values classify
/// identically.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum VariableRole {
    /// Every non-null value is unique across the column, the column is
    /// not entirely null, and the column's declared type is
    /// [`ColumnType::Integer`] or [`ColumnType::Text`] (§5.2).
    Identifier,
    /// Numeric ([`ColumnType::Integer`] or [`ColumnType::Float`]) values
    /// whose distinct-value count exceeds the shared cardinality
    /// threshold, relative to row count (§5.3).
    Continuous,
    /// A non-empty, bounded (small relative to row count) set of distinct
    /// values (§5.4).
    Categorical,
    /// [`ColumnType::Text`] values, at least 90% of which parse as one of
    /// the recognised temporal formats (§5.5, `temporal_format`).
    Temporal,
    /// No heuristic below claimed the column: either the column is
    /// entirely null, or it is high-cardinality `Text` that is not
    /// recognisably temporal (e.g. free-text comments) (§5.6).
    Unclassified,
}

/// The fraction of a `Text` column's non-null values that must parse as a
/// recognised temporal format for the column to be classified `Temporal`
/// (§5.5, a **[DRAFT DECISION]** in Document 00E, adopted here as
/// specified: tolerating a small fraction of malformed entries in an
/// otherwise-temporal column without requiring Phase 4's validation
/// machinery to run first).
const TEMPORAL_PARSE_THRESHOLD: f64 = 0.9;

/// The distinct-value-count boundary between `Continuous`/`Categorical`:
/// at least 20 distinct values in absolute terms, or 5% of `row_count`,
/// whichever is larger (§5.3, a **[DRAFT DECISION]** in Document 00E).
///
/// This is also used, symmetrically, as `Categorical`'s *upper* bound —
/// see this module's top-of-file reconciliation note (in the generating
/// script's header) for why `Categorical` must be bounded above by this
/// same threshold rather than merely requiring `distinct_count >= 1`.
#[must_use]
pub(crate) fn continuous_categorical_threshold(row_count: usize) -> usize {
    (row_count / 20).max(20)
}

/// Classifies one column, given its declared type, the dataset's row
/// count, its non-null values (in dataset row order), and its distinct
/// non-null value count.
///
/// This is the fixed, ordered decision list of §5.1: Identifier, then
/// Temporal, then Continuous, then Categorical, then Unclassified — the
/// role of the *first* heuristic that claims the column, never a scoring
/// competition (§5.1: "keeps the classification auditable as a simple,
/// explicit precedence rule").
pub(crate) fn classify(
    column_type: ColumnType,
    row_count: usize,
    non_null_values: &[&Value],
    distinct_count: usize,
) -> VariableRole {
    let non_null_count = non_null_values.len();

    if is_identifier(column_type, non_null_count, distinct_count) {
        return VariableRole::Identifier;
    }
    if is_temporal(column_type, non_null_values) {
        return VariableRole::Temporal;
    }
    if is_continuous(column_type, row_count, distinct_count) {
        return VariableRole::Continuous;
    }
    if is_categorical(row_count, distinct_count) {
        return VariableRole::Categorical;
    }
    VariableRole::Unclassified
}

/// §5.2.
fn is_identifier(column_type: ColumnType, non_null_count: usize, distinct_count: usize) -> bool {
    matches!(column_type, ColumnType::Integer | ColumnType::Text)
        && non_null_count > 0
        && distinct_count == non_null_count
}

/// §5.5.
fn is_temporal(column_type: ColumnType, non_null_values: &[&Value]) -> bool {
    if column_type != ColumnType::Text || non_null_values.is_empty() {
        return false;
    }
    #[allow(clippy::cast_precision_loss)]
    // non-null counts are far below f64's exact-integer ceiling.
    let non_null_count = non_null_values.len() as f64;

    let parseable = non_null_values
        .iter()
        .filter(|value| match value {
            Value::Text(text) => parses_as_temporal(text),
            _ => false,
        })
        .count();
    #[allow(clippy::cast_precision_loss)]
    let ratio = parseable as f64 / non_null_count;
    ratio >= TEMPORAL_PARSE_THRESHOLD
}

/// §5.3. Assumes Identifier/Temporal have already been ruled out by the
/// caller's fixed evaluation order.
fn is_continuous(column_type: ColumnType, row_count: usize, distinct_count: usize) -> bool {
    matches!(column_type, ColumnType::Integer | ColumnType::Float)
        && distinct_count > continuous_categorical_threshold(row_count)
}

/// §5.4, bounded above per this module's reconciliation note. Assumes
/// Identifier/Temporal/Continuous have already been ruled out by the
/// caller's fixed evaluation order.
fn is_categorical(row_count: usize, distinct_count: usize) -> bool {
    (1..=continuous_categorical_threshold(row_count)).contains(&distinct_count)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn values(values: &[Value]) -> Vec<&Value> {
        values.iter().collect()
    }

    #[test]
    fn identifier_requires_exact_type_and_full_distinctness() {
        let ints = [Value::Integer(1), Value::Integer(2), Value::Integer(3)];
        assert_eq!(classify(ColumnType::Integer, 3, &values(&ints), 3), VariableRole::Identifier);

        // A Float column with all-unique values is deliberately NOT an
        // identifier (§5.2: "not what 'identifier' structurally means").
        let floats = [Value::Float(1.0), Value::Float(2.0)];
        assert_ne!(classify(ColumnType::Float, 2, &values(&floats), 2), VariableRole::Identifier);
    }

    #[test]
    fn all_null_column_is_never_an_identifier() {
        assert_ne!(classify(ColumnType::Integer, 5, &[], 0), VariableRole::Identifier);
    }

    #[test]
    fn temporal_is_recognised_even_with_up_to_ten_percent_malformed_entries() {
        let mut raw = vec![Value::Text("2024-01-01".into()); 9];
        raw.push(Value::Text("not a date".into()));
        assert_eq!(classify(ColumnType::Text, 10, &values(&raw), 2), VariableRole::Temporal);
    }

    #[test]
    fn temporal_is_checked_before_categorical_for_low_cardinality_dates() {
        // Three distinct dates, REPEATED across many rows (10 rows, 3
        // distinct values) — non-unique, so Identifier cannot claim this
        // column; Categorical's low-cardinality test would otherwise claim
        // it first if Temporal were not checked before it (Document 00E
        // §5.1's own worked example).
        let raw = [
            Value::Text("2024-01-01".into()),
            Value::Text("2024-02-01".into()),
            Value::Text("2024-03-01".into()),
            Value::Text("2024-01-01".into()),
            Value::Text("2024-02-01".into()),
            Value::Text("2024-03-01".into()),
            Value::Text("2024-01-01".into()),
            Value::Text("2024-02-01".into()),
            Value::Text("2024-03-01".into()),
            Value::Text("2024-01-01".into()),
        ];
        assert_eq!(classify(ColumnType::Text, 10, &values(&raw), 3), VariableRole::Temporal);
    }

    #[rstest::rstest]
    #[case::just_below_threshold(19, VariableRole::Categorical)]
    #[case::just_above_threshold(21, VariableRole::Continuous)]
    fn continuous_categorical_boundary_is_respected(
        #[case] distinct_count: usize,
        #[case] expected: VariableRole,
    ) {
        // row_count = 100 -> threshold = max(20, 100/20) = 20.
        let role = classify(ColumnType::Float, 100, &[], distinct_count);
        assert_eq!(role, expected);
    }

    #[test]
    fn categorical_does_not_claim_high_cardinality_free_text() {
        // 25 distinct values on 30 rows, threshold = max(20, 30/20) = 20:
        // distinct_count (25) exceeds the bound, so this is Unclassified,
        // not Categorical (Document 00E's `name` fixture column).
        assert_eq!(classify(ColumnType::Text, 30, &[], 25), VariableRole::Unclassified);
    }

    #[test]
    fn entirely_null_column_is_unclassified() {
        assert_eq!(classify(ColumnType::Text, 10, &[], 0), VariableRole::Unclassified);
    }

    #[test]
    fn boolean_like_low_cardinality_column_is_categorical() {
        assert_eq!(classify(ColumnType::Boolean, 1000, &[], 2), VariableRole::Categorical);
    }
}
