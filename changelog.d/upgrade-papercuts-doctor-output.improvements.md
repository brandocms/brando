- `mix brando.doctor` ends with the names of the checks that failed or warned (`4 warnings: Image configs, Sitemap, JSON-LD, Alt text.`), and prints ASCII marks and arrows where the shell's locale is not UTF-8.

- Mix tasks that start the application quietly (`mix brando.doctor` and the data tasks) set the Logger to `:error` again once it has started, so an application that sets its own level as it starts no longer runs its debug log through their output.
