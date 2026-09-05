//! A C ABI over [merman](https://github.com/Latias94/merman) for mrkd.
//!
//! Two exported functions: render a Mermaid source to PNG bytes, and free
//! those bytes. Everything else — theming, caching, sizing — is Swift's job,
//! so this stays a thin, auditable boundary.
//!
//! Three things here are load-bearing and not incidental:
//!
//! 1. **Every entry point is wrapped in `catch_unwind`.** merman is a pre-1.0
//!    alpha and the rasteriser under it is a large body of arithmetic. A panic
//!    unwinding out of an `extern "C"` function aborts the process, and this
//!    library is loaded into a sandboxed Quick Look extension as well as the
//!    app. A bad diagram must return an error code, not kill the host.
//! 2. **A renderer is built per call, and that is not the expensive part.**
//!    Host colours are compiled into the engine's site config before parsing,
//!    so the renderer cannot outlive one theme. What actually costs — loading
//!    the system font database, a one-time ~250 ms after which renders are
//!    ~10 ms — lives in a process-wide cache inside merman-export and is
//!    shared by every renderer built here. There is no public way to hand
//!    merman an explicit font list instead; `shared_system_fontdb()` is
//!    private and `RasterOptions` has no font field.
//! 3. **The SVG pipeline is `resvg_safe`.** merman's default SVG puts labels in
//!    `<foreignObject>`, which no non-browser rasteriser resolves. The
//!    `ResvgSafe` preset replaces them with real SVG text.
//! 4. **Theming goes through merman's `HostTheme`, not an init directive.**
//!    An `%%{init: …}%%` directive prepended to the source is parsed but does
//!    not reach the raster path — verified by rendering one and getting
//!    mermaid's stock cream flowchart back. `Presentation::with_theme`
//!    compiles host colours into the engine's site config, which does apply.
//!    The roles fall back to one another (surface-alt to surface, line to
//!    border, and so on), so a handful of colours themes every diagram
//!    family rather than thirty named variables.

use std::collections::BTreeMap;
use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};

use serde::Deserialize;

use merman::svg::export::RasterOptions;
use merman::svg::{
    HostTheme, HostThemeAppearance, Presentation, RootBackgroundPostprocessor, SvgPipeline,
    ThemeRole,
};
use merman::{
    Engine, OperationControl, PngRequest, RenderOutput, RenderRequest, Renderer, SvgRequest,
};

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

fn host_theme(spec: &ThemeSpec) -> Result<HostTheme, i32> {
    let appearance = if spec.appearance == "dark" {
        HostThemeAppearance::Dark
    } else {
        HostThemeAppearance::Light
    };
    let mut theme = HostTheme::new().with_appearance(appearance);

    if let Some(font_family) = &spec.font_family {
        theme = theme
            .try_with_font_family(font_family.as_str())
            .map_err(|_| MERMAID_ERR_INVALID_INPUT)?;
    }
    if let Some(font_size) = &spec.font_size {
        theme = theme
            .try_with_font_size(font_size.as_str())
            .map_err(|_| MERMAID_ERR_INVALID_INPUT)?;
    }
    for (id, value) in &spec.roles {
        let role = ThemeRole::from_id(id).map_err(|_| MERMAID_ERR_INVALID_INPUT)?;
        theme = theme
            .try_with_role(role, value.as_str())
            .map_err(|_| MERMAID_ERR_INVALID_INPUT)?;
    }
    Ok(theme)
}

/// A PNG was produced; `out_bytes` and `out_len` are set and the caller owns
/// the buffer until it passes it back to [`mermaid_free_png`].
pub const MERMAID_OK: i32 = 0;
/// A null pointer, a source that is not valid UTF-8, or a scale that is not a
/// finite positive number.
pub const MERMAID_ERR_INVALID_INPUT: i32 = 1;
/// The source parsed but contained no Mermaid diagram.
pub const MERMAID_ERR_NO_DIAGRAM: i32 = 2;
/// merman rejected the source or the raster step failed.
pub const MERMAID_ERR_RENDER: i32 = 3;
/// The renderer panicked and the unwind was caught here.
pub const MERMAID_ERR_PANIC: i32 = 4;

/// Runs `body`, converting a panic into [`MERMAID_ERR_PANIC`].
///
/// This is the whole reason the release profile keeps `panic = "unwind"`.
fn guarded(body: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(MERMAID_ERR_PANIC)
}

fn render_png(source: &str, theme_json: &str, scale: f32) -> Result<Vec<u8>, i32> {
    let spec: ThemeSpec = serde_json::from_str(theme_json).map_err(|_| MERMAID_ERR_INVALID_INPUT)?;
    // The host colours have to be compiled into the engine's site config
    // before parsing, which is why the renderer is built per call rather than
    // kept in a global. It is cheap: the expensive part of a first render is
    // the system font database, and that lives in a process-wide cache inside
    // merman-export, shared by every renderer this function ever builds.
    let resolved = Presentation::new().with_theme(host_theme(&spec)?).resolve();
    let renderer = Renderer::new().with_engine(resolved.materialize_engine(Engine::new()));

    let svg = SvgRequest {
        // mermaid's own root element carries `background-color: white`, which
        // resvg honours — that is where the white card in a dark document
        // comes from, and neither the host theme nor a transparent raster
        // background removes it. Rewriting it to `transparent` lets the
        // document itself show through, which cannot mismatch the way a
        // painted canvas colour could.
        pipeline: Some(
            SvgPipeline::resvg_safe()
                .with_postprocessor(RootBackgroundPostprocessor::new("transparent")),
        ),
        presentation: resolved.render_policy(),
        ..SvgRequest::default()
    };
    // `background: None` leaves the PNG transparent outside the diagram's own
    // canvas, so it sits on the document rather than on a white card.
    let options = RasterOptions {
        scale,
        ..RasterOptions::default()
    };
    let output = renderer
        .render(RenderRequest::png(
            source,
            OperationControl::default(),
            PngRequest { svg, options },
        ))
        .map_err(|_| MERMAID_ERR_RENDER)?;

    match output {
        RenderOutput::Png(Some(png)) => Ok(png.bytes),
        _ => Err(MERMAID_ERR_NO_DIAGRAM),
    }
}

/// Renders `source` to a PNG at `scale` device pixels per point, in the
/// colours described by `theme_json`.
///
/// # Safety
/// `source` and `theme_json` must be NUL-terminated C strings. `out_bytes`
/// and `out_len` must be writable. On [`MERMAID_OK`] the caller owns
/// `*out_bytes` and must release it with [`mermaid_free_png`]; on any other
/// result they are set to null/0 and nothing is allocated.
#[no_mangle]
pub extern "C" fn mermaid_render_png(
    source: *const c_char,
    theme_json: *const c_char,
    scale: f32,
    out_bytes: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    guarded(|| {
        if source.is_null() || theme_json.is_null() || out_bytes.is_null() || out_len.is_null() {
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

        match render_png(source, theme_json, scale) {
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
        r##"{"appearance":"dark","fontFamily":"Helvetica","fontSize":"13px","roles":{
            "canvas":"#1E1E2E","surface":"#313244","surface-alt":"#45475A",
            "surface-muted":"#181825","text":"#CDD6F4","subtle-text":"#A6ADC8",
            "border":"#585B70","line":"#89B4FA"}}"##
            .to_string()
    }

    fn light_theme_json() -> String {
        r##"{"appearance":"light","fontFamily":"Helvetica","fontSize":"13px","roles":{
            "canvas":"#FFFFFF","surface":"#F6F8FA","surface-alt":"#EAEEF2",
            "surface-muted":"#F0F3F6","text":"#1F2328","subtle-text":"#656D76",
            "border":"#D0D7DE","line":"#0969DA"}}"##
            .to_string()
    }

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
        let bytes = render_png(
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
        let bytes = render_png("flowchart TD\n  A --> B", &dark_theme_json(), 1.0)
            .expect("flowchart should render");

        // IHDR is the first chunk: 8-byte signature, 4-byte length, 4-byte
        // type, then width, height, bit depth, colour type.
        let color_type = bytes[25];
        assert_eq!(color_type, 6, "expected 8-bit RGBA, got colour type {color_type}");

        let corner = decode_first_pixel(&bytes);
        assert_eq!(corner[3], 0, "the top-left pixel is opaque: {corner:?}");
    }

    /// Inflates the image data far enough to recover the top-left pixel.
    /// The first scanline has no row above it, so every filter merman's
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

    /// The point of the whole theming path: the same diagram in two themes has
    /// to come out as different pixels. If merman ever stops honouring the
    /// host theme this is the test that notices.
    #[test]
    fn the_same_diagram_in_two_themes_produces_different_pixels() {
        let source = "flowchart TD\n  A[Start] --> B[Done]";
        let dark = render_png(source, &dark_theme_json(), 2.0).expect("dark render");
        let light = render_png(source, &light_theme_json(), 2.0).expect("light render");

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
            render_png("this is just prose", &dark_theme_json(), 2.0).unwrap_err(),
            MERMAID_ERR_RENDER
        );
    }

    #[test]
    fn a_malformed_diagram_does_not_render() {
        assert_eq!(
            render_png("flowchart TD\n  A[Unclosed --> B{{{", &dark_theme_json(), 2.0).unwrap_err(),
            MERMAID_ERR_RENDER
        );
    }

    #[test]
    fn a_theme_payload_that_is_not_json_is_rejected() {
        assert_eq!(
            render_png("flowchart TD\n  A --> B", "not json", 2.0).unwrap_err(),
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
            render_png("flowchart TD\n  A --> B", json, 2.0).unwrap_err(),
            MERMAID_ERR_INVALID_INPUT
        );
    }

    #[test]
    fn a_role_value_css_rejects_is_rejected() {
        let json = r##"{"appearance":"dark","roles":{"canvas":"red; drop everything"}}"##;
        assert_eq!(
            render_png("flowchart TD\n  A --> B", json, 2.0).unwrap_err(),
            MERMAID_ERR_INVALID_INPUT
        );
    }

    #[test]
    fn a_scale_that_is_not_a_positive_number_is_rejected() {
        let mut bytes: *mut u8 = std::ptr::null_mut();
        let mut len: usize = 0;
        let source = std::ffi::CString::new("flowchart TD\n  A --> B").unwrap();
        let theme = std::ffi::CString::new(dark_theme_json()).unwrap();

        for bad in [0.0f32, -2.0, f32::NAN, f32::INFINITY] {
            let code =
                mermaid_render_png(source.as_ptr(), theme.as_ptr(), bad, &mut bytes, &mut len);
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

        assert_eq!(
            mermaid_render_png(std::ptr::null(), theme.as_ptr(), 2.0, &mut bytes, &mut len),
            MERMAID_ERR_INVALID_INPUT
        );
    }

    /// The round trip the Swift side depends on: bytes out, bytes back,
    /// no leak and no double free.
    #[test]
    fn the_c_entry_point_hands_out_a_png_and_takes_it_back() {
        let source = std::ffi::CString::new("sequenceDiagram\n  A->>B: hi").unwrap();
        let theme = std::ffi::CString::new(dark_theme_json()).unwrap();
        let mut bytes: *mut u8 = std::ptr::null_mut();
        let mut len: usize = 0;

        let code = mermaid_render_png(source.as_ptr(), theme.as_ptr(), 2.0, &mut bytes, &mut len);

        assert_eq!(code, MERMAID_OK);
        assert!(!bytes.is_null());
        assert!(len > 1000);
        let header = unsafe { std::slice::from_raw_parts(bytes, 8) };
        assert_eq!(header, b"\x89PNG\r\n\x1a\n");
        mermaid_free_png(bytes, len);
    }
}
