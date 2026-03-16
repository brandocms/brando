## Villain Text Styles

Text blocks support configurable style presets through `styles`, an embedded schema.

Each style entry has:

- `element` (required): HTML element to target (`p`, `h1`-`h6`, `span`)
- `class` (required): CSS class to apply
- `label` (optional): UI label in the editor toolbar
- `icon` (optional): icon class for toolbar button rendering

Styles are configured per-ref in the Module form under the text block's "Styles" section.

### Behavior

- Paragraph and headings (`p`, `h1`-`h6`) are applied as node attributes (`class` on the block element).
- `span` styles are applied as inline marks and can be toggled on selected text.
- Paragraph remains the base/default style (no class). Style presets should represent named variants such as `lede`.

### Validation

- `element` is restricted to `p`, `h1`-`h6`, and `span`.
- `class` must match CSS-friendly identifiers (`[A-Za-z_][A-Za-z0-9_-]*`).
- Duplicate `{element, class}` pairs are deduplicated when passed to the TipTap component.

### Module Ref Defaults

When creating new text refs in Module Form, Brando initializes `styles` with:

```elixir
[%Style{element: "p", class: "lede", label: "Lede", icon: "hero-circle"}]
```

This gives editors a sensible default variant without making `"paragraph"` a classed style.
