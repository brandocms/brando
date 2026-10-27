# Linked entries for `Brando.Sites.ServicesTest`: the context hands back the
# entry a test stored under its id, so `Services.resolve/1` loads it through
# `EntryQuery.get/2` without a table.
defmodule Brando.ServiceDescriptionTest do
  @moduledoc false

  def put_entry(%{id: id} = entry), do: Process.put({__MODULE__, id}, entry)

  def get_intro_page(opts), do: fetch(opts)
  def get_plain_page(opts), do: fetch(opts)
  def get_raising_page(opts), do: fetch(opts)

  defp fetch(%{matches: %{id: id}}) do
    case Process.get({__MODULE__, id}) do
      nil -> {:error, {:not_found, id}}
      entry -> {:ok, entry}
    end
  end
end

# Its page's description falls back to the intro, like a case category's
defmodule Brando.ServiceDescriptionTest.IntroPage do
  @moduledoc false

  use Brando.Blueprint,
    application: "Brando",
    domain: "ServiceDescriptionTest",
    schema: "IntroPage",
    singular: "intro_page",
    plural: "intro_pages",
    gettext_module: Brando.Gettext

  attributes do
    attribute :meta_description, :text
    attribute :intro, :text
    attribute :rendered_blocks, :text
  end

  meta_schema do
    field ["description", "og:description"], &fallback(&1, [:meta_description, {:strip_tags, :intro}])
    # Needs preloads the service read does not load; must not run
    field "og:image", fn _ -> raise "og:image evaluated" end
  end
end

# Its meta_schema prints no description
defmodule Brando.ServiceDescriptionTest.PlainPage do
  @moduledoc false

  use Brando.Blueprint,
    application: "Brando",
    domain: "ServiceDescriptionTest",
    schema: "PlainPage",
    singular: "plain_page",
    plural: "plain_pages",
    gettext_module: Brando.Gettext

  attributes do
    attribute :meta_description, :text
    attribute :title, :string
    attribute :rendered_blocks, :text
  end

  meta_schema do
    field ["title", "og:title"], & &1.title
  end
end

defmodule Brando.ServiceDescriptionTest.RaisingPage do
  @moduledoc false

  use Brando.Blueprint,
    application: "Brando",
    domain: "ServiceDescriptionTest",
    schema: "RaisingPage",
    singular: "raising_page",
    plural: "raising_pages",
    gettext_module: Brando.Gettext

  attributes do
    attribute :rendered_blocks, :text
  end

  meta_schema do
    field ["description", "og:description"], fn _ -> raise ArgumentError, "bad description" end
  end
end
