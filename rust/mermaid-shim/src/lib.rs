//! A C ABI over [merman](https://github.com/Latias94/merman) for mrkd.
//!
//! Two exported functions: render a Mermaid source to PNG bytes, and free
//! those bytes. Everything else — theming, caching, sizing — is Swift's job,
//! so this stays a thin, auditable boundary.
//!
//! Four things here are load-bearing and not incidental:
//!
//! 1. **Every entry point is wrapped in `catch_unwind`.** merman and the
//!    rasteriser under it are a large body of arithmetic. A panic unwinding
//!    out of an `extern "C"` function aborts the process, and this library is
//!    loaded into a sandboxed Quick Look extension as well as the app. A bad
//!    diagram must return an error code, not kill the host.
//! 2. **merman renders the SVG; the rasterising is ours.** merman's own PNG
//!    path resolves fonts through a `fontdb` database it builds privately from
//!    the system font directories, and mrkd's typefaces are inside the app
//!    bundle where `load_system_fonts` will never look. There is no hook for
//!    handing it a font list, so the raster step lives here instead: one
//!    `usvg`/`resvg` pass over a database that holds the system fonts *and*
//!    the bundle's. That is the only reason a diagram can be set in the same
//!    typeface as the prose around it.
//! 3. **The SVG pipeline is `resvg_safe`.** merman's default SVG puts labels in
//!    `<foreignObject>`, which no non-browser rasteriser resolves. The
//!    `ResvgSafe` preset replaces them with real SVG text.
//! 4. **Theming goes through merman's host theme, not an init directive.**
//!    An `%%{init: …}%%` directive prepended to the source is parsed but does
//!    not reach the raster path — verified by rendering one and getting
//!    mermaid's stock cream flowchart back. `HostThemeProfile` compiles host
//!    colours into the engine's site config, which does apply. The roles fall
//!    back to one another (surface-alt to surface, line to border, and so on),
//!    so a handful of colours themes every diagram family rather than thirty
//!    named variables.

use std::collections::BTreeMap;
use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Arc, OnceLock, RwLock};

use serde::Deserialize;

use merman::render::{
    HeadlessRenderer, HostThemeAppearance, HostThemeOutput, HostThemeProfile, HostThemeRoles,
    HostThemeRootBackground,
};
use resvg::{tiny_skia, usvg};

/// The theme payload Swift sends across, built from the active mrkd theme.
/// Role ids are merman's own (`canvas`, `surface`, `text`, …); an id merman
/// does not know is an error rather than something to ignore, so a typo in
/// the Swift side shows up instead of silently un-theming a diagram.
#[derive(Deserialize)]
struct ThemeSpec {
    appearance: String,
    #[serde(rename = "fontFamily")]
    font_family: Option<String>,
    #[serde(rename = "fontSize")]
    font_size: Option<String>,
    roles: BTreeMap<String, String>,
}

/// A PNG was produced; `out_bytes` and `out_len` are set and the caller owns
/// the buffer until it passes it back to [`mermaid_free_png`].
pub const MERMAID_OK: i32 = 0;
/// A null pointer, input that is not valid UTF-8, a theme payload that is not
/// the expected JSON, or a scale that is not a finite positive number.
pub const MERMAID_ERR_INVALID_INPUT: i32 = 1;
/// The source parsed but contained no Mermaid diagram.
pub const MERMAID_ERR_NO_DIAGRAM: i32 = 2;
/// merman rejected the source or the raster step failed.
pub const MERMAID_ERR_RENDER: i32 = 3;
/// The renderer panicked and the unwind was caught here.
pub const MERMAID_ERR_PANIC: i32 = 4;
/// One of the font files the caller listed could not be read as a font.
pub const MERMAID_ERR_FONT: i32 = 5;

/// Runs `body`, converting a panic into [`MERMAID_ERR_PANIC`].
///
/// This is the whole reason the release profile keeps `panic = "unwind"`.
fn guarded(body: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(MERMAID_ERR_PANIC)
}

// MARK: - Theme

/// One CSS declaration value — a colour, a length — with no way out of the
/// declaration it will be written into.
///
/// Ported from merman's own `css_declaration_value`, which validated these
/// role values before 0.7's plainer `HostThemeRoles` struct took them
/// unchecked. A role value ends up inside a `<style>` block, so `;` and the
/// quote and angle-bracket characters have to stay out of it.
fn css_declaration_value(value: &str) -> Result<String, i32> {
    let trimmed = value.trim();
    let invalid = trimmed.is_empty()
        || trimmed
            .chars()
            .any(|ch| ch.is_control() || matches!(ch, ';' | '"' | '\'' | '<' | '>' | '{' | '}'));
    if invalid {
        return Err(MERMAID_ERR_INVALID_INPUT);
    }
    Ok(trimmed.to_string())
}

/// The same check for a font-family list, which is allowed the quotes that a
/// family name with a space in it needs.
fn css_font_family(value: &str) -> Result<String, i32> {
    let trimmed = value.trim();
    let invalid = trimmed.is_empty()
        || trimmed
            .chars()
            .any(|ch| ch.is_control() || matches!(ch, ';' | '<' | '>' | '{' | '}'));
    if invalid {
        return Err(MERMAID_ERR_INVALID_INPUT);
    }
    Ok(trimmed.to_string())
}

/// merman's theme roles, keyed by the ids Swift sends.
///
/// The id strings are merman's own from its 0.8 line, where roles were an
/// enum with `from_id`. 0.7 has the same roles as struct fields and no id
/// parsing, so the table lives here — an unknown id is still an error rather
/// than a silently dropped colour.
fn host_theme_roles(spec: &ThemeSpec) -> Result<HostThemeRoles, i32> {
    let mut roles = HostThemeRoles::default();
    for (id, value) in &spec.roles {
        let field = match id.as_str() {
            "canvas" => &mut roles.canvas,
            "surface" => &mut roles.surface,
            "surface-alt" => &mut roles.surface_alt,
            "surface-muted" => &mut roles.surface_muted,
            "text" => &mut roles.text,
            "subtle-text" => &mut roles.subtle_text,
            "border" => &mut roles.border,
            "line" => &mut roles.line,
            "edge-label-background" => &mut roles.edge_label_background,
            "cluster-background" => &mut roles.cluster_background,
            "cluster-border" => &mut roles.cluster_border,
            "note-background" => &mut roles.note_background,
            "note-border" => &mut roles.note_border,
            "note-text" => &mut roles.note_text,
            "actor-background" => &mut roles.actor_background,
            "actor-border" => &mut roles.actor_border,
            "actor-text" => &mut roles.actor_text,
            "activation-background" => &mut roles.activation_background,
            "activation-border" => &mut roles.activation_border,
            "error" => &mut roles.error,
            "warning" => &mut roles.warning,
            "success" => &mut roles.success,
            _ => return Err(MERMAID_ERR_INVALID_INPUT),
        };
        *field = Some(css_declaration_value(value)?);
    }
    Ok(roles)
}

/// The host theme profile for `spec`, including the output settings that make
/// the SVG rasterisable and let the document show through it.
fn host_theme_profile(spec: &ThemeSpec) -> Result<HostThemeProfile, i32> {
    let appearance = if spec.appearance == "dark" {
        HostThemeAppearance::Dark
    } else {
        HostThemeAppearance::Light
    };

    Ok(HostThemeProfile {
        appearance,
        font_family: spec.font_family.as_deref().map(css_font_family).transpose()?,
        font_size: spec
            .font_size
            .as_deref()
            .map(css_declaration_value)
            .transpose()?,
        roles: host_theme_roles(spec)?,
        output: HostThemeOutput {
            // mermaid's own root element carries `background-color: white`,
            // which resvg honours — that is where the white card in a dark
            // document comes from, and neither the host theme nor a
            // transparent raster background removes it. Rewriting it to
            // `transparent` lets the document itself show through, which
            // cannot mismatch the way a painted canvas colour could.
            root_background: HostThemeRootBackground::Color("transparent".to_string()),
            scoped_css: Some(EDGE_LABEL_OVERLAY_CSS.to_string()),
            ..HostThemeOutput::resvg_safe_editor()
        },
        ..HostThemeProfile::default()
    })
}

/// Host CSS, appended after merman's own stylesheet so it wins on equal
/// specificity.
///
/// mermaid paints the box behind an edge label twice: an opaque `.edgeLabel`
/// background with a half-transparent `.labelBkg` layer over it, and
/// `.edgeLabel rect` at `opacity: 0.5` on top of that. In a browser those
/// stack up to something solid. Flattened into the one `<rect>` a rasteriser
/// can draw, only the transparency survives, and the edge line shows straight
/// through the label it is supposed to be interrupted by.
const EDGE_LABEL_OVERLAY_CSS: &str = ".edgeLabel rect{opacity:1;}";

// MARK: - Fonts

/// The font database `usvg` resolves names against: the system fonts plus the
/// font files the caller listed, which for mrkd are the variable typefaces
/// inside its own bundle.
///
/// Built once and reused. `load_system_fonts` costs a few hundred
/// milliseconds and the bundled files another few, which would otherwise be
/// paid on every diagram in the document. The cache is keyed on the file list
/// so a caller that changes it gets a new database rather than a stale one;
/// in mrkd the list is the bundle's own and never changes, so this is built
/// exactly once per process.
fn font_database(paths: &[String]) -> Result<Arc<usvg::fontdb::Database>, i32> {
    static CACHE: OnceLock<RwLock<Option<(Vec<String>, Arc<usvg::fontdb::Database>)>>> =
        OnceLock::new();
    let cache = CACHE.get_or_init(|| RwLock::new(None));

    if let Ok(cached) = cache.read() {
        if let Some((key, database)) = cached.as_ref() {
            if key == paths {
                return Ok(Arc::clone(database));
            }
        }
    }

    let mut database = usvg::fontdb::Database::new();
    database.load_system_fonts();
    for path in paths {
        // Loudly, not best-effort: this list is mrkd's own bundle, so a file
        // that will not load is a broken build, and a diagram silently set in
        // a fallback face is exactly the bug this whole path exists to fix.
        //
        // The face count rather than the return value: `load_font_file` only
        // reports whether the file could be *opened*, and logs and skips a
        // file it cannot parse. A font that contributes no face is as much a
        // failure here as one that is missing.
        let before = database.len();
        database.load_font_file(path).map_err(|_| MERMAID_ERR_FONT)?;
        if database.len() == before {
            return Err(MERMAID_ERR_FONT);
        }
    }
    configure_fontdb_generic_families(&mut database);

    let database = Arc::new(database);
    if let Ok(mut cached) = cache.write() {
        *cached = Some((paths.to_vec(), Arc::clone(&database)));
    }
    Ok(database)
}

/// Points `sans-serif`, `serif` and `monospace` at faces that exist.
///
/// Ported from merman's `configure_fontdb_generic_families`. `fontdb` starts
/// with the Windows family names for the generics, so on a machine without
/// them a diagram asking for `sans-serif` would resolve to nothing.
fn configure_fontdb_generic_families(fontdb: &mut usvg::fontdb::Database) {
    let sans = first_font_family(fontdb, |face| !face.monospaced)
        .or_else(|| first_font_family(fontdb, |_| true));
    let mono = first_font_family(fontdb, |face| face.monospaced).or_else(|| sans.clone());

    if query_normal_font_family(fontdb, usvg::fontdb::Family::SansSerif).is_none() {
        if let Some(family) = sans.as_ref() {
            fontdb.set_sans_serif_family(family.clone());
        }
    }
    if query_normal_font_family(fontdb, usvg::fontdb::Family::Serif).is_none() {
        if let Some(family) = sans.as_ref() {
            fontdb.set_serif_family(family.clone());
        }
    }
    if query_normal_font_family(fontdb, usvg::fontdb::Family::Monospace).is_none() {
        if let Some(family) = mono.as_ref() {
            fontdb.set_monospace_family(family.clone());
        }
    }
}

/// The family a diagram falls back to when its own `font-family` names
/// nothing that exists. Ported from merman's `raster_default_font_family`.
fn default_font_family(fontdb: &usvg::fontdb::Database) -> Option<String> {
    query_normal_font_family(fontdb, usvg::fontdb::Family::SansSerif)
        .or_else(|| query_normal_font_family(fontdb, usvg::fontdb::Family::Serif))
        .or_else(|| first_font_family(fontdb, |_| true))
}

fn query_normal_font_family(
    fontdb: &usvg::fontdb::Database,
    family: usvg::fontdb::Family<'_>,
) -> Option<String> {
    let families = [family];
    fontdb
        .query(&usvg::fontdb::Query {
            families: &families,
            weight: usvg::fontdb::Weight::NORMAL,
            stretch: usvg::fontdb::Stretch::Normal,
            style: usvg::fontdb::Style::Normal,
        })
        .and_then(|id| fontdb.face(id))
        .and_then(face_family_name)
}

fn first_font_family<F>(fontdb: &usvg::fontdb::Database, mut predicate: F) -> Option<String>
where
    F: FnMut(&usvg::fontdb::FaceInfo) -> bool,
{
    fontdb
        .faces()
        .find(|face| predicate(face))
        .and_then(face_family_name)
}

fn face_family_name(face: &usvg::fontdb::FaceInfo) -> Option<String> {
    face.families
        .iter()
        .find(|(_, language)| *language == usvg::fontdb::Language::English_UnitedStates)
        .or_else(|| face.families.first())
        .map(|(family, _)| family.clone())
}

/// Resolves `font-family` the way a browser does rather than the way `usvg`
/// does on its own. Ported from merman's `browser_like_font_resolver`.
///
/// Three steps, in order: the requested families, matched without regard to
/// case; then a generic family of the same kind, so a name nothing provides
/// lands on a sans face for prose and a monospaced one for code; and only
/// then the first face in the database. Without the middle step an
/// unrecognised family falls to whatever happens to be first, which is how a
/// diagram ends up in a random typeface.
fn browser_like_font_resolver() -> usvg::FontResolver<'static> {
    usvg::FontResolver {
        select_font: Box::new(|font, fontdb| {
            select_font_case_insensitively(font, fontdb.as_ref())
                .or_else(|| query_generic_fallback_font(font, fontdb.as_ref()))
                .or_else(|| fontdb.faces().next().map(|face| face.id))
        }),
        select_fallback: usvg::FontResolver::default_fallback_selector(),
    }
}

fn select_font_case_insensitively(
    font: &usvg::Font,
    fontdb: &usvg::fontdb::Database,
) -> Option<usvg::fontdb::ID> {
    let weight = usvg::fontdb::Weight(font.weight());
    let stretch = font.stretch().into();
    let style = font.style().into();

    for family in font.families() {
        let selected = match family {
            usvg::FontFamily::Named(name) => {
                query_named_font_family_case_insensitively(fontdb, name, weight, stretch, style)
            }
            usvg::FontFamily::Serif => {
                query_font_family(fontdb, usvg::fontdb::Family::Serif, weight, stretch, style)
            }
            usvg::FontFamily::SansSerif => query_font_family(
                fontdb,
                usvg::fontdb::Family::SansSerif,
                weight,
                stretch,
                style,
            ),
            usvg::FontFamily::Cursive => query_font_family(
                fontdb,
                usvg::fontdb::Family::Cursive,
                weight,
                stretch,
                style,
            ),
            usvg::FontFamily::Fantasy => query_font_family(
                fontdb,
                usvg::fontdb::Family::Fantasy,
                weight,
                stretch,
                style,
            ),
            usvg::FontFamily::Monospace => query_font_family(
                fontdb,
                usvg::fontdb::Family::Monospace,
                weight,
                stretch,
                style,
            ),
        };
        if selected.is_some() {
            return selected;
        }
    }

    // usvg's own last resort, kept so the whole requested stack is tried
    // first and this is reached only when none of it matched.
    query_font_family(fontdb, usvg::fontdb::Family::Serif, weight, stretch, style)
}

fn query_named_font_family_case_insensitively(
    fontdb: &usvg::fontdb::Database,
    requested: &str,
    weight: usvg::fontdb::Weight,
    stretch: usvg::fontdb::Stretch,
    style: usvg::fontdb::Style,
) -> Option<usvg::fontdb::ID> {
    query_font_family(
        fontdb,
        usvg::fontdb::Family::Name(requested),
        weight,
        stretch,
        style,
    )
    .or_else(|| {
        // Only reached when the exact name missed, so the allocation this
        // costs is off the hot path. `to_lowercase` rather than an ASCII
        // comparison because family names are not all ASCII.
        let requested = requested.to_lowercase();
        let canonical = fontdb
            .faces()
            .flat_map(|face| face.families.iter())
            .map(|(name, _)| name)
            .find(|name| name.to_lowercase() == requested)?;

        query_font_family(
            fontdb,
            usvg::fontdb::Family::Name(canonical),
            weight,
            stretch,
            style,
        )
    })
}

fn query_font_family(
    fontdb: &usvg::fontdb::Database,
    family: usvg::fontdb::Family<'_>,
    weight: usvg::fontdb::Weight,
    stretch: usvg::fontdb::Stretch,
    style: usvg::fontdb::Style,
) -> Option<usvg::fontdb::ID> {
    let families = [family];
    fontdb.query(&usvg::fontdb::Query {
        families: &families,
        weight,
        stretch,
        style,
    })
}

/// A generic family of the same kind as the one asked for, so an unknown
/// monospaced name lands on a monospaced face. Ported from merman's
/// `query_browser_like_fallback_font`.
fn query_generic_fallback_font(
    font: &usvg::Font,
    fontdb: &usvg::fontdb::Database,
) -> Option<usvg::fontdb::ID> {
    let families = if font_requests_monospace(font) {
        [
            usvg::fontdb::Family::Monospace,
            usvg::fontdb::Family::SansSerif,
            usvg::fontdb::Family::Serif,
        ]
    } else {
        [
            usvg::fontdb::Family::SansSerif,
            usvg::fontdb::Family::Serif,
            usvg::fontdb::Family::Monospace,
        ]
    };

    fontdb.query(&usvg::fontdb::Query {
        families: &families,
        weight: usvg::fontdb::Weight(font.weight()),
        stretch: font.stretch().into(),
        style: font.style().into(),
    })
}

fn font_requests_monospace(font: &usvg::Font) -> bool {
    font.families().iter().any(|family| match family {
        usvg::FontFamily::Monospace => true,
        usvg::FontFamily::Named(name) => {
            let name = name.to_ascii_lowercase();
            name.contains("mono")
                || name.contains("courier")
                || name.contains("consolas")
                || name.contains("menlo")
        }
        _ => false,
    })
}

// MARK: - Raster

/// The largest pixmap a diagram may allocate, per side and in total.
/// merman's own budget, kept because the source is a markdown file and a
/// `viewBox` of a hundred thousand points must not become an allocation.
const MAX_RASTER_SIDE: u32 = 8192;
const MAX_RASTER_PIXELS: u64 = (MAX_RASTER_SIDE as u64) * (MAX_RASTER_SIDE as u64);

/// What to draw and where. `translate_to_origin` says whether the content has
/// to be moved into the pixmap, which it does only for the diagram types that
/// emit no `viewBox`.
struct Geometry {
    min_x: f32,
    min_y: f32,
    width: f32,
    height: f32,
    translate_to_origin: bool,
}

/// Rasterises `svg` at `scale` device pixels per point against `fonts`.
fn rasterise(svg: &str, scale: f32, fonts: Arc<usvg::fontdb::Database>) -> Result<Vec<u8>, i32> {
    let default_family = default_font_family(&fonts).unwrap_or_else(|| "Arial".to_string());
    let mut options = usvg::Options {
        fontdb: fonts,
        font_family: default_family,
        font_resolver: browser_like_font_resolver(),
        // usvg would otherwise read files named by an `href`, relative to the
        // SVG. Nothing merman emits needs that, and the source is a markdown
        // file someone else may have written, so the only images that resolve
        // are the ones carried in the document itself.
        image_href_resolver: usvg::ImageHrefResolver {
            resolve_data: usvg::ImageHrefResolver::default_data_resolver(),
            resolve_string: Box::new(|_, _| None),
        },
        ..usvg::Options::default()
    };
    // A diagram with no viewBox is sized by the `max-width` in its root style
    // instead; without this it would be laid out in usvg's default 100×100.
    if parse_view_box(svg).is_none() {
        if let Some(max_width) = parse_max_width_px(svg) {
            if let Some(size) = usvg::Size::from_wh(max_width, options.default_size.height()) {
                options.default_size = size;
            }
        }
    }

    let tree = usvg::Tree::from_str(svg, &options).map_err(|_| MERMAID_ERR_RENDER)?;
    let geometry = raster_geometry(svg, &tree);
    let (width, height, effective_scale) = raster_plan(&geometry, scale)?;

    let mut pixmap = tiny_skia::Pixmap::new(width, height).ok_or(MERMAID_ERR_RENDER)?;
    // No fill: the pixmap stays transparent outside the diagram's own canvas,
    // so it sits on the document rather than on a white card.
    let transform = if geometry.translate_to_origin {
        tiny_skia::Transform::from_row(
            effective_scale,
            0.0,
            0.0,
            effective_scale,
            -geometry.min_x * effective_scale,
            -geometry.min_y * effective_scale,
        )
    } else {
        tiny_skia::Transform::from_scale(effective_scale, effective_scale)
    };
    resvg::render(&tree, transform, &mut pixmap.as_mut());

    pixmap.encode_png().map_err(|_| MERMAID_ERR_RENDER)
}

/// Ported from merman's `raster_geometry_for_svg`.
fn raster_geometry(svg: &str, tree: &usvg::Tree) -> Geometry {
    if let Some((width, height)) = parse_view_box(svg) {
        // usvg and resvg already apply the root viewBox transform, including
        // moving its min corner to the origin. Translating again would push a
        // diagram with a negative viewBox min (kanban, gitGraph) out of the
        // pixmap and render it blank.
        return Geometry {
            min_x: 0.0,
            min_y: 0.0,
            width,
            height,
            translate_to_origin: false,
        };
    }

    // Some diagram types (`info`) emit no viewBox at all. Fall back to the
    // bounds usvg computed for the content, and move it into the pixmap.
    let bounds = tree.root().abs_stroke_bounding_box();
    let width = bounds.width().max(1.0);
    let height = bounds.height().max(1.0);
    if width.is_finite() && height.is_finite() {
        Geometry {
            min_x: bounds.x(),
            min_y: bounds.y(),
            width,
            height,
            translate_to_origin: true,
        }
    } else {
        let size = tree.size();
        Geometry {
            min_x: 0.0,
            min_y: 0.0,
            width: size.width(),
            height: size.height(),
            translate_to_origin: false,
        }
    }
}

/// The pixmap size for `geometry` at `scale`, and the scale actually used —
/// which is smaller than asked for only when the budget above would be
/// exceeded, and then uniformly, so the diagram is never squashed.
///
/// Ported from merman's `raster_plan_for_geometry`. Rounding the base size up
/// before scaling rather than after is deliberate: `ceil(342.36) * 2` is 686
/// where `ceil(342.36 * 2)` is 685, and a diagram that loses a pixel every
/// time the scale doubles looks like a rendering bug.
fn raster_plan(geometry: &Geometry, scale: f32) -> Result<(u32, u32, f32), i32> {
    if !(scale.is_finite() && scale > 0.0) {
        return Err(MERMAID_ERR_INVALID_INPUT);
    }
    let base_width = f64::from(geometry.width).ceil().max(1.0);
    let base_height = f64::from(geometry.height).ceil().max(1.0);
    if !(base_width.is_finite() && base_height.is_finite()) {
        return Err(MERMAID_ERR_RENDER);
    }

    // The shrink is worked out from the size actually asked for, before
    // either side is clamped: a 20000-point-wide diagram clamped to 8192
    // first would report that it needs no shrinking at all, and come out with
    // its height untouched and its proportions wrong. Two passes are enough
    // in practice; the loop is there because rounding up to whole pixels can
    // leave the last one a hair over.
    let mut effective = f64::from(scale);
    for _ in 0..8 {
        let width = base_width * effective;
        let height = base_height * effective;
        if !(width.is_finite() && height.is_finite() && width > 0.0 && height > 0.0) {
            return Err(MERMAID_ERR_RENDER);
        }
        let shrink = (f64::from(MAX_RASTER_SIDE) / width)
            .min(f64::from(MAX_RASTER_SIDE) / height)
            .min((MAX_RASTER_PIXELS as f64 / (width * height)).sqrt())
            .min(1.0);
        if shrink >= 1.0 {
            break;
        }
        effective *= shrink * 0.999_999;
    }

    Ok((
        raster_dimension(base_width * effective)?,
        raster_dimension(base_height * effective)?,
        effective as f32,
    ))
}

/// One side of the pixmap, in whole pixels. The clamp is the last guard
/// rather than the mechanism: [`raster_plan`] has already scaled the diagram
/// to fit, so reaching it means rounding put a side one pixel over.
fn raster_dimension(value: f64) -> Result<u32, i32> {
    if !(value.is_finite() && value > 0.0) {
        return Err(MERMAID_ERR_RENDER);
    }
    let value = value.ceil().max(1.0).min(f64::from(MAX_RASTER_SIDE));
    Ok(value as u32)
}

/// The root element's `viewBox` width and height. A deliberately small,
/// non-validating scan, as merman's own is: the input is merman's output, and
/// the answer only chooses between two sizing paths.
fn parse_view_box(svg: &str) -> Option<(f32, f32)> {
    let start = svg.find("viewBox=\"")? + "viewBox=\"".len();
    let rest = &svg[start..];
    let raw = &rest[..rest.find('"')?];
    let mut fields = raw.split_whitespace();
    let _min_x = fields.next()?.parse::<f32>().ok()?;
    let _min_y = fields.next()?.parse::<f32>().ok()?;
    let width = fields.next()?.parse::<f32>().ok()?;
    let height = fields.next()?.parse::<f32>().ok()?;
    (width.is_finite() && height.is_finite() && width > 0.0 && height > 0.0)
        .then_some((width, height))
}

fn parse_max_width_px(svg: &str) -> Option<f32> {
    let start = svg.find("max-width:")? + "max-width:".len();
    let rest = svg[start..].trim_start();
    let value = rest[..rest.find("px")?].trim().parse::<f32>().ok()?;
    (value.is_finite() && value > 0.0).then_some(value)
}

// MARK: - Render

/// The stack the SVG work runs on.
///
/// `usvg` and merman's layout both recurse over nested structure, and the
/// thread mrkd calls in on is a dispatch worker with a 512 KB stack. A stack
/// overflow is a signal, not an unwind: `catch_unwind` cannot turn it into an
/// error code, so the only defence is a stack big enough. merman's own raster
/// path spawns exactly this thread for exactly this reason.
const RENDER_STACK_BYTES: usize = 8 * 1024 * 1024;

fn render_png(
    source: &str,
    theme_json: &str,
    font_paths: &[String],
    scale: f32,
) -> Result<Vec<u8>, i32> {
    let source = source.to_string();
    let theme_json = theme_json.to_string();
    let font_paths = font_paths.to_vec();

    std::thread::Builder::new()
        .name("mrkd-mermaid-render".to_string())
        .stack_size(RENDER_STACK_BYTES)
        .spawn(move || render_on_worker(&source, &theme_json, &font_paths, scale))
        .map_err(|_| MERMAID_ERR_RENDER)?
        .join()
        // A panic in the worker is already isolated from the host: the thread
        // unwinds and `join` reports it, which is the same answer the guard
        // at the C boundary gives.
        .unwrap_or(Err(MERMAID_ERR_PANIC))
}

fn render_on_worker(
    source: &str,
    theme_json: &str,
    font_paths: &[String],
    scale: f32,
) -> Result<Vec<u8>, i32> {
    let spec: ThemeSpec = serde_json::from_str(theme_json).map_err(|_| MERMAID_ERR_INVALID_INPUT)?;
    let profile = host_theme_profile(&spec)?;
    // Cheap: the profile compiles into the engine's site config, and the
    // expensive part of a render — the font database — is cached across
    // calls. The renderer cannot outlive one theme because the host colours
    // have to be in the site config before parsing.
    let renderer = HeadlessRenderer::new().with_host_theme(&profile);
    let svg = renderer
        .render_svg_sync(source)
        .map_err(|_| MERMAID_ERR_RENDER)?
        .ok_or(MERMAID_ERR_NO_DIAGRAM)?;

    rasterise(&svg, scale, font_database(font_paths)?)
}

/// Reads a JSON array of file paths.
fn font_paths(json: &str) -> Result<Vec<String>, i32> {
    serde_json::from_str(json).map_err(|_| MERMAID_ERR_INVALID_INPUT)
}

/// Renders `source` to a PNG at `scale` device pixels per point, in the
/// colours described by `theme_json`, in the fonts listed by
/// `font_paths_json` plus the system's.
///
/// # Safety
/// `source`, `theme_json` and `font_paths_json` must be NUL-terminated C
/// strings. `out_bytes` and `out_len` must be writable. On [`MERMAID_OK`] the
/// caller owns `*out_bytes` and must release it with [`mermaid_free_png`]; on
/// any other result they are set to null/0 and nothing is allocated.
#[no_mangle]
pub extern "C" fn mermaid_render_png(
    source: *const c_char,
    theme_json: *const c_char,
    font_paths_json: *const c_char,
    scale: f32,
    out_bytes: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    guarded(|| {
        if source.is_null()
            || theme_json.is_null()
            || font_paths_json.is_null()
            || out_bytes.is_null()
            || out_len.is_null()
        {
            return MERMAID_ERR_INVALID_INPUT;
        }
        // Clear the out-params first so an early return can never leave the
        // caller reading an uninitialised pointer.
        unsafe {
            *out_bytes = std::ptr::null_mut();
            *out_len = 0;
        }
        if !scale.is_finite() || scale <= 0.0 {
            return MERMAID_ERR_INVALID_INPUT;
        }
        let Ok(source) = (unsafe { CStr::from_ptr(source) }).to_str() else {
            return MERMAID_ERR_INVALID_INPUT;
        };
        let Ok(theme_json) = (unsafe { CStr::from_ptr(theme_json) }).to_str() else {
            return MERMAID_ERR_INVALID_INPUT;
        };
        let Ok(font_paths_json) = (unsafe { CStr::from_ptr(font_paths_json) }).to_str() else {
            return MERMAID_ERR_INVALID_INPUT;
        };
        let font_paths = match font_paths(font_paths_json) {
            Ok(paths) => paths,
            Err(code) => return code,
        };

        match render_png(source, theme_json, &font_paths, scale) {
            Ok(bytes) => {
                // into_boxed_slice drops any excess capacity, so length alone
                // is enough to reconstruct the allocation in mermaid_free_png.
                let boxed = bytes.into_boxed_slice();
                let len = boxed.len();
                let ptr = Box::into_raw(boxed) as *mut u8;
                unsafe {
                    *out_bytes = ptr;
                    *out_len = len;
                }
                MERMAID_OK
            }
            Err(code) => code,
        }
    })
}

/// Releases a buffer handed out by [`mermaid_render_png`].
///
/// # Safety
/// `bytes` must be a pointer returned by [`mermaid_render_png`] with its
/// matching `len`, passed exactly once.
#[no_mangle]
pub extern "C" fn mermaid_free_png(bytes: *mut u8, len: usize) {
    if bytes.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(
            bytes, len,
        )));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A theme payload in the shape Swift sends, dark and unmistakable, so a
    /// test can tell a themed diagram from mermaid's stock cream one.
    fn dark_theme_json() -> String {
        theme_json("dark", "Helvetica")
    }

    fn light_theme_json() -> String {
        r##"{"appearance":"light","fontFamily":"Helvetica","fontSize":"13px","roles":{
            "canvas":"#FFFFFF","surface":"#F6F8FA","surface-alt":"#EAEEF2",
            "surface-muted":"#F0F3F6","text":"#1F2328","subtle-text":"#656D76",
            "border":"#D0D7DE","line":"#0969DA"}}"##
            .to_string()
    }

    /// The dark payload in a chosen body font, for the font tests.
    fn theme_json(appearance: &str, font_family: &str) -> String {
        format!(
            r##"{{"appearance":"{appearance}","fontFamily":"{font_family}","fontSize":"13px","roles":{{
            "canvas":"#1E1E2E","surface":"#313244","surface-alt":"#45475A",
            "surface-muted":"#181825","text":"#CDD6F4","subtle-text":"#A6ADC8",
            "border":"#585B70","line":"#89B4FA"}}}}"##
        )
    }

    /// mrkd's bundled typefaces, from the repository this crate lives in.
    /// The app passes the same files from inside its bundle.
    fn bundled_fonts() -> Vec<String> {
        let directory = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../Sources/Resources/Fonts");
        let mut paths: Vec<String> = std::fs::read_dir(&directory)
            .expect("the bundled fonts directory should exist")
            .filter_map(|entry| {
                let path = entry.ok()?.path();
                (path.extension()?.eq_ignore_ascii_case("ttf"))
                    .then(|| path.to_str().unwrap().to_string())
            })
            .collect();
        paths.sort();
        assert!(!paths.is_empty(), "no bundled fonts found in {directory:?}");
        paths
    }

    fn render(source: &str, theme: &str, scale: f32) -> Result<Vec<u8>, i32> {
        render_png(source, theme, &bundled_fonts(), scale)
    }

    const FLOWCHART: &str = "flowchart TD\n  A[Start] --> B[Done]";

    /// The guard is the only thing standing between a renderer bug and a dead
    /// Quick Look extension, so it gets its own test: a closure that panics
    /// must come back as an error code, not unwind past `guarded`.
    #[test]
    fn guarded_turns_a_panic_into_an_error_code() {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(|_| {}));
        let code = guarded(|| panic!("renderer exploded"));
        std::panic::set_hook(previous);

        assert_eq!(code, MERMAID_ERR_PANIC);
    }

    #[test]
    fn guarded_passes_a_normal_result_through() {
        assert_eq!(guarded(|| MERMAID_OK), MERMAID_OK);
    }

    #[test]
    fn a_flowchart_renders_to_png_bytes() {
        let bytes = render(
            "flowchart TD\n  A[Start] --> B[Done]",
            &dark_theme_json(),
            2.0,
        )
        .expect("a valid flowchart should render");
        assert!(bytes.len() > 1000, "suspiciously small PNG: {}", bytes.len());
        assert_eq!(&bytes[..8], b"\x89PNG\r\n\x1a\n");
    }

    /// A diagram has to sit on the document, not on a white card. This reads
    /// the PNG's own colour type and the corner pixel's alpha rather than
    /// trusting that the postprocessor is still wired up.
    #[test]
    fn the_rendered_background_is_transparent() {
        let bytes = render("flowchart TD\n  A --> B", &dark_theme_json(), 1.0)
            .expect("flowchart should render");

        // IHDR is the first chunk: 8-byte signature, 4-byte length, 4-byte
        // type, then width, height, bit depth, colour type.
        let color_type = bytes[25];
        assert_eq!(color_type, 6, "expected 8-bit RGBA, got colour type {color_type}");

        let corner = decode_first_pixel(&bytes);
        assert_eq!(corner[3], 0, "the top-left pixel is opaque: {corner:?}");
    }

    /// Inflates the image data far enough to recover the top-left pixel.
    /// The first scanline has no row above it, so every filter the PNG
    /// encoder can pick reduces to "the byte as written" for the first pixel.
    fn decode_first_pixel(png: &[u8]) -> [u8; 4] {
        let mut idat = Vec::new();
        let mut i = 8;
        while i + 8 <= png.len() {
            let len = u32::from_be_bytes(png[i..i + 4].try_into().unwrap()) as usize;
            let kind = &png[i + 4..i + 8];
            if kind == b"IDAT" {
                idat.extend_from_slice(&png[i + 8..i + 8 + len]);
            }
            i += 12 + len;
        }
        let raw = miniz_oxide::inflate::decompress_to_vec_zlib(&idat).expect("inflate IDAT");
        let filter = raw[0];
        assert!(filter <= 4, "unexpected PNG filter type {filter}");
        [raw[1], raw[2], raw[3], raw[4]]
    }

    /// The pixel dimensions of a PNG, from its IHDR.
    fn png_size(png: &[u8]) -> (u32, u32) {
        (
            u32::from_be_bytes(png[16..20].try_into().unwrap()),
            u32::from_be_bytes(png[20..24].try_into().unwrap()),
        )
    }

    /// Every pixel of a PNG, as RGBA rows.
    fn decode_rgba(png: &[u8]) -> (u32, u32, Vec<u8>) {
        let mut reader = png::Decoder::new(png).read_info().expect("PNG header");
        let mut buffer = vec![0; reader.output_buffer_size()];
        let info = reader.next_frame(&mut buffer).expect("PNG pixels");
        assert_eq!(info.color_type, png::ColorType::Rgba);
        buffer.truncate(info.buffer_size());
        (info.width, info.height, buffer)
    }

    /// A named role has to reach the pixels, not just the theme object.
    ///
    /// `edge-label-background` is the one that would fail silently: it is the
    /// box behind an edge label, which exists only to break the line where
    /// the text crosses it, so it has to be the document's own colour. merman
    /// falls back to its own grey when it is unset, which reads as a
    /// rectangle drawn around the label — a value passed in and dropped would
    /// look exactly like that.
    #[test]
    fn a_theme_role_colour_reaches_the_pixels() {
        let theme = r##"{"appearance":"dark","fontFamily":"Helvetica","fontSize":"13px","roles":{
            "canvas":"#1E1E2E","surface":"#313244","text":"#CDD6F4",
            "edge-label-background":"#FF00FF"}}"##;
        let bytes = render(
            "flowchart TD\n  A[Start] -->|maybe| B[Done]",
            theme,
            1.0,
        )
        .expect("flowchart with an edge label should render");

        let (_, _, pixels) = decode_rgba(&bytes);
        let magenta = pixels
            .chunks_exact(4)
            .filter(|pixel| pixel[0] > 200 && pixel[1] < 60 && pixel[2] > 200 && pixel[3] > 200)
            .count();
        assert!(
            magenta > 100,
            "the edge label background role never reached the pixels: {magenta} magenta pixels"
        );
    }

    /// A scale big enough to blow the pixmap budget has to come back as a
    /// smaller diagram, not a squashed one. Both sides are clamped
    /// independently at the end, so the shrink that gets under the budget has
    /// to be worked out before that and applied to both.
    #[test]
    fn a_scale_beyond_the_budget_shrinks_the_diagram_rather_than_squashing_it() {
        let normal = render(FLOWCHART, &dark_theme_json(), 1.0).expect("1x render");
        let enormous = render(FLOWCHART, &dark_theme_json(), 100.0).expect("100x render");

        let (width, height) = png_size(&enormous);
        assert!(
            width <= MAX_RASTER_SIDE && height <= MAX_RASTER_SIDE,
            "{width}x{height} is over the pixmap budget"
        );

        let (normal_width, normal_height) = png_size(&normal);
        let wanted = f64::from(normal_width) / f64::from(normal_height);
        let got = f64::from(width) / f64::from(height);
        assert!(
            (got - wanted).abs() < 0.01,
            "aspect ratio {got:.3} against {wanted:.3}: the diagram was squashed"
        );
    }

    /// The point of the whole theming path: the same diagram in two themes has
    /// to come out as different pixels. If merman ever stops honouring the
    /// host theme this is the test that notices.
    #[test]
    fn the_same_diagram_in_two_themes_produces_different_pixels() {
        let source = "flowchart TD\n  A[Start] --> B[Done]";
        let dark = render(source, &dark_theme_json(), 2.0).expect("dark render");
        let light = render(source, &light_theme_json(), 2.0).expect("light render");

        assert_ne!(dark, light, "the theme did not reach the rasteriser");
    }

    /// Prose and broken diagrams both come back as MERMAID_ERR_RENDER — merman
    /// rejects them during parse rather than returning an empty output. Swift
    /// treats any failure the same way (fall back to the styled code block),
    /// but pinning the code here means a change in merman's behaviour shows up
    /// as a test failure rather than as a silently different fallback path.
    #[test]
    fn prose_is_not_a_diagram() {
        assert_eq!(
            render("this is just prose", &dark_theme_json(), 2.0).unwrap_err(),
            MERMAID_ERR_RENDER
        );
    }

    #[test]
    fn a_malformed_diagram_does_not_render() {
        assert_eq!(
            render("flowchart TD\n  A[Unclosed --> B{{{", &dark_theme_json(), 2.0).unwrap_err(),
            MERMAID_ERR_RENDER
        );
    }

    #[test]
    fn a_theme_payload_that_is_not_json_is_rejected() {
        assert_eq!(
            render("flowchart TD\n  A --> B", "not json", 2.0).unwrap_err(),
            MERMAID_ERR_INVALID_INPUT
        );
    }

    /// An unknown role id is an error, not something to skip: silently
    /// dropping it would leave that part of the diagram un-themed with
    /// nothing to show for it.
    #[test]
    fn an_unknown_theme_role_is_rejected() {
        let json = r##"{"appearance":"dark","roles":{"chartreuse":"#00FF00"}}"##;
        assert_eq!(
            render("flowchart TD\n  A --> B", json, 2.0).unwrap_err(),
            MERMAID_ERR_INVALID_INPUT
        );
    }

    #[test]
    fn a_role_value_css_rejects_is_rejected() {
        let json = r##"{"appearance":"dark","roles":{"canvas":"red; drop everything"}}"##;
        assert_eq!(
            render("flowchart TD\n  A --> B", json, 2.0).unwrap_err(),
            MERMAID_ERR_INVALID_INPUT
        );
    }

    #[test]
    fn a_scale_that_is_not_a_positive_number_is_rejected() {
        let mut bytes: *mut u8 = std::ptr::null_mut();
        let mut len: usize = 0;
        let source = std::ffi::CString::new("flowchart TD\n  A --> B").unwrap();
        let theme = std::ffi::CString::new(dark_theme_json()).unwrap();
        let fonts = std::ffi::CString::new("[]").unwrap();

        for bad in [0.0f32, -2.0, f32::NAN, f32::INFINITY] {
            let code = mermaid_render_png(
                source.as_ptr(),
                theme.as_ptr(),
                fonts.as_ptr(),
                bad,
                &mut bytes,
                &mut len,
            );
            assert_eq!(code, MERMAID_ERR_INVALID_INPUT, "scale {bad} should be rejected");
            assert!(bytes.is_null());
            assert_eq!(len, 0);
        }
    }

    #[test]
    fn a_null_pointer_is_rejected_rather_than_dereferenced() {
        let mut bytes: *mut u8 = std::ptr::null_mut();
        let mut len: usize = 0;
        let theme = std::ffi::CString::new(dark_theme_json()).unwrap();
        let fonts = std::ffi::CString::new("[]").unwrap();

        assert_eq!(
            mermaid_render_png(
                std::ptr::null(),
                theme.as_ptr(),
                fonts.as_ptr(),
                2.0,
                &mut bytes,
                &mut len
            ),
            MERMAID_ERR_INVALID_INPUT
        );
        assert_eq!(
            mermaid_render_png(
                c"flowchart TD\n A --> B".as_ptr(),
                theme.as_ptr(),
                std::ptr::null(),
                2.0,
                &mut bytes,
                &mut len
            ),
            MERMAID_ERR_INVALID_INPUT
        );
    }

    /// The round trip the Swift side depends on: bytes out, bytes back,
    /// no leak and no double free.
    #[test]
    fn the_c_entry_point_hands_out_a_png_and_takes_it_back() {
        let source = std::ffi::CString::new("sequenceDiagram\n  A->>B: hi").unwrap();
        let theme = std::ffi::CString::new(dark_theme_json()).unwrap();
        let fonts = std::ffi::CString::new(serde_json::to_string(&bundled_fonts()).unwrap()).unwrap();
        let mut bytes: *mut u8 = std::ptr::null_mut();
        let mut len: usize = 0;

        let code = mermaid_render_png(
            source.as_ptr(),
            theme.as_ptr(),
            fonts.as_ptr(),
            2.0,
            &mut bytes,
            &mut len,
        );

        assert_eq!(code, MERMAID_OK);
        assert!(!bytes.is_null());
        assert!(len > 1000);
        let header = unsafe { std::slice::from_raw_parts(bytes, 8) };
        assert_eq!(header, b"\x89PNG\r\n\x1a\n");
        mermaid_free_png(bytes, len);
    }

    // MARK: - Fonts

    /// The file a face was loaded from, for the tests that care where a
    /// typeface came from rather than what it looks like.
    fn face_path(face: &usvg::fontdb::FaceInfo) -> Option<&std::path::Path> {
        match &face.source {
            usvg::fontdb::Source::File(path) => Some(path.as_path()),
            usvg::fontdb::Source::SharedFile(path, _) => Some(path.as_path()),
            usvg::fontdb::Source::Binary(_) => None,
        }
    }

    /// Every one of mrkd's own typefaces has to be in the database the
    /// rasteriser resolves against. This is the assertion that does not care
    /// what the machine running it happens to have installed: it looks for
    /// the bundle's own file paths, which nothing else can supply.
    #[test]
    fn every_bundled_font_file_is_in_the_database() {
        let paths = bundled_fonts();
        let database = font_database(&paths).expect("the font database should build");
        let loaded: std::collections::BTreeSet<&std::path::Path> =
            database.faces().filter_map(face_path).collect();

        for path in &paths {
            assert!(
                loaded.contains(std::path::Path::new(path)),
                "{path} is bundled with mrkd but not in the font database"
            );
        }
    }

    /// The whole point of rasterising here rather than in merman: a diagram
    /// set in the document's own typeface. Same source, same theme, same box —
    /// only the family named in the payload differs, and the pixels must
    /// differ with it.
    #[test]
    fn the_theme_font_family_reaches_the_glyphs() {
        let serif = render(FLOWCHART, &theme_json("dark", "Literata"), 2.0).expect("serif render");
        let sans = render(FLOWCHART, &theme_json("dark", "Inter"), 2.0).expect("sans render");

        assert_eq!(
            png_size(&serif),
            png_size(&sans),
            "the two renders are different sizes, so this compares more than the glyphs"
        );
        assert_ne!(
            serif, sans,
            "Literata and Inter drew identical pixels — the theme's font never reached the rasteriser"
        );
    }

    /// The same diagram in the same theme, with and without the bundle's font
    /// files. Without them `Inter` — mrkd's default body font — resolves to
    /// whatever generic sans the machine has, so the pixels have to change.
    ///
    /// This assumes Inter is not separately installed on the machine running
    /// the tests, which is the same assumption the feature itself rests on:
    /// if it were, there would be nothing here to fix.
    #[test]
    fn without_the_bundled_files_the_theme_font_cannot_be_used() {
        let theme = theme_json("dark", "Inter");
        let with = render_png(FLOWCHART, &theme, &bundled_fonts(), 2.0).expect("bundled render");
        let without = render_png(FLOWCHART, &theme, &[], 2.0).expect("system-only render");

        assert_ne!(
            with, without,
            "loading mrkd's own fonts made no difference to the pixels"
        );
    }

    /// The font database is the expensive part of a render — a few hundred
    /// milliseconds — so it is built once and shared. Pointer identity rather
    /// than a timing assertion, which would be flaky.
    #[test]
    fn the_font_database_is_built_once_and_reused() {
        let paths = bundled_fonts();
        let first = font_database(&paths).expect("first build");
        let second = font_database(&paths).expect("second build");

        assert!(
            Arc::ptr_eq(&first, &second),
            "the font database was rebuilt for an identical font list"
        );
    }

    /// A file that is not a font is a broken build, not something to skip:
    /// carrying on would silently draw every diagram in a fallback face.
    #[test]
    fn a_file_that_is_not_a_font_is_reported() {
        let not_a_font = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("Cargo.toml")
            .to_str()
            .unwrap()
            .to_string();

        assert_eq!(
            render_png(FLOWCHART, &dark_theme_json(), &[not_a_font], 2.0).unwrap_err(),
            MERMAID_ERR_FONT
        );
    }

    #[test]
    fn a_font_list_that_is_not_json_is_rejected() {
        assert_eq!(font_paths("Inter.ttf").unwrap_err(), MERMAID_ERR_INVALID_INPUT);
        assert_eq!(font_paths(r#"["a","b"]"#).unwrap(), vec!["a", "b"]);
    }
}
