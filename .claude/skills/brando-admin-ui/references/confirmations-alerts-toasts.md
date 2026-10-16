# Confirmations, alerts and toasts

Confirmations and alerts use the native `<dialog>` (`assets/src/alerts.js`):
left-aligned, a question as the title, the explanation under it, and compact
buttons on a shared right edge. Write the title as the question and name the
confirm button after its result rather than “OK”:

```heex
<button
  type="button"
  phx-click="recreate_image_sizes"
  data-confirm-title={gettext("Recreate image sizes?")}
  data-confirm={gettext("Every image’s sizes are made again from its original.")}
  data-confirm-ok={gettext("Recreate sizes")}
>
```

Without `data-confirm-title`, the `data-confirm` text becomes the title. Add
`data-confirm-destructive` for actions that delete or discard: the confirm
button turns red and Cancel takes the initial focus. `phx-confirm-click` (the
`ConfirmClick` hook) takes the same title, message and labels.

Toasts share one stack in the bottom right (`assets/src/Toast`). Results of the
user's own actions show a status dot — success fades, errors stay until closed.
Other editors' changes appear quieter, with their initials, and fade sooner.
Messages are plain text.
