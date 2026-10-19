- **Installation has a guide of its own.** `guides/installation.md` takes the
  setup steps from the old "Installation and generators" guide, from creating
  the Phoenix application to the first sign-in, and sits next to the overview
  in the docs. `guides/generators.md` keeps generating content types, framework
  migrations and upgrades, the auxiliary generators and the task reference.
  The examples name the application `my_app`, like the other guides, and the
  guide says which flags go to `mix phx.new` and why. The setup steps now run
  `mix brando.gen.mail` first: the recommended `--no-mailer` application had no
  mailer, so password resets and form notifications could not be sent.

- **`install.sh` is removed from the repository.** It only printed the
  Igniter installation steps, which the installation guide has.
