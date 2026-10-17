- **The live preview does less work per edit.** Opening, reloading or
  reconnecting the preview no longer morphs the whole page into itself: the
  iframe tells the channel which render it shows, and the cached page is
  replayed only when it missed one. A render identical to what the iframe
  shows (an entry field the template does not display, such as meta or
  slug) is not sent. Unchanged blocks with lazy images are skipped by the
  morph instead of having `srcset` stripped and restored on every update. A
  preview update reads the entry once to authorize itself instead of three
  times, and a field in `rerender_on_change` no longer waits 1.2 seconds
  before rendering.

- **Editing a block inside a slot patches the live preview like any other
  block.** A slot, a block in a slot and a single module with children used
  to re-render the whole page, at most once a second: typing at a steady
  pace showed the last keystroke about 1.4 seconds late and sent around 22
  KB per update. Their root block is now rendered from the editor's state
  and patched alone, as fast as other blocks and with a fraction of the
  data.

- **Ecto tracing no longer slows down queries nobody records.**
  `opentelemetry_ecto` copies the whole process dictionary on every query
  to find the parent span, before the sampler decides, and a process
  rendering a page holds a large one: about 1 ms of a 5 ms live preview
  render, with tracing off. The wrapper `mix brando.gen.otel` generates now
  passes a query on only when a recording span in its process, or in the
  process that started its task, waits for it, so a query outside any span
  no longer becomes a trace of its own. An application generated before
  keeps its `lib/<app>/o11y/open_telemetry_ecto.ex`, which a rerun leaves
  alone as customized; delete it and run `mix brando.gen.otel` again to take
  the change.
