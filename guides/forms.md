# Forms

A form is something visitors fill in on the site, such as a contact or signup
form. Editors build it in the admin under **Configuration → Forms**, and the site
renders it with `Brando.HTML.Forms.site_form/1`.

<!-- usage-rules:start -->

A form is addressed by **key and language**. Each language has its own form,
linked to the others as a [synchronized translation](i18n.md): the source form
decides which fields there are, and each translation words them in its own
language.

Run `mix brando.gen.migrations` for `brando_194`, `brando_195` and `brando_196`
to add the tables.

<!-- usage-rules:end -->

## Build a form

Open **Configuration → Forms**, create **Contact** and give it the key `contact`. The
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
and the message shown once the form has been sent. Leave the last two empty to
use the site's wording. **Page after sending** sends visitors on to a page
instead of showing the message: a path on the site, such as `/thank-you`, or a
full address.

The **Submissions** tab sets who each submission is emailed to, the
confirmation sent to the visitor, and how long submissions are kept; see
[Email](#email) and [Keeping submissions](#keeping-submissions) below.

Once a form is saved, its screen lists the entries whose blocks hold it, in any
of its languages. Deleting a form from the list names them too: a page that
holds a deleted form shows nothing in its place. A form named by key in a
module's code (`{% form 'contact' %}`) is not listed.

## Messages

What visitors read around every form — the submit button, what is said once a
form is sent or could not be, and the error next to a field that is empty or
filled in wrongly — is set once for the site, under **Configuration → Forms →
Messages**. Each message has a field per content language.

The first time the page is opened, the messages are filled in with Brando's own
wording in the languages Brando is translated into (English and Norwegian). The
others are left empty and marked as missing, for an editor to write. A language
left empty uses Brando's wording, in English where Brando has no translation.

## Translate a form

Create a translation from the form's **Translations** panel. The translation
starts as a copy of the source, and from then on the source decides:

- which fields there are, in what order and layout
- each field's key, type and whether it is required
- the option values of dropdowns and choices
- who submissions are emailed to, whether the visitor gets a confirmation, and
  how long submissions are kept

Each translation words its own email subjects and confirmation, and has its
own page after sending. A translation's designer is read-only. Its edit dialogs show what the source
decides beside the text to translate: labels, placeholders, help text and option
labels, with the source's wording as a reference. An option the source adds
shows its value until it is translated.

Because keys and option values are the same in every language, submissions in
any language can be read side by side.

When content moves between installations with content transfer, a block's form
is matched by its key on the destination. Without a form by that key there,
the import asks which form to use.

## Render a form

<!-- usage-rules:start -->

### In a block

Give a module a **Form** variable and render it with the `form` tag. Editors
then pick the form in the block:

```liquid
{% form contact %}
{% form contact { class: 'wide', id: 'contact-us' } %}
```

The tag also takes a key, `{% form 'contact' %}`, for a form that is always
the same. Either way it shows the published form with that key in the entry's
language, so a translated page shows the translated form. Saving a form
re-renders the entries whose blocks hold it in a variable; an entry that names
a form by key in its module code is re-rendered when it is next saved.

A HEEx module renders it with `<.site_form>`, which takes the same slots as
`site_form/1` below:

```heex
<.site_form form={@contact}>
  <:submit>Send it</:submit>
</.site_form>
```

Liquid cannot pass slots. For your own markup in every Liquid block, set a
function component that the tag renders instead; it gets the same assigns:

```elixir
config :brando, Brando.Forms, component: {MyAppWeb.Forms, :site_form}
```

### In a template

`Brando.HTML.Forms.site_form/1` renders a form with its fields loaded:

```elixir
form = Brando.Forms.get_published_form("contact", "en")
```

```heex
<Brando.HTML.Forms.site_form form={@form} />
```

Without slots it renders the whole form, grouped by section, with labels,
required markers, help text and errors linked for screen readers. Values are
posted as `fields[<key>]`, or `fields[<key>][]` for multiple choice. Pass
`values` and `errors`, keyed by field key, to fill the form in again after a
failed submission.

<!-- usage-rules:end -->

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

### In a LiveView

`Brando.HTML.Forms.LiveForm` renders a form inside a LiveView with the same
slots as `site_form/1`. A field shows its errors once the visitor has been in
it, and the form is sent over the LiveView's socket, through the same checks
and email as a posted form:

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:contact, Brando.Forms.get_published_form("contact", "en"))
   |> assign(:form_meta, Brando.HTML.Forms.LiveForm.connect_meta(socket))}
end
```

```heex
<.live_component module={Brando.HTML.Forms.LiveForm} id="contact" form={@contact} meta={@form_meta}>
  <:submit>Send it</:submit>
</.live_component>
```

`connect_meta/1` reads the visitor's IP address and user agent for the rate
limit and the stored submission, so the socket must give them:

```elixir
socket "/live", Phoenix.LiveView.Socket,
  websocket: [connect_info: [:peer_data, :user_agent, session: @session_options]]
```

With Turnstile, load its script in the layout. A Turnstile token is good for
one submission, so a visitor whose check fails is asked to reload the page.

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

`:success` and `:failure` replace the messages shown once the form has been
sent, or when sending failed.

## Submissions

A form posts to Brando's route, `/__brando/forms/<key>`, which `page_routes/1`
adds to your browser pipeline. The submission is checked against the form's
fields, and stored. **Content → Forms** lists every form with how many
submissions it has had and when the latest came in; the item appears once a
form has been built. Open a form there to read, delete or export its
submissions as CSV. A submission in any
language is listed with the form, and keeps the labels its fields had when it
was sent.

The form submits itself with a small inline script: errors appear by their
fields, and the success message replaces the form. Without JavaScript the post
returns to the page at the `#<form id>-sent` (or `-failed`) anchor, and a
`:target` rule shows the message. A form with a page after sending goes there
instead, either way; on a static site a path is resolved against the page the
form was on. Pass `enhance={false}` to leave the script out,
and `nonce` when your content security policy requires one.

### Email

Add **Recipients** on the form's **Submissions** tab, and each submission is
emailed to them, with the visitor's answers labelled as on the form, the page it
was sent from and a link to it in the admin. A recipient marked **Blind copy**
is hidden from the others; when every recipient is one, the email is addressed
to the site's own sender. Replies go to the first email address the visitor
filled in.

The **Subject** is worded per language and can carry what the visitor filled
in, by field key: `Message from {{ name }}`. A choice shows its label. Left
empty, the subject is "New submission" and the form's title.

The email is sent from a background job (`Brando.Worker.FormNotification`)
through the mailer set up in the [Email guide](email.md), and tried again up to
five times when the provider fails. The form's submissions page has an
**Email** column — sent, queued, or not sent — and an opened submission says
why one was not sent and has **Send again**, which sends it to the recipients
the form has now. With no mailer configured, nothing is sent and the
submission says so; it is stored either way.

**Send a confirmation** emails the visitor at the address they filled in, so
the form needs an Email field. It carries the confirmation message, or the
success message when there is none, and a copy of what they sent, without
hidden fields. Replies go to the form's first recipient that is not a blind
copy. Anyone can type someone else's address into a form, so use Turnstile on
forms that send confirmations.

### Keeping submissions

**Delete submissions after (days)** keeps a form's submissions for that long.
`Brando.Worker.FormSubmissionPurger` deletes older ones every night at 05:15
UTC, in every active environment. Leave it empty to keep them until they are
deleted by hand. An application that sets its own `config :brando, Oban`
replaces Brando's crontab, and adds the job to its own:

```elixir
{"15 5 * * *", Brando.Worker.FormSubmissionPurger}
```

### Protection

- **CSRF.** A form carries the visitor's CSRF token, checked by your pipeline's
  `protect_from_forgery`. Block HTML is stored when an entry is saved, so a form
  in a block stores a `$csrftoken` placeholder that pages, fragments and
  `Brando.HTML.render_blocks/1` fill in as they are sent. If you output stored
  block HTML some other way, pass it through `Brando.HTML.replace_csrf_token/1`.
  A cache in front of the site would keep the token of whoever the page was
  cached for, so before it sends, the form's script fetches the visitor's own
  from `/__brando/forms/csrf-token` (also added by `page_routes/1`). A visitor
  without JavaScript on such a cached page is refused.
- **Origin.** A post whose `Origin` (or `Referer`) is another site is refused.
- **Honeypot.** A hidden field people never see; a submission that fills it in
  is answered as a success and not stored.
- **Rate limit.** Ten submissions per visitor and 200 per form in ten minutes,
  counted by a hash of the visitor's IP address:

  ```elixir
  config :brando, Brando.Forms,
    rate_limit: [window: :timer.minutes(10), per_visitor: 10, per_form: 200]
  ```

- **Turnstile.** With Cloudflare Turnstile keys configured, forms render the
  widget and every submission must carry a token Cloudflare confirms:

  ```elixir
  config :brando, Brando.Forms,
    turnstile: [
      site_key: System.get_env("TURNSTILE_SITE_KEY"),
      secret_key: System.get_env("TURNSTILE_SECRET_KEY")
    ]
  ```

  Brando's default production headers allow `challenges.cloudflare.com`; if you
  set your own content security policy, allow it in `script-src` and
  `frame-src`.

<!-- usage-rules:start -->

### Static sites

A statically delivered site (`delivery_mode: :static`) has no backend serving
its pages, and no session for a CSRF token. Its forms post to your Brando
backend instead, at `/__brando/forms/static/<site>/<environment>/<key>`, and the
request must come from one of the site's own domains. Add the route at the top
level of your router, outside the browser pipeline:

```elixir
form_routes()

scope "/" do
  pipe_through :browser
  page_routes()
end
```

The forms post to the endpoint's URL; set another with
`config :brando, Brando.Forms, submit_url: "https://admin.example.com"`.

<!-- usage-rules:end -->
