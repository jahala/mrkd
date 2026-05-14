# Smart Typography Test Doc

Sanity-check fixture for smart typography. Each section below covers a transformation
or skip-rule. Toggle "Smart typography" in Settings and observe.

## Quotes

She said "hello there." This should transform to curly quotes.

She's coming. It's not what y'all think. Apostrophes and single quotes go smart.

He said "no," then left. Quotes before punctuation transform properly.

She replied, "He told me, 'wait here.'" Nested quotes handle correctly.

## Em-dash

He paused---then ran. Three hyphens become an em-dash.

She thought -- a long pause -- then continued. Double-hyphen with spaces becomes em-dash.

The result---surprising as it was---stood. Em-dash mid-sentence for interruption.

## En-dash

The project ran 1989--2026. Date ranges use en-dash.

See pages 12--34. Page ranges use en-dash.

Mon--Fri, 9--5. Word and time ranges use en-dash.

## CLI Flag Preservation

Run `--verbose` to enable. Backtick-wrapped flags do not transform.

Pass `--option "value"` to the tool. Code spans preserve both dashes and quotes.

Try --no-cache --verbose --strict-mode. Flag-like patterns in prose stay literal.

## Ellipsis

wait... really? Three dots become an ellipsis character.

Something to think about... Ellipsis at sentence end.

She thought about it, but... never mind. Ellipsis mid-sentence.

## Inline Code

This is `--option "value"` in a span. Backticks protect dashes and quotes.

Test `"foo" -- bar` carefully. Complex code spans stay untransformed.

## Fenced Code Block

```
function example() {
  // CLI flag: --verbose
  // Quotes: "hello" 'world'
  // Dashes: -- --- and...
}
```

Code blocks never transform. Everything inside stays exactly as written.

## Link URLs with Parentheses

[Wikipedia](https://en.wikipedia.org/wiki/Foo_(disambiguation)) URL parens are tracked.

[Another link](https://example.com/(path)/with/parens) Multiple parens in path.

## GFM Table

| Header 1 | Header 2 | Header 3 |
| --- | --- | --- |
| Cell with "quotes" | Cell with -- dash | Cell with ... ellipsis |
| 1989--2026 | --flag | Press --- to halt |

Table cells transform; separator row survives unscathed.

## HTML and Special Tags

Press <kbd>Ctrl</kbd>+<kbd>C</kbd> to copy. HTML tags pass through.

Visit <https://example.com> for more. Angle-bracket links stay literal.

## Real-World Prose

During the '80s---specifically 1989--2026---the team shipped features with `--experimental` flags while the lead said, "Just run `"release" -- staging` and see what happens." Everyone paused... then laughed. The approach worked, but managing quotes, dashes, and ellipsis across code samples, comments, and prose wasn't trivial.
