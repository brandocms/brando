- Block editor: a multi module can take images and videos dropped on its blocks, each becoming a new entry of a chosen child module with the file in one of its media, picture or video refs (`media_drop child: "<uid>", ref: :<name>` in a definition file, or Behavior in the module editor).
  Run `mix brando.gen.migrations` for `brando_246`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.

- System check (`mix brando.doctor`): names a multi module whose media drop setting no longer fits its children, which the definition export leaves out.
