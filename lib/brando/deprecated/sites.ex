# Deprecated names for the Identity's embedded schemas, which claimed
# top-level `Brando.*` names from `lib/brando/sites/` (#2833); renamed to
# `Brando.Sites.*` in 0.55 and removed in 0.57.
#
# A module's struct cannot be lent to another name: `%Brando.Link{}`, as a
# literal or a pattern, and a Blueprint relation's `module: Brando.Link`
# need the new name (`mix brando.migrate55` rewrites them). Calls to the
# changeset functions keep working.

defmodule Brando.Config do
  @moduledoc false

  for arity <- 1..5 do
    args = Macro.generate_arguments(arity, __MODULE__)
    @deprecated "Use Brando.Sites.Config.changeset/#{arity} instead"
    defdelegate changeset(unquote_splicing(args)), to: Brando.Sites.Config
  end
end

defmodule Brando.Link do
  @moduledoc false

  for arity <- 1..5 do
    args = Macro.generate_arguments(arity, __MODULE__)
    @deprecated "Use Brando.Sites.Link.changeset/#{arity} instead"
    defdelegate changeset(unquote_splicing(args)), to: Brando.Sites.Link
  end
end

defmodule Brando.Meta do
  @moduledoc false
  # `Brando.Meta.HTML` (lib/brando/meta/html.ex) renders a page's <meta>
  # tags and stays where it is: it is no part of this schema.

  for arity <- 1..5 do
    args = Macro.generate_arguments(arity, __MODULE__)
    @deprecated "Use Brando.Sites.Meta.changeset/#{arity} instead"
    defdelegate changeset(unquote_splicing(args)), to: Brando.Sites.Meta
  end
end
