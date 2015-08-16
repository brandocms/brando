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
  defmacro __using__([:controller, controller_opts] = opts) when is_list(opts) do
    apply(__MODULE__, :controller, controller_opts)
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