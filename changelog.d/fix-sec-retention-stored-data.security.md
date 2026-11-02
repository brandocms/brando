- Permanently deleting a site or environment deletes its form submissions, drafts, assistant conversations, proposals and transfer receipts, which a later site with the same keys could otherwise read.

  Rows left by earlier deletions stay until you remove them: see "Rows left by deleted sites and forms" in `guides/migrating_from_053.md`.

- Deleting the last language of a form deletes its submissions, and the delete dialog says how many. Deleting forms from the list asks first. Rows of a form since renamed stay.

- A 404 request with an unstorable Referer, or a long multibyte URL, no longer discards the other 404 counts in the same flush.

- An assistant conversation opens whatever a stored entry title or a model's arguments hold.
