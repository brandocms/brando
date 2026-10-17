<%
  context = inspect(context_module)
  schema = inspect(schema_module)
  # Entries in another language may share a slug; show the request's language.
  current_language = if site_layouts, do: "conn.assigns.language", else: "Brando.config(:default_language)"
  list_opts =
    Enum.join(
      (if status, do: ["status: :published"], else: []) ++
        (if language, do: ["filter: %{language: #{current_language}}"], else: []),
      ", "
    )
  status_opt = if status, do: ", status: :published", else: ""
  preload_opt = if alternates, do: ", preload: [:alternate_entries]", else: ""
  language_match = if language and param == "slug", do: ", language: #{current_language}", else: ""
  get_call = "#{context}.get_#{singular}(%{matches: %{#{param}: #{param}#{language_match}}#{status_opt}#{preload_opt}})"
%>defmodule <%= inspect controller_module %> do
<%= if site_layouts do %>  use BrandoWeb, :controller

  plug :put_view, html: <%= inspect html_module %>
  plug :put_layout, false
  plug :put_root_layout, html: {<%= inspect site_layouts %>, :root}

  alias Brando.Pages

  # Renders the site's 404 page, or follows a redirect, for {:error, {_, :not_found}}.
  action_fallback BrandoWeb.FallbackController

  def index(conn, _params) do
    with {:ok, entries} <- <%= context %>.list_<%= plural %>(%{<%= list_opts %>}),
         {:ok, partials} <- partials(conn) do
      conn
      |> put_section(<%= inspect plural %>)
      |> put_title(<%= inspect Phoenix.Naming.humanize(plural) %>)
      |> assign(:partials, partials)
      |> render(:index, entries: entries)
    end
  end

  def show(conn, %{<%= inspect param %> => <%= param %>}) do
    with <%= if param == "id" do %>{:ok, id} <- parse_id(id),
         <% end %>{:ok, entry} <- <%= get_call %>,
         {:ok, partials} <- partials(conn) do
      conn
      |> put_section(<%= inspect singular %>)
      |> put_meta(<%= schema %>, entry)<%= if alternates do %>
      |> put_hreflang(entry)<% end %><%= if text_field do %>
      |> put_title(entry.<%= main_field %>)<% end %>
      |> assign(:partials, partials)
      |> render(:show, entry: entry)
    end
  end

  defp partials(conn) do
    Pages.get_fragments(%{
      filter: %{parent_key: "partials", language: conn.assigns.language},
      cache: {:ttl, :infinite}
    })
  end
<% else %>  use <%= web_module %>, :controller

  plug Brando.Plug.Tenant

  def index(conn, _params) do
    {:ok, entries} = <%= context %>.list_<%= plural %>(%{<%= list_opts %>})
    render(conn, :index, entries: entries)
  end

  # A missing entry raises Ecto.NoResultsError, which Phoenix renders as a 404.
  def show(conn, %{<%= inspect param %> => <%= param %>}) do
<%= if param == "id" do %>    with {:ok, id} <- parse_id(id),
         {:ok, entry} <- <%= get_call %> do
      render(conn, :show, entry: entry)
    else
      {:error, {_, :not_found}} -> raise Ecto.NoResultsError, queryable: <%= schema %>
    end
<% else %>    case <%= get_call %> do
      {:ok, entry} -> render(conn, :show, entry: entry)
      {:error, {_, :not_found}} -> raise Ecto.NoResultsError, queryable: <%= schema %>
    end
<% end %>  end
<% end %><%= if param == "id" do %>
  # A malformed id is a missing entry, not a query error.
  defp parse_id(id) do
<%= if id_type == :binary_id do %>    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:<%= singular %>, :not_found}}
    end
<% else %>    case Integer.parse(id) do
      # Within the range of a bigint primary key.
      {id, ""} when id in 1..9_223_372_036_854_775_807 -> {:ok, id}
      _ -> {:error, {:<%= singular %>, :not_found}}
    end
<% end %>  end
<% end %>end
