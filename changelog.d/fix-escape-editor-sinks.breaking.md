- The `html` var type is called `rich_text`, and its value is sanitized like a text ref's: unsafe markup is refused on save, and a value saved before with unsafe markup renders as its text.
  Run `mix brando.gen.migrations` and migrate (`brando_225`). Match `:rich_text` where code matched `type: :html` on a var; `:html` is still read on the way in (definition files, exports, transfers).
- Liquid modules print `string` and `text` vars, globals and identity links HTML-escaped and with their braces encoded, so markup or Liquid in them shows as text.
  Make a var that is meant to hold HTML a `rich_text` var (the migration guide has the steps); `{{ var | escape }}` keeps printing it once. A comparison, `truncate` or `replace` on such a var sees the escaped text.
- A header ref's text is printed as text, braces included, with its line breaks still as `<br>`; markup in a heading shows as written, a character reference such as `&shy;` as its character.
  Move markup out of headings into text refs; the seeded Hero's heading holds a `<span class="soft">` to remove.
- A picture's caption reaches `render_caption/1` as markup: the image's own title and the credits escaped, a placement's caption sanitized.
  A parser module that overrides `render_caption/1` and escapes `title` or `credits` itself should stop.
- Markdown refs and the `markdown` filter render no raw HTML and no script addresses (`Brando.Markdown` is safe by default; `safe: false` for Markdown no editor wrote).
  Move HTML that Markdown content embeds into a text or HTML ref.
- Media responses carry `X-Content-Type-Options: nosniff` and `Content-Security-Policy: sandbox` (PDFs only the first), so an uploaded SVG or HTML file opened on its own runs no script.
  A web server that serves `/media` itself should send the same headers (see "How media is served" in the media guide).
