/*
 * C ABI of rust/mermaid-shim — the Mermaid renderer linked into both mrkd
 * and its sandboxed Quick Look extension.
 *
 * The implementation and the meaning of every status code live in
 * rust/mermaid-shim/src/lib.rs. This header only has to agree with it.
 */

#ifndef MERMAID_SHIM_H
#define MERMAID_SHIM_H

#include <stddef.h>
#include <stdint.h>

#define MERMAID_OK 0
#define MERMAID_ERR_INVALID_INPUT 1
#define MERMAID_ERR_NO_DIAGRAM 2
#define MERMAID_ERR_RENDER 3
#define MERMAID_ERR_PANIC 4

/*
 * Renders Mermaid `source` to PNG bytes at `scale` device pixels per point,
 * in the colours described by `theme_json`.
 *
 * `theme_json` is an object with "appearance" ("light" or "dark"), optional
 * "fontFamily" and "fontSize", and a "roles" map of merman theme-role ids to
 * CSS colours. Swift builds it in MermaidThemePayload.
 *
 * On MERMAID_OK the caller owns *out_bytes and must release it with
 * mermaid_free_png. On every other result *out_bytes is NULL and *out_len
 * is 0. Never unwinds: a panic inside the renderer comes back as
 * MERMAID_ERR_PANIC.
 */
int32_t mermaid_render_png(const char *source,
                           const char *theme_json,
                           float scale,
                           uint8_t **out_bytes,
                           size_t *out_len);

/* Releases a buffer produced by mermaid_render_png. */
void mermaid_free_png(uint8_t *bytes, size_t len);

#endif /* MERMAID_SHIM_H */
