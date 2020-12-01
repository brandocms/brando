defmodule Brando.Plug.HTML do
  @moduledoc """
  A plug with HTML oriented helpers
  """
  alias Brando.Pages.Page
  alias Brando.Utils
  alias Brando.JSONLD
  import Plug.Conn

  @type conn :: Plug.Conn.t()

  @doc """
  A plug for setting `body`'s `data-script` attribute to named section.

  Used for calling javascript setup(). Check the `data-script` attr
  in javascript.

  ## Usage

      import Brando.Plug.HTML
      plug :put_section, "users"
  """

  @spec put_section(conn, binary) :: conn
  def put_section(conn, name) do
    conn
    |> put_private(:brando_section_name, name)
    |> assign(:section, name)
  end

  @spec get_section(conn) :: binary
  def get_section(conn), do: conn.private.brando_section_name

  @doc """
  Add `classes` to body

  ## Usage

      import Brando.Plug.HTML
      plug :put_css_classes, "wrapper box"
  """
  @spec put_css_classes(conn, binary | [binary]) :: conn
  def put_css_classes(conn, classes) when is_binary(classes),
    do: put_private(conn, :brando_css_classes, classes)

  def put_css_classes(conn, classes) when is_list(classes),
    do: put_private(conn, :brando_css_classes, Enum.join(classes, " "))

  def put_css_classes(conn, _), do: conn

  @doc """
  Adds `title` to `conn`'s assigns as `page_title`
  """
  def put_title(conn, title), do: assign(conn, :page_title, title)

  @doc """
  Adds JSON-LD breadcrumbs to conn
  """
  def put_breadcrumbs(conn, %Page{is_homepage: true}) do
    breadcrumbs = [
      {Brando.config(:app_name), "/"}
    ]

    put_json_ld(conn, :breadcrumbs, breadcrumbs)
  end

  def put_breadcrumbs(conn, %Page{}) do
    breadcrumbs = [
      {Brando.config(:app_name), "/"}
    ]

    put_json_ld(conn, :breadcrumbs, breadcrumbs)
  end

  @doc """
  Adds JSON-LD to conn
  """
  def put_json_ld(conn, :breadcrumbs, breadcrumbs),
    do: assign(conn, :json_ld_breadcrumbs, breadcrumbs)

  def put_json_ld(conn, module, data, extra_fields \\ []) do
    extra_fields = JSONLD.Schema.convert_format(extra_fields)
    meta_meta = %{__meta__: %{current_url: Utils.current_url(conn)}}
    data_with_meta = Map.merge(data, meta_meta)
    assign(conn, :json_ld_entity, module.extract_json_ld(data_with_meta, extra_fields))
  end

  @doc """
  Put META data in conn
  """
  @spec put_meta(conn, key :: binary, data :: any) :: conn
  @spec put_meta(conn, module :: atom, data :: any) :: conn
  def put_meta(conn, module, data) when is_atom(module) do
    meta_meta = %{__meta__: %{current_url: Utils.current_url(conn)}}
    data_with_meta = Map.merge(data, meta_meta)
    extracted_meta = module.extract_meta(data_with_meta)
    merged_meta = Map.merge(conn.private[:brando_meta] || %{}, extracted_meta)
    put_private(conn, :brando_meta, merged_meta)
  end

  def put_meta(conn, key, data) when is_binary(key) do
    meta = conn.private[:brando_meta] || %{}
    put_private(conn, :brando_meta, Map.put(meta, key, data))
  end

  @doc """
  Add meta key if not found in conn
  """
  def put_meta_if_missing(conn, key, data) when is_binary(key) do
    meta = conn.private[:brando_meta] || %{}

    if Map.get(meta, key) do
      conn
    else
      put_private(conn, :brando_meta, Map.put(meta, key, data))
    end
  end
end
