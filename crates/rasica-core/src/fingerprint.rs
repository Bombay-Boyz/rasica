//! Deterministic fingerprinting, required by Architecture Spec §6.2A for
//! keying Tier 3 caches, and supporting the Numeric Determinism guarantee of
//! §4.1 by giving later phases (e.g. the Rule Engine's fact-base lookups,
//! §10.14A) one stable, non-toolchain-dependent hash to build on.

use std::fmt;

/// The output of a deterministic fingerprint: a fixed-size, comparable,
/// hashable digest.
///
/// Two `Fingerprint`s are equal if and only if they were computed from
/// byte-identical [`DeterministicFingerprint::fingerprint_bytes`] output.
/// `Fingerprint` deliberately does not implement [`std::hash::Hash`] against
/// `std::collections::HashMap`'s default `RandomState` hasher; the digest
/// itself is already a strong, uniformly distributed 256-bit value, so
/// consumers needing a `HashMap` key should use the digest's bytes directly
/// (e.g. via a `BuildHasherDefault` over a non-randomising hasher) rather
/// than re-hashing it with a randomised hasher that would reintroduce the
/// very non-determinism this type exists to avoid.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Fingerprint([u8; 32]);

impl Fingerprint {
    /// Returns the raw 32-byte BLAKE3 digest.
    #[must_use]
    pub const fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }

    /// Renders the fingerprint as a lowercase hexadecimal string, suitable
    /// for inclusion in an Audit Record (§6.15) or a diagnostic message.
    #[must_use]
    pub fn to_hex(&self) -> String {
        blake3::Hash::from(self.0).to_hex().to_string()
    }
}

impl fmt::Debug for Fingerprint {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_tuple("Fingerprint").field(&self.to_hex()).finish()
    }
}

impl fmt::Display for Fingerprint {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.to_hex())
    }
}

/// Implemented by any value that can be turned into a stable byte sequence
/// for fingerprinting.
///
/// # Contract
///
/// Implementations shall be:
///
/// - **Deterministic:** the same logical value always produces the same
///   bytes, regardless of process, platform, or execution order. In
///   particular, implementations shall not depend on: pointer addresses,
///   `HashMap`/`HashSet` iteration order (use a sorted representation
///   instead), the current time, or any other source of non-determinism —
///   this is the same requirement §4.1 places on Logical Determinism, applied
///   at the byte-representation level.
/// - **Injective with respect to logical equality:** two values that are not
///   logically equal shall not (outside of the negligible probability of a
///   BLAKE3 collision) produce the same bytes.
pub trait DeterministicFingerprint {
    /// Returns the deterministic byte representation of `self` used as
    /// fingerprint input.
    fn fingerprint_bytes(&self) -> Vec<u8>;

    /// Computes this value's [`Fingerprint`].
    ///
    /// Provided in terms of [`DeterministicFingerprint::fingerprint_bytes`];
    /// implementors should not need to override this.
    fn fingerprint(&self) -> Fingerprint {
        Fingerprint(*blake3::hash(&self.fingerprint_bytes()).as_bytes())
    }
}

// Blanket impl for byte slices themselves, so composite fingerprints can be
// built by fingerprinting sub-parts and concatenating, e.g.:
//   [a.fingerprint().as_bytes(), b.fingerprint().as_bytes()].concat()
impl DeterministicFingerprint for [u8] {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        self.to_vec()
    }
}

impl DeterministicFingerprint for str {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        self.as_bytes().to_vec()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identical_input_produces_identical_fingerprint() {
        assert_eq!("rasica".fingerprint(), "rasica".fingerprint());
    }

    #[test]
    fn different_input_produces_different_fingerprint() {
        assert_ne!("rasica".fingerprint(), "RASICA".fingerprint());
    }

    #[test]
    fn composite_fingerprint_is_order_sensitive() {
        let ab: Vec<u8> =
            ["a".fingerprint().as_bytes().as_slice(), "b".fingerprint().as_bytes().as_slice()]
                .concat();
        let ba: Vec<u8> =
            ["b".fingerprint().as_bytes().as_slice(), "a".fingerprint().as_bytes().as_slice()]
                .concat();

        assert_ne!(ab.fingerprint(), ba.fingerprint());
    }

    proptest::proptest! {
        #[test]
        fn fingerprint_is_deterministic_across_calls(s in ".*") {
            let first = s.fingerprint();
            let second = s.fingerprint();
            proptest::prop_assert_eq!(first, second);
        }
    }
}
