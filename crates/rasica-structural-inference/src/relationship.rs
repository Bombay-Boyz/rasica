//! `RelationshipEvidence` (§6.7's "relationships" deliverable, §5.7):
//! deterministic, mechanically-observed candidate-key evidence between
//! `Identifier`-classified columns of a single Dataset.
//!
//! This is deliberately scoped to *evidence*, not a resolved semantic
//! relationship — interpreting this evidence into an actual knowledge
//! graph edge is the Knowledge Engine's job (Phase 6), not this crate's.

use std::collections::HashSet;

use crate::value_key::ValueKey;

/// Identifies one column within the Dataset being inferred over, by
/// position.
///
/// Scoped to a single Dataset for this phase (§5.7 restricts relationship
/// evidence to identifier pairs within one Dataset; cross-Dataset evidence
/// is an explicitly deferred capability) — see the generating script's
/// ADAPTATION NOTE for why this does not also carry a Dataset identity
/// handle.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ColumnRef {
    column_position: usize,
}

impl ColumnRef {
    pub(crate) fn new(column_position: usize) -> Self {
        Self { column_position }
    }

    /// The 0-based column index within the Dataset's schema.
    #[must_use]
    pub fn column_position(&self) -> usize {
        self.column_position
    }
}

/// The specific, mechanically-checkable relationship a piece of evidence
/// asserts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RelationshipKind {
    /// Both `left` and `right` are classified `Identifier`, and every
    /// non-null value in `right` also appears as a value in `left`
    /// (§5.7's candidate foreign-key check). This does not distinguish
    /// which side is the "parent" — that is a semantic judgement out of
    /// scope here — it only records that the subset relationship holds in
    /// this direction.
    ValueSubset,
}

/// A single piece of deterministic, mechanically-observed evidence that
/// two columns may be related.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RelationshipEvidence {
    left: ColumnRef,
    right: ColumnRef,
    kind: RelationshipKind,
}

impl RelationshipEvidence {
    /// The column whose value set was checked as the (candidate) superset.
    #[must_use]
    pub fn left(&self) -> ColumnRef {
        self.left
    }

    /// The column whose value set was checked as the (candidate) subset.
    #[must_use]
    pub fn right(&self) -> ColumnRef {
        self.right
    }

    /// The specific relationship this evidence asserts.
    #[must_use]
    pub fn kind(&self) -> RelationshipKind {
        self.kind
    }
}

/// Computes §5.7's `ValueSubset` evidence over every ordered pair of
/// distinct columns in `identifier_columns` — each entry being an
/// `Identifier`-classified column's position and the set of its non-null
/// values.
///
/// Iterates ordered pairs `(left, right)` with `left != right` in
/// ascending `(left_position, right_position)` order, so that evidence
/// order never depends on hash-map iteration order (the same determinism
/// concern `value_key`/`ValueKey` exists to satisfy elsewhere in this
/// crate) — only on the fixed column order the schema itself declares.
pub(crate) fn detect_value_subset_evidence(
    identifier_columns: &[(usize, HashSet<ValueKey>)],
) -> Vec<RelationshipEvidence> {
    let mut evidence = Vec::new();

    for (left_position, left_values) in identifier_columns {
        for (right_position, right_values) in identifier_columns {
            if left_position == right_position {
                continue;
            }
            if right_values.is_empty() {
                continue; // a non-empty subset is required (§5.7).
            }
            if right_values.is_subset(left_values) {
                evidence.push(RelationshipEvidence {
                    left: ColumnRef::new(*left_position),
                    right: ColumnRef::new(*right_position),
                    kind: RelationshipKind::ValueSubset,
                });
            }
        }
    }

    evidence
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key_set(values: &[i64]) -> HashSet<ValueKey> {
        values.iter().map(|v| ValueKey::from(&rasica_dataset::value::Value::Integer(*v))).collect()
    }

    #[test]
    fn detects_a_subset_relationship_in_one_direction() {
        let columns = [(0, key_set(&[1, 2, 3, 4, 5])), (1, key_set(&[2, 4]))];
        let evidence = detect_value_subset_evidence(&columns);
        assert_eq!(evidence.len(), 1);
        assert_eq!(evidence[0].left().column_position(), 0);
        assert_eq!(evidence[0].right().column_position(), 1);
        assert_eq!(evidence[0].kind(), RelationshipKind::ValueSubset);
    }

    #[test]
    fn identical_value_sets_produce_evidence_in_both_directions() {
        let columns = [(0, key_set(&[1, 2, 3])), (1, key_set(&[1, 2, 3]))];
        let evidence = detect_value_subset_evidence(&columns);
        assert_eq!(evidence.len(), 2);
    }

    #[test]
    fn disjoint_columns_produce_no_evidence() {
        let columns = [(0, key_set(&[1, 2, 3])), (1, key_set(&[4, 5, 6]))];
        assert!(detect_value_subset_evidence(&columns).is_empty());
    }

    #[test]
    fn empty_right_hand_column_produces_no_evidence() {
        let columns = [(0, key_set(&[1, 2, 3])), (1, HashSet::new())];
        assert!(detect_value_subset_evidence(&columns).is_empty());
    }
}
