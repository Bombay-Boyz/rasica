//! Strongly-typed, globally unique identifiers.
//!
//! `Id<T>` prevents mixing up identifiers that belong to different
//! Core Architectural Objects (e.g. accidentally comparing a `DatasetId`
//! to a `RuleId`) at compile time, at zero runtime cost, by carrying a
//! phantom marker type. See Architecture Spec Appendix G, which defines
//! `RuleId` and `DomainModuleId` as the first two consumers of this pattern.

use std::{
    cmp::Ordering,
    fmt,
    hash::{Hash, Hasher},
    marker::PhantomData,
    str::FromStr,
};

use uuid::Uuid;

/// A globally unique identifier for a value of type `T`.
///
/// `T` is a marker type only; it need not (and typically does not) exist
/// as a runtime value. `Id<T>` is `Copy`, `Eq`, `Ord`, and `Hash` regardless
/// of whether `T` implements those traits, because the identifier's identity
/// is independent of `T`'s own properties.
pub struct Id<T> {
    value: Uuid,
    _marker: PhantomData<fn() -> T>,
}

impl<T> Id<T> {
    /// Generates a new, random `Id`
    /// (Architecture Spec §4.1): identifiers name objects, they do not
    /// influence which analytical operations are selected or in what order
    /// rules apply. Any object whose *content* (not just its identity) must
    /// be reproducible across runs is fingerprinted separately — see
    /// `rasica-core::fingerprint`.
    #[must_use]
    pub fn new() -> Self {
        Self { value: Uuid::new_v4(), _marker: PhantomData }
    }

    /// Constructs an `Id` from an existing, already-unique raw value.
    ///
    /// Used for deserialising identifiers that were generated in a previous
    /// process (e.g. loaded from a persisted Audit Record, §6.15).
    #[must_use]
    pub const fn from_uuid(value: Uuid) -> Self {
        Self { value, _marker: PhantomData }
    }

    /// Returns the underlying UUID.
    #[must_use]
    pub const fn as_uuid(&self) -> Uuid {
        self.value
    }
}

impl<T> Default for Id<T> {
    fn default() -> Self {
        Self::new()
    }
}

// Manual trait implementations below: `#[derive(..)]` would require `T: Clone`,
// `T: Eq`, etc., which is incorrect for a phantom marker (see the classic
// "phantom type parameter" derive pitfall). Implementing by hand keeps `Id<T>`
// usable for any marker `T`, matching its stated contract above.

impl<T> Clone for Id<T> {
    fn clone(&self) -> Self {
        *self
    }
}
impl<T> Copy for Id<T> {}

impl<T> PartialEq for Id<T> {
    fn eq(&self, other: &Self) -> bool {
        self.value == other.value
    }
}
impl<T> Eq for Id<T> {}

impl<T> PartialOrd for Id<T> {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}
impl<T> Ord for Id<T> {
    fn cmp(&self, other: &Self) -> Ordering {
        self.value.cmp(&other.value)
    }
}

impl<T> Hash for Id<T> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.value.hash(state);
    }
}

impl<T> fmt::Debug for Id<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_tuple("Id").field(&self.value).finish()
    }
}

impl<T> fmt::Display for Id<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Display::fmt(&self.value, f)
    }
}

impl<T> FromStr for Id<T> {
    type Err = uuid::Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Uuid::from_str(s).map(Self::from_uuid)
    }
}

impl<T> serde::Serialize for Id<T> {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        self.value.serialize(serializer)
    }
}

impl<'de, T> serde::Deserialize<'de> for Id<T> {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        Uuid::deserialize(deserializer).map(Self::from_uuid)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct DatasetMarker;
    struct RuleMarker;

    #[test]
    fn distinct_ids_are_not_equal() {
        let a: Id<DatasetMarker> = Id::new();
        let b: Id<DatasetMarker> = Id::new();
        assert_ne!(a, b);
    }

    #[test]
    #[allow(clippy::expect_used)]
    fn round_trips_through_string() {
        let original: Id<RuleMarker> = Id::new();
        let parsed: Id<RuleMarker> = original.to_string().parse().expect(
            "an Id's Display output is always a valid UUID string, so parsing it back can never fail",
        );
        assert_eq!(original, parsed);
    }

    #[test]
    fn is_copy() {
        let a: Id<DatasetMarker> = Id::new();
        let b = a; // would fail to compile if `Id` were not `Copy`
        assert_eq!(a, b);
    }
}
