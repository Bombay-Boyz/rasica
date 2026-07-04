//! Semantic versioning primitives shared by the Core Engine and every
//! Domain Module (Architecture Spec §14.16, Appendix G).

use std::fmt;

pub use semver::Version as SemVer;
use semver::VersionReq;

/// The version of the RASICA Core Engine itself, as distinct from any
/// individual Domain Module's version (§14.16: versioned independently).
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct EngineVersion(SemVer);

impl EngineVersion {
    /// Wraps an existing [`SemVer`] as the current engine version.
    #[must_use]
    pub const fn new(version: SemVer) -> Self {
        Self(version)
    }

    /// Returns the underlying [`SemVer`].
    #[must_use]
    pub const fn as_semver(&self) -> &SemVer {
        &self.0
    }
}

impl fmt::Display for EngineVersion {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        fmt::Display::fmt(&self.0, f)
    }
}

/// A range of Core Engine versions a Domain Module declares itself
/// compatible with (Appendix G: `DomainModule::engine_compatibility`).
///
/// Compatibility checking, not construction, is the operation that matters:
/// a malformed or overly broad range is a Domain Module authoring defect to
/// be caught at Domain Manager registration time (Architecture Spec §11.7),
/// not something this type attempts to prevent structurally.
#[derive(Debug, Clone)]
pub struct EngineVersionRange(VersionReq);

impl EngineVersionRange {
    /// Parses a Cargo-style version requirement string (e.g. `">=0.3, <0.5"`).
    ///
    /// # Errors
    ///
    /// Returns [`semver::Error`] if `requirement` is not a valid version
    /// requirement expression.
    pub fn parse(requirement: &str) -> Result<Self, semver::Error> {
        VersionReq::parse(requirement).map(Self)
    }

    /// Returns whether `version` satisfies this range.
    #[must_use]
    pub fn matches(&self, version: &EngineVersion) -> bool {
        self.0.matches(version.as_semver())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn range_matches_within_bounds() {
        let range = EngineVersionRange::parse(">=1.0.0, <2.0.0")
            .expect("literal in test is a valid semver requirement");
        let compatible = EngineVersion::new(SemVer::new(1, 5, 0));
        let incompatible = EngineVersion::new(SemVer::new(2, 0, 0));

        assert!(range.matches(&compatible));
        assert!(!range.matches(&incompatible));
    }
}
