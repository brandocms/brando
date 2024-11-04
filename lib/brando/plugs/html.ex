defmodule Brando.Plug.HTML do
  @moduledoc """
  A plug with HTML oriented helpers
  """
  require Logger
  import Plug.Conn
  alias Brando.Pages.Page
  alias Brando.Utils
  alias Brando.JSONLD

  @type conn :: Plug.Conn.t()

  @doc """
  A plug for setting `body`'s `data-script` attribute to named section.

  Used for calling javascript setup(). Check the `data-script` attr
  in javascript.

  ## Usage

      import Brando.Plug.HTML
      plug :put_section, "users"
  """

  @spec put_section(conn, atom | binary) :: conn
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
    meta_meta = %{
      __meta__: %{
        current_url: Utils.current_url(conn),
        language: Map.get(data, :language, conn.assigns.language)
      }
    }

    data_with_meta = Map.merge(data, meta_meta)
    assign(conn, :json_ld_entity, JSONLD.extract_json_ld(module, data_with_meta, extra_fields))
  end

  @doc """
  Put hreflang data in conn

  If you have a translatable entry:

      put_hreflang(conn, entry)

  If you want to supply your own alternates

      put_hreflang(conn, [en: "/en/something", no: "/no/something"])

  Or to run localized_path on all available languages:

      put_hreflang(conn, {:post_path, [conn, :list]})

  """
  def put_hreflang(conn, hreflangs) when is_list(hreflangs) do
    full_host_canonical =
      {conn.assigns.language, Brando.Utils.hostname(Path.join(["/" | conn.path_info]))}

    full_host_hreflangs = Enum.map(hreflangs, &Brando.Utils.hostname/1)
    put_private(conn, :brando_hreflangs, [full_host_canonical] ++ full_host_hreflangs)
  end

  def put_hreflang(conn, {fun, args}) do
    full_host_canonical =
      {conn.assigns.language, Brando.Utils.hostname(Path.join(["/" | conn.path_info]))}

    full_host_hreflangs =
      Enum.map(Brando.config(:languages), fn [value: lang_code, text: _] ->
        {String.to_atom(lang_code), Brando.I18n.Helpers.localized_path(lang_code, fun, args)}
      end)

    put_private(conn, :brando_hreflangs, [full_host_canonical] ++ full_host_hreflangs)
  end

  def put_hreflang(conn, %{alternate_entries: %Ecto.Association.NotLoaded{}} = entry) do
    Logger.error("""
    ==> put_hreflang: Missing preload for :alternate_entries

    Url....: #{Brando.Utils.hostname(Path.join(["/" | conn.path_info]))}
    Schema.: #{entry.__struct__}
    Id.....: ##{entry.id}

    """)

    conn
  end

  def put_hreflang(conn, %{alternate_entries: alternate_entries} = entry)
      when is_list(alternate_entries) do
    canonical = {entry.language, Brando.HTML.absolute_url(entry, :with_host)}

    hreflangs =
      Enum.reduce(entry.alternate_entries, [], fn
        %{status: :published} = alt, acc ->
          case Brando.HTML.absolute_url(alt) do
            nil ->
              log_no_valid_hreflang(alt)
              acc

            url ->
              acc ++ [{alt.language, Brando.Utils.hostname(url)}]
          end

        %{status: _}, acc ->
          acc

        alt, acc ->
          case Brando.HTML.absolute_url(alt) do
            nil ->
              log_no_valid_hreflang(alt)
              acc

            url ->
              acc ++ [{alt.language, Brando.Utils.hostname(url)}]
          end
      end)

    put_private(conn, :brando_hreflangs, [canonical] ++ hreflangs)
  end

  def put_hreflang(conn, _), do: conn

  defp log_no_valid_hreflang(alt) do
    Logger.error("""
    ==> put_hreflang: No valid url found for alternate entry.

    Schema.......: #{alt.__struct__}
    Id...........: ##{alt.id}
    URL template.:

    #{alt.__struct__.__absolute_url_template__}

    This usually happens when the alternate entry is missing a preload.
    For instance if you have an entry that requires a preloaded category
    to generate a correct url, you must preload this category with
    your alternate_entries:

        opts = %{
          matches: %{slug: slug, category: category},
          status: :published,
          preload: [:category, alternate_entries: [:category]]
        }

    """)
  end

  @doc """
  Put META data in conn
  """
  def put_meta(conn, module, data, opts \\ [])

  @spec put_meta(conn, module :: atom, data :: any) :: conn
  def put_meta(conn, module, data, _opts) when is_atom(module) do
    meta_meta = %{__meta__: %{current_url: Utils.current_url(conn)}}
    data_with_meta = Map.merge(data, meta_meta)
    extracted_meta = Brando.Blueprint.Meta.extract_meta(module, data_with_meta)
    merged_meta = (conn.private[:brando_meta] || []) ++ extracted_meta
    put_private(conn, :brando_meta, merged_meta)
  end

  def put_meta(conn, key, data, opts) when is_binary(key) do
    meta = conn.private[:brando_meta] || []

    meta =
      if Keyword.get(opts, :replace) do
        Enum.reject(meta, fn {k, _} -> k == key end)
      else
        meta
      end

    put_private(conn, :brando_meta, meta ++ [{key, data}])
  end

  @doc """
  Add meta key if not found in conn
  """
  def put_meta_if_missing(conn, key, data) when is_binary(key) do
    meta = conn.private[:brando_meta] || []

    if Enum.any?(meta, fn {k, _} -> k == key end) do
      conn
    else
      put_private(conn, :brando_meta, meta ++ [{key, data}])
    end
  end
end
