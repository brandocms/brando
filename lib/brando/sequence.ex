defmodule Brando.Sequence do
  @moduledoc """
  Helpers for sequencing schema data.

  Adds a `sequence` field to your schema. You still have to sort by
  `sequence` in your schema's module.

  ## Example/Usage

  The `filter` function can return an Ecto queryable (recommended), or a
  list of results.

  Controller:

      use Brando.Sequence,
        [:controller, [schema: Brando.Image,
                       filter: &Brando.Image.for_series_id/1]]

  View:

      use Brando.Sequence, :view

  Schema:

      use Brando.Sequence, :schema

      schema "my_schema" do
        # ...
        sequenced()
      end

  Migration:

      use Brando.Sequence, :migration

      def up do
        create table(:my_schema) do
          # ...
          sequenced()
        end
      end

  Template (`sequence.html.eex`):

      <ul id="sequence" class="clearfix">
      <%= for i <- @items do %>
        <li data-id="<%= i.id %>"><%= i.name %></li>
      <% end %>
      </ul>
      <a id="sort-post"
         href="<%= Brando.helpers.your_path(@conn, :sequence_post, @filter) %>"
         class="btn btn-default">
        Lagre rekkefølge
      </a>
  """

  defmodule Schema do
    @moduledoc false
    @doc false
    defmacro sequenced do
      quote do
        Ecto.Schema.field(:sequence, :integer, default: 0)
      end
    end
  end

  defmodule Migration do
    @moduledoc false
    @doc false
    defmacro sequenced do
      quote do
        Ecto.Migration.add(:sequence, :integer, default: 0)
      end
    end
  end

  @doc false
  @lint false
  def controller(schema_module, filter \\ nil) do
    quote do
      if unquote(filter) do
        @doc """
        Filters the results through `filter`.
        """
        @spec filter_function(term) :: [term]
        def filter_function(filter_param) do
          {:filter, fun} = unquote(filter)
          case fun.(filter_param) do
            res when is_list(res) -> res
            res -> Brando.repo.all(res)
          end
        end

        @spec filter_function() :: [term]
        def filter_function do
          {:filter, fun} = unquote(filter)
          case fun.() do
            res when is_list(res) -> res
            res -> Brando.repo.all(res)
          end
        end
      end

      if unquote(filter) do
        @doc """
        Render the :sequence view with `filter`
        """
        def sequence(conn, %{"filter" => filter}) do
          {:schema, schema_module} = unquote(schema_module)
          items = filter_function(filter)
          conn
          |> assign(:items, items)
          |> assign(:filter, filter)
          |> render(:sequence)
        end

        @doc """
        Render the :sequence view.
        """
        def sequence(conn, _) do
          {:schema, schema_module} = unquote(schema_module)

          conn
          |> assign(:items, filter_function())
          |> render(:sequence)
        end
      else
        def sequence(conn, _) do
          {:schema, schema_module} = unquote(schema_module)
          conn
          |> assign(:items, Brando.repo.all(schema_module))
          |> render(:sequence)
        end
      end

      @doc """
      Sequence schema and render :sequence post
      """
      def sequence_post(conn, %{"order" => ids}) do
        {:schema, schema_module} = unquote(schema_module)
        schema_module.sequence(ids, Range.new(0, length(ids)))
        conn
        |> render(:sequence_post)
      end
    end
  end

  @doc false
  def view do
    quote do
      def render("sequence_post.json", _assigns) do
        %{status: "200"}
      end
    end
  end

  @doc false
  def schema do
    quote do
      import Brando.Sequence.Schema, only: [sequenced: 0]
      def sequence(ids, vals) do
        order = Enum.zip(vals, ids)
        table = __MODULE__.__schema__(:source)
        Brando.repo.transaction(fn -> Enum.map(order, fn ({val, id}) ->
          Ecto.Adapters.SQL.query(
            Brando.repo,
            ~s(UPDATE #{table} SET "sequence" = $1 WHERE "id" = $2),
            [val, String.to_integer(id)])
        end) end)
      end
    end
  end

  @doc false
  def migration do
    quote do
      import Brando.Sequence.Migration, only: [sequenced: 0]
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
end
