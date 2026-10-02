# Forms

A form is something visitors fill in on the site, such as a contact or signup
form. Editors build it in the admin under **Content → Forms**, and the site
renders it with `Brando.HTML.Forms.site_form/1`.

A form is addressed by **key and language**. Each language has its own form,
linked to the others as a [synchronized translation](i18n.md): the source form
decides which fields there are, and each translation words them in its own
language.

Run `mix brando.gen.migrations` for `brando_193` to add the tables.

## Build a form

Open **Content → Forms**, create **Contact** and give it the key `contact`. The
**Form** tab holds the field designer: a canvas of 12-unit rows on the left, and
the form as visitors will see it on the right.

Add fields with **Add field**, or with the shortcuts beside it. Each field opens
for editing when it is added. Arrange fields as in the module editor's variable
canvas: drag a field between rows, drag a row by its handle, and set a field's
width to a full, half, third or quarter row. **req** on a field marks it as
required.

A field's **key** names its value in submissions, so it may only contain
lowercase letters, digits and underscores, starting with a letter. Keys must be
unique within the form.

| Type | Visitors see |
| --- | --- |
| Text, Email, Phone, Number, Date | A single input of that kind |
| Long text | A text area |
| Dropdown | One option from a list |
| Single choice | One option, all shown as radio buttons |
| Multiple choice | Any number of options, as checkboxes |
| Checkbox | A single yes or no |
| Consent | A box visitors must tick, with its details below |
| Section | A heading that starts a new group of fields |
| Hidden | Nothing; its value is sent with every submission |

Dropdowns and choices have options. An option's **value** is what a submission
stores, and its **label** is what visitors see. Hidden fields are kept in their
own tray below the canvas.

The **Messages** tab holds the text above the fields, the submit button's label
and the message shown once the form has been sent.

## Translate a form

Create a translation from the form's **Translations** panel. The translation
starts as a copy of the source, and from then on the source decides:

- which fields there are, in what order and layout
- each field's key, type and whether it is required
- the option values of dropdowns and choices

A translation's designer is read-only. Its edit dialogs show what the source
decides beside the text to translate: labels, placeholders, help text and option
labels, with the source's wording as a reference. An option the source adds
shows its value until it is translated.

Because keys and option values are the same in every language, submissions in
any language can be read side by side.

## Render a form

`Brando.HTML.Forms.site_form/1` renders a form with its fields loaded:

```elixir
{:ok, form} =
  Brando.Forms.get_form(%{
    matches: %{key: "contact", language: "en"},
    status: :published,
    preload: [:fields]
  })
```

```heex
<Brando.HTML.Forms.site_form form={@form} action={~p"/contact"} />
```

Without slots it renders the whole form, grouped by section, with labels,
required markers, help text and errors linked for screen readers. Values are
posted as `fields[<key>]`, or `fields[<key>][]` for multiple choice. Pass
`values` and `errors`, keyed by field key, to fill the form in again after a
failed submission.

Only structural classes (`site-form`, `site-form-field`, …) and data attributes
are emitted; the site styles them. Each field carries `data-width` and, where
the editor started a new row, `data-new-row`, so a 12-column grid lays it out as
it was built:

```css
.site-form-fields { display: grid; grid-template-columns: repeat(12, 1fr); gap: 1rem; }
.site-form-field { grid-column: span 12; }
.site-form-field[data-width="half"] { grid-column: span 6; }
.site-form-field[data-width="third"] { grid-column: span 4; }
.site-form-field[data-width="fourth"] { grid-column: span 3; }
.site-form-field[data-new-row] { grid-column-start: 1; }
```

### Change the markup

`classes` adds classes to the parts — `form`, `section`, `legend`, `fields`,
`field`, `label`, `input`, `help`, `error` and `submit` — for a site that only
needs its own styling.

A `:field` slot replaces the markup of a field. Filter it with `key` or `type`
to replace one field, or one kind of field; the rest keep the default markup.
The slot receives the field, its input name, id, value and errors, and
`default_field/1` renders the built-in markup, so a slot can wrap it instead of
replacing it:

```heex
<Brando.HTML.Forms.site_form form={@form} action={~p"/contact"}>
  <:field :let={f} key="email">
    <div class="email-row">
      <Brando.HTML.Forms.default_field {f} />
      <small>We never share it.</small>
    </div>
  </:field>
  <:field :let={f} type="consent">
    <label class="consent">
      <input type="checkbox" name={f.name} value="true" required />
      I accept the <a href="/privacy">privacy policy</a>
    </label>
  </:field>
  <:submit>Send it</:submit>
</Brando.HTML.Forms.site_form>
```

`:section` replaces a section's heading, `:intro` the text above the fields and
`:submit` the button's content. `only` and `except` take field keys, to render
part of a form.
