//! Layer-merging implementation backing [`super::RasicaConfig::load`].

use std::path::Path;

use figment::{
    providers::{Env, Format, Serialized, Toml},
    Figment,
};
use serde::Serialize;

use super::{ConfigError, RasicaConfig};

/// Compiled-in defaults, expressed as a plain serialisable struct so they
/// participate in the same merge machinery as every other layer rather than
/// being special-cased.
#[derive(Serialize)]
struct Defaults {
    logging: DefaultsLogging,
}

#[derive(Serialize)]
struct DefaultsLogging {
    level: &'static str,
    format: &'static str,
}

impl Default for Defaults {
    fn default() -> Self {
        Self { logging: DefaultsLogging { level: "info", format: "pretty" } }
    }
}

#[allow(clippy::result_large_err)]
pub(super) fn load(file_path: &Path) -> Result<RasicaConfig, ConfigError> {
    let mut figment = Figment::new().merge(Serialized::defaults(Defaults::default()));

    if file_path.exists() {
        figment = figment.merge(Toml::file(file_path));
    }

    figment = figment.merge(Env::prefixed("RASICA_").split("__"));

    figment.extract().map_err(|cause| ConfigError::SourceUnreadable {
        source_name: file_path.display().to_string(),
        cause,
    })
}

// LogLevel / LogFormat need Deserialize (already derived on the public types
// in mod.rs); no additional glue is required here because Figment/serde
// deserialise directly into the public config structs.
