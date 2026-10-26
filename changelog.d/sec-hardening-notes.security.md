- The remember-me cookie is marked `secure` when the site is served over https.

- A shared preview's link is shown once: the database keeps only a hash of its key, and the brando_222 migration hashes the keys stored before, keeping their links working.

- A scheduled environment copy or live switch is cancelled when it runs if whoever scheduled it may no longer promote the site's environments, or their account is disabled or deleted.

- A form's confirmation emails go to one address at most three times an hour (`confirmation_limit`), so a form cannot be used to send someone email after email.
