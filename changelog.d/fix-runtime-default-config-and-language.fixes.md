- A `config :brando, :default_language` changed in configuration, in `config/runtime.exs` too, takes effect without recompiling Brando: a new user's content language is the one configured when the user is created.

- Choosing a content language in the admin's top bar saves it on every screen; on the calendar, sites, assets and several other screens it crashed the screen or was not saved.

- The Identity and SEO screens no longer crash when the content language is switched to a language that has no identity or SEO entry yet: the entry is made, as it is when the screen is opened in that language.
