- In legacy mode an event in an application's own admin LiveView or LiveComponent is refused to a User-role account unless the module declares it read-only.
  List the events that store and send nothing: `def __read_only_events__, do: ~w(open_tab toggle_row)`.
- `Brando.Revisions.protect_revision`, `delete_revision`, `purge_revisions/2` and `Brando.Publisher.cancel_scheduled_revision` take the acting user as a new last argument.
  Pass the user, or `:system` from trusted maintenance code.
