//! Ties [`rasica_common::Id`] to Core Architectural Objects generically.

use rasica_common::Id;

/// Implemented by every Core Architectural Object that has a stable identity
/// distinct from its content (Architecture Spec §6.2, "Single source of
/// truth").
///
/// Not every Core Architectural Object needs identity distinct from content —
/// two `Fingerprint`-equal values may be legitimately interchangeable — so
/// this trait is opt-in, not a supertrait of [`crate::mutability::Immutable`].
pub trait Identifiable {
    /// The marker type distinguishing this object's identifiers from every
    /// other object's, per [`Id`]'s own documentation.
    type Marker;

    /// Returns this object's stable identifier.
    fn id(&self) -> Id<Self::Marker>;
}
