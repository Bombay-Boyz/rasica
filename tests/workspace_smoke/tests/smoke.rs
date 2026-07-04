//! Verifies that `rasica-core` and `rasica-common` compose as intended:
//! the tier markers and fingerprinting contract are usable together to
//! define a minimal, hypothetical Tier 1 object, exactly as a real Core
//! Architectural Object will do starting in Phase 2.

use rasica_common::Id;
use rasica_core::prelude::*;

struct ExampleMarker;

/// A minimal stand-in for a future Tier 1 Core Architectural Object,
/// existing only to prove the Phase 1 vocabulary is sufficient to build one.
struct ExampleImmutableObject {
    id: Id<ExampleMarker>,
    payload: String,
}

impl Immutable for ExampleImmutableObject {}

impl Identifiable for ExampleImmutableObject {
    type Marker = ExampleMarker;

    fn id(&self) -> Id<Self::Marker> {
        self.id
    }
}

impl DeterministicFingerprint for ExampleImmutableObject {
    fn fingerprint_bytes(&self) -> Vec<u8> {
        // Deliberately excludes `self.id`: identity is not content, and two
        // objects with different identities but identical payloads should
        // fingerprint identically (§6.2A's caching rule keys on *inputs*,
        // i.e. content, not on identity).
        self.payload.fingerprint_bytes()
    }
}

#[test]
fn tier_and_identity_traits_compose_on_a_real_type() {
    let object = ExampleImmutableObject { id: Id::new(), payload: "example".to_owned() };

    let _ = object.id();
    let _ = object.fingerprint();
}

#[test]
fn objects_with_equal_content_fingerprint_equally_regardless_of_identity() {
    let a = ExampleImmutableObject { id: Id::new(), payload: "same".to_owned() };
    let b = ExampleImmutableObject { id: Id::new(), payload: "same".to_owned() };

    assert_ne!(a.id(), b.id());
    assert_eq!(a.fingerprint(), b.fingerprint());
}
