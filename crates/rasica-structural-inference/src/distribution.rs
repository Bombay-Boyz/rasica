//! `DistributionSummary` (§6.7's "distributions" deliverable, scoped per
//! §2.2 to closed-form descriptive statistics rather than
//! distribution-family fitting).

/// A deterministic, closed-form descriptive summary of a `Continuous`
/// column's non-null values.
///
/// All five fields are computed from non-null values only; nulls are
/// excluded from every statistic.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DistributionSummary {
    minimum: f64,
    maximum: f64,
    mean: f64,
    median: f64,
    /// The population standard deviation (divisor `n`, not `n - 1`):
    /// Structural Knowledge describes the dataset's *own* observed
    /// spread, not an inference about a hypothetical larger population,
    /// so the population (not sample) formula is the structurally
    /// correct one here.
    standard_deviation: f64,
}

impl DistributionSummary {
    /// The minimum non-null value observed.
    #[must_use]
    pub fn minimum(&self) -> f64 {
        self.minimum
    }

    /// The maximum non-null value observed.
    #[must_use]
    pub fn maximum(&self) -> f64 {
        self.maximum
    }

    /// The arithmetic mean of the non-null values observed.
    #[must_use]
    pub fn mean(&self) -> f64 {
        self.mean
    }

    /// The median of the non-null values observed.
    #[must_use]
    pub fn median(&self) -> f64 {
        self.median
    }

    /// The population standard deviation of the non-null values observed.
    #[must_use]
    pub fn standard_deviation(&self) -> f64 {
        self.standard_deviation
    }

    /// Derives a summary from `values`, a column's non-null numeric
    /// values in dataset row order.
    ///
    /// Sorts `values` before summing — an `O(n log n)` cost already paid
    /// for `median` — rather than summing in row order, so that this
    /// summary's derived-fingerprint bytes do not depend on an otherwise
    /// irrelevant upstream row-ordering change (Document 00E §4.2's
    /// determinism note).
    ///
    /// # Panics
    ///
    /// Panics if `values` is empty. This is a programming defect, not a
    /// data condition: `infer` (§6) only calls this once a column has
    /// already been classified `Continuous`, which itself requires a
    /// distinct-value count exceeding a positive threshold, and therefore
    /// requires at least one non-null value to exist.
    #[must_use]
    pub(crate) fn derive(values: &[f64]) -> Self {
        assert!(
            !values.is_empty(),
            "DistributionSummary::derive called with no values; this is a caller defect \
             (only Continuous columns, which are non-empty by construction, may reach here)"
        );

        let mut sorted = values.to_vec();
        sorted.sort_by(f64::total_cmp);

        let minimum = sorted[0];
        let maximum = sorted[sorted.len() - 1];

        #[allow(clippy::cast_precision_loss)]
        // column lengths are far below f64's exact-integer ceiling.
        let count = sorted.len() as f64;
        let mean = sorted.iter().sum::<f64>() / count;

        let median = if sorted.len() % 2 == 0 {
            let mid = sorted.len() / 2;
            f64::midpoint(sorted[mid - 1], sorted[mid])
        } else {
            sorted[sorted.len() / 2]
        };

        let variance = sorted.iter().map(|value| (value - mean).powi(2)).sum::<f64>() / count;
        let standard_deviation = variance.sqrt();

        Self { minimum, maximum, mean, median, standard_deviation }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[allow(clippy::float_cmp)] // exact values, hand-computed from small fixed inputs.
    fn matches_hand_computed_statistics() {
        let summary = DistributionSummary::derive(&[2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]);
        assert_eq!(summary.minimum(), 2.0);
        assert_eq!(summary.maximum(), 9.0);
        assert_eq!(summary.mean(), 5.0);
        assert_eq!(summary.median(), 4.5);
        assert_eq!(summary.standard_deviation(), 2.0);
    }

    #[test]
    #[allow(clippy::float_cmp)]
    fn odd_length_median_is_the_middle_element() {
        let summary = DistributionSummary::derive(&[3.0, 1.0, 2.0]);
        assert_eq!(summary.median(), 2.0);
    }

    #[test]
    fn result_is_independent_of_input_order() {
        let ascending = DistributionSummary::derive(&[1.0, 2.0, 3.0, 4.0, 5.0]);
        let shuffled = DistributionSummary::derive(&[4.0, 1.0, 5.0, 2.0, 3.0]);
        assert_eq!(ascending, shuffled);
    }

    #[test]
    #[should_panic(expected = "no values")]
    fn panics_on_empty_input() {
        let _ = DistributionSummary::derive(&[]);
    }
}
