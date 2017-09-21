defmodule Brando.Tag do
  @moduledoc """
  Helpers for tagging schema data.

  Adds a `tags` field to your schema.

  ## Example/Usage

  Controller:

      use Brando.Tag,
        [:controller, [schema: Brando.Post]]

  View:

      use Brando.Tag, :view

  Schema:

      use Brando.Tag, :schema

      schema "my_schema" do
        # ...
        tags
      end

  You will find a function in your schema called `by_tag/1` which returns
  an Ecto Queryable of all records in your schema matching `tag`.

  Also remember to add

      params = params |> Brando.Tag.split_tags

  to your changeset functions

  Migration:

      use Brando.Tag, :migration

      def up do
        create table(:schema) do
          # ...
          tags
        end
      end

  Template (`post_with_tags.html.eex`):

      TODO: show example

  """

  defmodule Schema do
    @moduledoc false
    @doc false
    defmacro tags do
      quote do
        Ecto.Schema.field(:tags, {:array, :string})
      end
    end
  end

  defmodule Migration do
    @moduledoc false
    @doc false
    defmacro tags do
      quote do
        Ecto.Migration.add(:tags, {:array, :varchar})
      end
    end
  end

  @doc false
  def controller(_schema, _filter \\ nil) do
    quote do
    end
  end

  @doc false
  def view do
    quote do
      # TODO: include some convenience helpers here
    end
  end

  @doc false
  def schema do
    quote do
      import Brando.Tag.Schema, only: [tags: 0]

      @doc """
      Search `schema`'s tags field for `tags`
      """
      def by_tag(tag) do
        from m in __MODULE__,
          where: ^tag in m.tags
      end
    end
  end

  @doc false
  def migration do
    quote do
      import Brando.Tag.Migration, only: [tags: 0]
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
  defmacro __using__([:controller, ctrl_opts] = opts) when is_list(opts) do
    apply(__MODULE__, :controller, ctrl_opts)
  end

  @doc """
  Splits the "tags" field in `params` to an array and returns `params`
  """
  def split_tags(params) when params == %{}, do: %{}
  def split_tags(params) do
    if params["tags"] do
      split_tags = params["tags"]
                   |> String.split(",")
                   |> Enum.map(&String.trim/1)

      Map.put(params, "tags", split_tags)
    else
      params
    end
  end
end
