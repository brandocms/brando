defmodule Brando.Sequence do
  @moduledoc """
  Helpers for sequencing models.

  Adds a `sequence` field to your model. You still have to sort by
  `sequence` in your model's module.

  ## Example/Usage

  Controller:

      use Brando.Sequence,
        [:controller, [model: Brando.Image,
                       filter: &Brando.Image.for_series_id/1]]

  View:

      use Brando.Sequence, :view

  Model:

      use Brando.Sequence, :model

      schema "model" do
        # ...
        sequenced
      end

  Migration:

      use Brando.Sequence, :migration

      def up do
        create table(:model) do
          # ...
          sequenced
        end
      end

  Template (`sequence.html.eex`):

      <ul id="sequence" class="clearfix">
      <%= for i <- @items do %>
        <li data-id="<%= i.id %>"><%= i.name %></li>
      <% end %>
      </ul>
      <a id="sort-post"
         href="<%= Helpers.your_path(@conn, :sequence_post, @filter) %>"
         class="btn btn-default">
        Lagre rekkefølge
      </a>
  """
  defmodule Model do
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
  def controller(model, filter \\ nil) do
    quote do
      if unquote(filter) do
        @doc """
        Filters the results through `filter`.
        """
        def filter_function(filter_param) do
          {:filter, fun} = unquote(filter)
          fun.(filter_param)
        end
      end
      @doc """
      Render the :sequence view.
      """
      def sequence(conn) do
        {:model, model} = unquote(model)
        conn
        |> assign(:items, Brando.repo.all(model))
        |> render(:sequence)
      end
      if unquote(filter) do
        @doc """
        Render the :sequence view with `filter`
        """
        def sequence(conn, %{"filter" => filter}) do
          {:model, model} = unquote(model)
          items = filter_function(filter)
          conn
          |> assign(:items, items)
          |> assign(:filter, filter)
          |> render(:sequence)
        end
      end
      def sequence(conn, %{}) do
        {:model, model} = unquote(model)
        conn
        |> assign(:items, Brando.repo.all(model))
        |> render(:sequence)
      end

      @doc """
      Sequence model and render :sequence post
      """
      def sequence_post(conn, %{"order" => ids}) do
        {:model, model} = unquote(model)
        model.sequence(ids, Range.new(0, length(ids)))
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
  def model do
    quote do
      import Brando.Sequence.Model, only: [sequenced: 0]
      def sequence(ids, vals) do
        order = Enum.zip(vals, ids)
        table = __MODULE__.__schema__(:source)
        Brando.repo.transaction(fn -> Enum.map(order, fn ({val, id}) ->
          Ecto.Adapters.SQL.query(
            Brando.repo, "UPDATE #{table} SET \"sequence\" = $1 " <>
                         "WHERE \"id\" = $2",
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
