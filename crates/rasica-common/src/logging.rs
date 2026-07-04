//! Logging/tracing initialisation (Architecture Spec §14.6 context; consumed
//! by the Diagnostics framework in a later phase, §6.14/§13).

use tracing::level_filters::LevelFilter;
use tracing_subscriber::{fmt, EnvFilter};

use crate::config::{LogFormat, LogLevel, LoggingConfig};

/// Initialises the global `tracing` subscriber from `config`.
///
/// This shall be called exactly once, as early as possible in `main`, before
/// any other RASICA code runs. Calling it more than once will return an
/// error from the underlying `tracing` global-subscriber registration; that
/// error is treated as a programming defect per §14.9 and is therefore
/// intentionally surfaced as a panic rather than a `Result`, since a second
/// call can only be reached by an implementation mistake, not by any runtime
/// condition a caller could meaningfully recover from.
///
/// # Panics
///
/// Panics if a global subscriber has already been installed.
pub fn init(config: &LoggingConfig) {
    let filter = EnvFilter::builder()
        .with_default_directive(level_filter(config.level()).into())
        .from_env_lossy();

    let subscriber = fmt().with_env_filter(filter);

    match config.format() {
        LogFormat::Pretty => subscriber.pretty().init(),
        LogFormat::Json => subscriber.json().init(),
    }
}

const fn level_filter(level: LogLevel) -> LevelFilter {
    match level {
        LogLevel::Trace => LevelFilter::TRACE,
        LogLevel::Debug => LevelFilter::DEBUG,
        LogLevel::Info => LevelFilter::INFO,
        LogLevel::Warn => LevelFilter::WARN,
        LogLevel::Error => LevelFilter::ERROR,
    }
}
