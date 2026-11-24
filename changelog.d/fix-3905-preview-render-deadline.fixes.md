- A preview link of a translation a proposal creates, from `preview_proposal` or the admin's shareable link, stops a page that renders past the repo's timeout and lets go of the source and translation group it holds, as the review page's frame already did.

- A proposal preview and an apply that make translations of the same sources take their locks in one order, so neither aborts the other with a deadlock.

- Applying a proposal's `translate` batch saves the translation's pending version it rechecked, not one a translation sync recomputed in between, and refuses by name a translation whose group got another source since the apply took its locks.
