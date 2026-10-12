- **`mix brando.migrate54` preloads page vars where templates read them.**
  When a template calls `get_var/2` or `has_var?/2` on `@page`, the task
  adds `:vars` to the `preload` of every `Pages.get_page/1` call whose
  options are a map, written in the call or assigned to a variable in the
  same function (`preload: [:alternate_entries]` becomes
  `[:alternate_entries, :vars]`), and lists the loads in its notice. Once
  every load preloads `:vars`, the `@page` reads are no longer listed, so a
  rerun stops reporting them. Other `get_var/2` reads, and the reads when a
  load's options cannot be updated (listed with file and line), are still
  listed, matched by name.
