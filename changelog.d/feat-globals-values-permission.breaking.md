- Groups that exist keep their grants: an Editor group prepared before the upgrade only views global values until it is given Global sets · Edit values.
  Tick Edit values for the group under **Configuration → Permissions** to let it fill in values.

- A var's owner key (`page_id`, `module_id`, `global_set_id` and the like) is no longer cast from params.
  Set it on the struct when creating a var on its own: `%Var{page_id: page.id} |> Var.changeset(params)`.
