#!/usr/bin/env python3
"""Mutation harness: break covered code, prove the test notices, put it back.

Each entry breaks exactly one thing the new tests are supposed to be watching.
A test that still passes with its subject broken is not testing anything, so
this runs in the foreground and reports a table.

    scripts/mutation-check.py M1 M2 ...   # a subset
    scripts/mutation-check.py --list

The file is restored and its SHA-256 compared with the original after every
mutation, whether the run passed, failed, or was interrupted.
"""

import hashlib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUST = ROOT / "rust/mermaid-shim/src/lib.rs"
RENDERER = ROOT / "Sources/Engine/MermaidRenderer.swift"
PROVIDER = ROOT / "Sources/Engine/DiagramAttachmentProvider.swift"
FONTS = ROOT / "Sources/Engine/BundledFonts.swift"

MUTATIONS = [
    # id, file, old, new, tests expected to fail, runner
    ("M1", RUST,
     """        let before = database.len();
        database.load_font_file(path).map_err(|_| MERMAID_ERR_FONT)?;
        if database.len() == before {
            return Err(MERMAID_ERR_FONT);
        }""",
     "        let _ = path;",
     "every_bundled_font_file_is_in_the_database", "cargo"),

    ("M1b", RUST,
     """        let before = database.len();
        database.load_font_file(path).map_err(|_| MERMAID_ERR_FONT)?;
        if database.len() == before {
            return Err(MERMAID_ERR_FONT);
        }""",
     "        let _ = path;",
     "without_the_bundled_files_the_theme_font_cannot_be_used", "cargo"),

    ("M2", RUST,
     "        font_family: spec.font_family.as_deref().map(css_font_family).transpose()?,",
     "        font_family: None,",
     "the_theme_font_family_reaches_the_glyphs", "cargo"),

    ("M3", RUST,
     """        if database.len() == before {
            return Err(MERMAID_ERR_FONT);
        }""",
     "        let _ = before;",
     "a_file_that_is_not_a_font_is_reported", "cargo"),

    ("M4", RUST,
     """    if let Ok(cached) = cache.read() {
        if let Some((key, database)) = cached.as_ref() {
            if key == paths {
                return Ok(Arc::clone(database));
            }
        }
    }""",
     "    let _ = &cache;",
     "the_font_database_is_built_once_and_reused", "cargo"),

    ("M5", RUST,
     "    serde_json::from_str(json).map_err(|_| MERMAID_ERR_INVALID_INPUT)",
     "    Ok(serde_json::from_str(json).unwrap_or_default())",
     "a_font_list_that_is_not_json_is_rejected", "cargo"),

    ("M6", RUST,
     "            scoped_css: Some(EDGE_LABEL_OVERLAY_CSS.to_string()),\n",
     "",
     "a_theme_role_colour_reaches_the_pixels", "cargo"),

    ("M10", RUST,
     '            root_background: HostThemeRootBackground::Color("transparent".to_string()),',
     "            root_background: HostThemeRootBackground::Canvas,",
     "the_rendered_background_is_transparent", "cargo"),

    # The role id table: a value that lands on the wrong role is as bad as one
    # that is dropped. `note-background` is a role a flowchart never draws.
    ("M11", RUST,
     '            "edge-label-background" => &mut roles.edge_label_background,',
     '            "edge-label-background" => &mut roles.note_background,',
     "a_theme_role_colour_reaches_the_pixels", "cargo"),

    # The uniform shrink that keeps an oversized diagram in proportion. Without
    # it each side is clamped on its own and the diagram comes out squashed.
    ("M12", RUST,
     "        effective *= shrink * 0.999_999;",
     "        effective *= 1.0;",
     "a_scale_beyond_the_budget_shrinks_the_diagram_rather_than_squashing_it", "cargo"),

    ("S1", PROVIDER,
     "                fontURLs: fontURLs,",
     "                fontURLs: [],",
     "testTheProvidersFontsReachTheDiagram", "swift"),

    ("S2", RENDERER,
     "        guard let fontData = try? JSONSerialization.data(withJSONObject: fontURLs.map(\\.path)),",
     "        guard let fontData = try? JSONSerialization.data(withJSONObject: [String]()),",
     "testWithoutTheBundledFilesTheBodyFontCannotBeUsed", "swift"),

    ("S2b", RENDERER,
     "        guard let fontData = try? JSONSerialization.data(withJSONObject: fontURLs.map(\\.path)),",
     "        guard let fontData = try? JSONSerialization.data(withJSONObject: [String]()),",
     "testTheDocumentsBodyFontChangesTheGlyphs", "swift"),

    ("S3", FONTS,
     '            .filter { $0.pathExtension.lowercased() == "ttf" }',
     "",
     "testNothingThatIsNotAFontIsPickedUp", "swift"),

    ("S3b", FONTS,
     '            .filter { $0.pathExtension.lowercased() == "ttf" }',
     '            .filter { $0.pathExtension.lowercased() == "otf" }',
     "testEveryShippedTypefaceIsFound", "swift"),

    ("S4", FONTS,
     "            .sorted { $0.path < $1.path }",
     "            .sorted { $0.path > $1.path }",
     "testTheOrderIsStable", "swift"),

    ("S5", FONTS,
     """        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []""",
     """        let contents = try! FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )""",
     "testADirectoryThatIsNotThereIsEmptyRatherThanFatal", "swift"),

    ("S6", RENDERER,
     "        case MERMAID_ERR_FONT: self = .fontLoadFailed\n",
     "",
     "testStatusCodesMapToTheirFailures", "swift"),
    ("S6b", RENDERER,
     "        case MERMAID_ERR_FONT: self = .fontLoadFailed\n",
     "",
     "testAFileThatIsNotAFontIsReported", "swift"),

]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(runner, test):
    if runner == "cargo":
        command = [
            "cargo", "test", "--release",
            "--manifest-path", str(ROOT / "rust/mermaid-shim/Cargo.toml"),
            "--", "--exact", f"tests::{test}",
        ]
    else:
        command = ["swift", "test", "--filter", test]
    done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    output = done.stdout + done.stderr
    ran = "running 1 test" if runner == "cargo" else "Executed 1 test"
    if done.returncode == 0:
        # A pass only counts if the test actually ran: a filter that matches
        # nothing exits 0 and would otherwise read as a surviving mutation.
        return ("PASSED" if ran in output else "NO SUCH TEST"), output
    # A mutation that makes the process abort — a `try!` that now throws —
    # never reaches the summary line, and is as dead as an assertion failure.
    return ("FAILED" if ran in output else "CRASHED"), output


def main():
    wanted = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--list" in sys.argv:
        for mutation in MUTATIONS:
            print(mutation[0], mutation[4])
        return 0

    rows = []
    exit_code = 0
    for identifier, path, old, new, test, runner in MUTATIONS:
        if wanted and identifier not in wanted:
            continue
        original = path.read_text()
        before = digest(path)
        if old not in original:
            print(f"{identifier}: MUTATION DOES NOT APPLY", flush=True)
            exit_code = 1
            continue
        try:
            path.write_text(original.replace(old, new, 1))
            verdict, output = run(runner, test)
        finally:
            path.write_text(original)
        after = digest(path)
        restored = "byte-identical" if before == after else "RESTORE FAILED"
        if before != after or verdict not in ("FAILED", "CRASHED"):
            exit_code = 1
            print(output[-2500:], flush=True)
        rows.append((identifier, path.name, test, verdict, restored))
        print(f"{identifier:5} {path.name:32} {test:52} {verdict:8} {restored}", flush=True)

    print()
    print(f"{'id':5} {'file':32} {'test':52} {'verdict':8} restored")
    for row in rows:
        print(f"{row[0]:5} {row[1]:32} {row[2]:52} {row[3]:8} {row[4]}")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
