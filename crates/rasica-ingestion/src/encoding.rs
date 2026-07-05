//! UTF-8 validation and byte-order-mark handling for text-based sources
//! (§1.4 Note 2 of the Phase 3 Implementation Specification).

const UTF8_BOM: [u8; 3] = [0xEF, 0xBB, 0xBF];

/// Strips a leading UTF-8 byte-order mark from `bytes`, if present, then
/// validates the remainder as UTF-8.
///
/// # Errors
///
/// Returns the underlying [`std::str::Utf8Error`] if `bytes` (after BOM
/// stripping) is not valid UTF-8. This is the sole encoding check Phase 3
/// performs; non-UTF-8 encodings are out of scope (§1.4 Note 2) and are
/// surfaced to callers as [`crate::error::IngestionError::InvalidEncoding`].
pub(crate) fn strip_bom_and_validate_utf8(bytes: &[u8]) -> Result<&str, std::str::Utf8Error> {
    let without_bom = bytes.strip_prefix(&UTF8_BOM).unwrap_or(bytes);
    std::str::from_utf8(without_bom)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[allow(clippy::expect_used)]
    fn strips_bom_when_present() {
        let mut bytes = UTF8_BOM.to_vec();
        bytes.extend_from_slice(b"a,b\n1,2\n");
        assert_eq!(
            strip_bom_and_validate_utf8(&bytes).expect("valid UTF-8 after BOM"),
            "a,b\n1,2\n"
        );
    }

    #[test]
    fn passes_through_unchanged_without_bom() {
        assert_eq!(strip_bom_and_validate_utf8(b"a,b\n1,2\n"), Ok("a,b\n1,2\n"));
    }

    #[test]
    fn rejects_invalid_utf8() {
        assert!(strip_bom_and_validate_utf8(&[0xFF, 0xFE, 0x00]).is_err());
    }
}
