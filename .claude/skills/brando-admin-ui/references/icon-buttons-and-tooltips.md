# Icon-only buttons and tooltips

A button is its icon alone only where the
icon is clear in context and sits beside related, labelled actions: a media
field's sources, a row's duplicate and delete, a toolbar's view switch. The
action an editor came for keeps its label. In a media field that is Upload,
with its icon, the main action beside "Drop … here"; the library (`folder`),
Add from URL (`link`) and a gallery's images (`images`) and videos (`film`)
follow it as icons, in that order, in every field, empty or filled, at every
width. Don't hide labels in narrow containers instead; choose the icon-only
buttons once.

An icon-only button still has a name: a visually hidden label inside it
(`MediaField.icon_button/1` renders one) or an `aria-label`. The tooltip
shows that name; it doesn't replace it. Put the text in `data-tooltip`:

```heex
<button type="button" class="media-button media-button--icon" data-tooltip={gettext("Select image")} phx-click={@browse}>
  <.icon name="folder" /><span class="media-button-label">{gettext("Select image")}</span>
</button>
```

- One delegated listener (`assets/src/tooltips.js`) serves every element
  with `data-tooltip`, including those LiveView adds later: no hook. It shows
  after 400ms of hover and at once on keyboard focus, and goes on leave,
  blur, scroll, Escape and when LiveView removes or changes the element.
- Text that repeats the name is only shown; text that adds to it (a
  shortcut, a longer description) is linked with `aria-describedby` while it
  shows. `data-tooltip-placement` overrides the default `top`.
- Don't add `title` as well: the browser would show a second tooltip.
  Non-interactive text keeps its `title` (a truncated filename, a date's
  full form), where the native hint is enough.
- The legacy Tippy `data-popover` binds only on mount; don't use it for new
  work.
