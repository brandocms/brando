defmodule Brando.Tag do
  @moduledoc """
  Helpers for tagging models.

  Adds a `tags` field to your model.

  ## Example/Usage

  Controller:

      use Brando.Tag,
        [:controller, [model: Brando.Post]]

  View:

      use Brando.Tag, :view

  Model:

      use Brando.Tag, :model

      schema "model" do
        # ...
        tags
      end

  You will find a function in your model called `by_tag/1` which returns
  an Ecto Queryable of all records in your model matching `tag`.

  Also remember to add

      params = params |> Brando.Tag.split_tags

  to your changeset functions

  Migration:

      use Brando.Tag, :migration

      def up do
        create table(:model) do
          # ...
          tags
        end
      end

  Template (`post_with_tags.html.eex`):

      TODO: show example

  """
  defmodule Model do
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
  def controller(_model, _filter \\ nil) do
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
  def model do
    quote do
      import Brando.Tag.Model, only: [tags: 0]
      import Brando.Utils, only: [search_model_by_tag: 2]

      def by_tag(tag) do
        search_model_by_tag(__MODULE__, tag)
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
  def split_tags(:empty), do: :empty
  def split_tags(params) do
    if params["tags"] do
      params |> Map.put("tags", String.split(params["tags"], ","))
    else
      params
    end
  end
end
