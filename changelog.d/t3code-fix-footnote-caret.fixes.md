- **Footnote E2E caret setup no longer races deferred editor focus.** Set the
  caret through the editor's selection command and verify its visible position,
  avoiding a stale select-all range being restored between keyboard events.
  Wait for the note drawer's editor to activate before filling its content.
