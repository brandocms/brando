defmodule Brando.EntryQueryTestContext do
  @moduledoc false

  def get_active_entry(opts) do
    send(self(), {:active_entry_options, opts})
    {:ok, :active_entry}
  end
end

defmodule Brando.EntryQueryTestContext.ActiveEntry do
  @moduledoc false

  use Brando.Blueprint,
    application: "Brando",
    domain: "EntryQueryTestContext",
    schema: "ActiveEntry",
    singular: "active_entry",
    plural: "active_entries",
    gettext_module: Brando.Gettext

  relations do
    relation :owner, :belongs_to, module: Brando.Users.User
  end
end
