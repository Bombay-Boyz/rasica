//! The closed, fixed set of recognised temporal text formats (§5.5):
//! `YYYY-MM-DD`, `YYYY-MM-DDTHH:MM:SS`, and `MM/DD/YYYY`. Deliberately not
//! general-purpose date/time parsing — matching the "closed enumeration"
//! style Document 00C's own `SourceFormat`/`ColumnType` use, and §2.2's
//! exclusion of anything beyond a closed-form deterministic function from
//! this crate.
//!
//! No external date/time crate is introduced for this: each format is a
//! small, fixed-width, positionally-anchored pattern, so validating it by
//! hand keeps this crate's dependency footprint unchanged (Document 00E
//! §8, "this crate needs no new external dependency").

/// Whether `text` parses successfully against at least one of the three
/// recognised formats.
pub(crate) fn parses_as_temporal(text: &str) -> bool {
    parses_ymd(text) || parses_ymd_hms(text) || parses_mdy(text)
}

fn is_ascii_digits(bytes: &[u8]) -> bool {
    !bytes.is_empty() && bytes.iter().all(u8::is_ascii_digit)
}

/// Calendrically valid year/month/day (accounting for leap years),
/// independent of separator style — shared by every format below.
fn valid_calendar_date(year: u32, month: u32, day: u32) -> bool {
    if !(1..=12).contains(&month) {
        return false;
    }
    let is_leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
    let days_in_month = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 => {
            if is_leap {
                29
            } else {
                28
            }
        }
        _ => unreachable!("month already validated to be in 1..=12"),
    };
    (1..=days_in_month).contains(&day)
}

/// `YYYY-MM-DD`.
fn parses_ymd(text: &str) -> bool {
    let bytes = text.as_bytes();
    if bytes.len() != 10 || bytes[4] != b'-' || bytes[7] != b'-' {
        return false;
    }
    if !is_ascii_digits(&bytes[0..4])
        || !is_ascii_digits(&bytes[5..7])
        || !is_ascii_digits(&bytes[8..10])
    {
        return false;
    }
    let (Ok(year), Ok(month), Ok(day)) =
        (text[0..4].parse(), text[5..7].parse(), text[8..10].parse())
    else {
        return false;
    };
    valid_calendar_date(year, month, day)
}

/// `YYYY-MM-DDTHH:MM:SS` (RFC 3339-style, without a timezone offset).
fn parses_ymd_hms(text: &str) -> bool {
    let bytes = text.as_bytes();
    if bytes.len() != 19 || bytes[10] != b'T' || bytes[13] != b':' || bytes[16] != b':' {
        return false;
    }
    if !parses_ymd(&text[0..10]) {
        return false;
    }
    if !is_ascii_digits(&bytes[11..13])
        || !is_ascii_digits(&bytes[14..16])
        || !is_ascii_digits(&bytes[17..19])
    {
        return false;
    }
    let (Ok(hour), Ok(minute), Ok(second)): (Result<u32, _>, Result<u32, _>, Result<u32, _>) =
        (text[11..13].parse(), text[14..16].parse(), text[17..19].parse())
    else {
        return false;
    };
    hour <= 23 && minute <= 59 && second <= 59
}

/// `MM/DD/YYYY`.
fn parses_mdy(text: &str) -> bool {
    let bytes = text.as_bytes();
    if bytes.len() != 10 || bytes[2] != b'/' || bytes[5] != b'/' {
        return false;
    }
    if !is_ascii_digits(&bytes[0..2])
        || !is_ascii_digits(&bytes[3..5])
        || !is_ascii_digits(&bytes[6..10])
    {
        return false;
    }
    let (Ok(month), Ok(day), Ok(year)) =
        (text[0..2].parse(), text[3..5].parse(), text[6..10].parse())
    else {
        return false;
    };
    valid_calendar_date(year, month, day)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_every_recognised_format() {
        assert!(parses_as_temporal("2024-02-29")); // leap year
        assert!(parses_as_temporal("2024-02-29T13:45:00"));
        assert!(parses_as_temporal("02/29/2024"));
    }

    #[test]
    fn rejects_malformed_or_out_of_range_values() {
        assert!(!parses_as_temporal("2023-02-29")); // not a leap year
        assert!(!parses_as_temporal("2023-13-01")); // invalid month
        assert!(!parses_as_temporal("2023-04-31")); // April has 30 days
        assert!(!parses_as_temporal("13/40/2023")); // invalid month/day (MM/DD/YYYY)
        assert!(!parses_as_temporal("2023-01-01T24:00:00")); // hour out of range
        assert!(!parses_as_temporal("not a date"));
        assert!(!parses_as_temporal(""));
    }
}
