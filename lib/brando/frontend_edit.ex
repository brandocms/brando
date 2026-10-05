defmodule Brando.FrontendEdit do
  @moduledoc """
  Frontend edit mode: an authorized admin clicks a block on the published
  site and edits it in a sidebar, with the page updating as they type.

  ## Setup

  Frontend edit is off until it is switched on in config:

      config :brando, Brando.FrontendEdit, enabled: true

  and the application's browser pipeline runs the plug, after the session is
  fetched and the tenant is resolved:

      pipeline :browser do
        plug :fetch_session
        # …
        plug Brando.Plug.Tenant
        plug Brando.Plug.FrontendEdit
      end

  Signed-in admins then get an "Edit page" button on frontend pages. Visitors
  get nothing: no markup, script or cookie is added to their responses.

  ## How a page becomes editable

  Published pages print the HTML stored at save (`rendered_<field>`), which
  has no block markers. In edit mode the request process is flagged
  (`active?/0`), and every place Brando hands out stored block HTML renders
  it again with markers instead (`rendered_html/2`):

    * single-entry queries from generated contexts (`get_page/1`,
      `get_project/1`, …) return entries whose `rendered_<field>` values are
      annotated, so templates printing the field directly are covered;
    * `Brando.HTML.render_blocks/1`, the `Phoenix.HTML.Safe` implementations
      of pages and fragments, and `Brando.Pages.render_fragment/1,2,3` and
      `fetch_fragment/2`;
    * fragments embedded in blocks, which carry their own markers, so their
      blocks are edited on the fragment.

  Each field is wrapped in `<!-- [+:F<key>] -->` … `<!-- [-:F<key>] -->`
  (`key` is `Schema:id:field`), and each block in the existing
  `[+:B<uid>]` markers live preview uses. The plug reads them back from the
  response to build the manifest the frontend script works from
  (`Brando.FrontendEdit.Manifest`).

  Pages rendered by a connected LiveView are not covered: the flag lives in
  the request process, which the LiveView socket does not share.
  """

  require Logger

  alias Brando.Blueprint.EntryQuery
  alias Brando.Villain

  @active_key {__MODULE__, :active}
  @loading_key {__MODULE__, :loading}
  @memo_key {__MODULE__, :memo}
  @stack_key {__MODULE__, :stack}
  @annotate_key {__MODULE__, :annotate}

  @cookie "_brando_frontend_edit"

  @doc "Whether frontend edit is switched on in config."
  @spec enabled?() :: boolean()
  def enabled? do
    case Brando.config(__MODULE__) do
      opts when is_list(opts) -> Keyword.get(opts, :enabled, false) == true
      _ -> false
    end
  end

  @doc "The cookie an admin's browser sets to say edit mode is on."
  def cookie, do: @cookie

  @doc "Whether the current process renders a page in edit mode."
  @spec active?() :: boolean()
  def active?, do: Process.get(@active_key) == true

  @doc """
  Switches edit mode on for the current process. The frontend edit plug calls it
  for an admin request; pair it with `deactivate/0`.
  """
  def activate do
    Process.put(@active_key, true)
    :ok
  end

  @doc "Switches edit mode off and clears the process's render memo and field stack."
  def deactivate do
    Process.delete(@active_key)
    Process.delete(@memo_key)
    Process.delete(@stack_key)
    :ok
  end

  @doc """
  Whether markup rendered now should carry frontend edit markers.

  Inside a block render this follows the render's `annotate_blocks` option
  (`annotation_scope/2`): edit-mode and preview renders carry markers, the
  stored HTML never does. Outside one, in the site's own templates, it
  follows edit mode.
  """
  @spec annotating?() :: boolean()
  def annotating? do
    case Process.get(@annotate_key) do
      nil -> active?()
      annotate? -> annotate?
    end
  end

  @doc """
  Runs `fun` with `annotating?/0` fixed to `annotate?`, restoring the previous
  value afterwards. Villain wraps each render in this, so the editable tags and
  components in module templates know whether to add markers.
  """
  def annotation_scope(annotate?, fun) do
    previous = Process.get(@annotate_key)
    Process.put(@annotate_key, annotate? == true)

    try do
      fun.()
    after
      if is_nil(previous), do: Process.delete(@annotate_key), else: Process.put(@annotate_key, previous)
    end
  end

  @doc """
  Runs `fun` with edit mode active in the current process. Used by tests and
  by renders outside a request.
  """
  def with_active(fun) do
    previous = Process.get(@active_key)
    activate()

    try do
      fun.()
    after
      if previous, do: Process.put(@active_key, previous), else: deactivate()
    end
  end

  @doc """
  The block HTML to print for `entry`'s block `field`.

  Outside edit mode this is the stored `rendered_<field>`. In edit mode the
  field is rendered from its blocks with block markers, wrapped in field
  markers, and memoized for the rest of the request. A render that fails
  falls back to the stored HTML, so a broken block cannot take the page down.
  """
  @spec rendered_html(map(), atom() | binary()) :: binary() | nil
  def rendered_html(%{__struct__: schema, id: id} = entry, field) when not is_nil(id) do
    stored = Map.get(entry, :"rendered_#{field}")

    if active?() and blocks_schema?(schema) and block_field?(schema, field) do
      memo_rendered_html(schema, id, field, stored)
    else
      stored
    end
  end

  def rendered_html(entry, field) when is_map(entry), do: Map.get(entry, :"rendered_#{field}")
  def rendered_html(_, _), do: nil

  defp memo_rendered_html(schema, id, field, stored) do
    key = field_key(schema, id, field)

    if key in Process.get(@stack_key, []) do
      stored
    else
      memo(key, fn -> render_annotated(schema, id, field, stored) end)
    end
  end

  @doc """
  Replaces every stored block field on `entry` with its edit-mode rendering.
  Called on single-entry query results; a no-op outside edit mode.
  """
  def annotate_entry(%{__struct__: schema} = entry) do
    if active?() and not loading?() and blocks_schema?(schema) and Map.get(entry, :id) do
      Enum.reduce(schema.__blocks_fields__(), entry, fn %{name: name}, acc -> annotate_field(acc, name) end)
    else
      entry
    end
  end

  def annotate_entry(entry), do: entry

  defp annotate_field(entry, name) do
    rendered_field = :"rendered_#{name}"

    if Map.has_key?(entry, rendered_field),
      do: Map.put(entry, rendered_field, rendered_html(entry, name)),
      else: entry
  end

  @doc """
  Annotates the entry in a single-entry query result, passing other results through.

  Revisions are left alone: they show content that is not what the blocks hold now.
  """
  def annotate_query_result({:ok, entry}, args) when is_map(args) do
    if Map.has_key?(args, :revision), do: {:ok, entry}, else: {:ok, annotate_entry(entry)}
  end

  def annotate_query_result(result, _args), do: result

  @doc """
  Whether a revision of the entry is scheduled to be published. Publishing it
  replaces the entry's content, including edits made after it was scheduled.
  """
  def scheduled_revision?(schema, id) do
    import Ecto.Query, only: [from: 2]

    from(r in Brando.Revisions.Revision,
      where: r.entry_type == ^to_string(schema) and r.entry_id == ^id and r.scheduled == true,
      select: count()
    )
    |> Brando.Repo.one()
    |> Kernel.>(0)
  end

  @doc "The key a field's markers carry: `Schema:id:field`."
  def field_key(schema, id, field), do: "#{inspect(schema)}:#{id}:#{field}"

  @doc """
  Resolves a field key back to `{schema, id, field}`. Only schemas with that
  block field resolve, so a key from the page cannot name arbitrary modules.
  """
  @spec parse_field_key(binary()) :: {:ok, {module(), integer(), atom()}} | :error
  def parse_field_key(key) when is_binary(key) do
    with [schema_name, id, field] <- String.split(key, ":"),
         {id, ""} <- Integer.parse(id),
         {:ok, schema} <- existing_module(schema_name),
         true <- blocks_schema?(schema),
         %{name: field} <- Enum.find(schema.__blocks_fields__(), &(to_string(&1.name) == field)) do
      {:ok, {schema, id, field}}
    else
      _ -> :error
    end
  end

  def parse_field_key(_), do: :error

  @doc "Whether `schema` is a Blueprint with block fields."
  def blocks_schema?(schema) when is_atom(schema) do
    Code.ensure_loaded?(schema) and function_exported?(schema, :has_trait, 1) and
      function_exported?(schema, :__blocks_fields__, 0) and schema.has_trait(Brando.Trait.Blocks)
  end

  def blocks_schema?(_), do: false

  defp block_field?(schema, field) do
    field = to_string(field)
    Enum.any?(schema.__blocks_fields__(), &(to_string(&1.name) == field))
  end

  defp existing_module(name) do
    module = String.to_existing_atom("Elixir." <> name)
    if Code.ensure_loaded?(module), do: {:ok, module}, else: :error
  rescue
    ArgumentError -> :error
  end

  defp loading?, do: Process.get(@loading_key) == true

  defp memo(key, fun) do
    memo = Process.get(@memo_key, %{})

    case Map.fetch(memo, key) do
      {:ok, html} ->
        html

      :error ->
        html = fun.()
        Process.put(@memo_key, Map.put(Process.get(@memo_key, %{}), key, html))
        html
    end
  end

  # The stored HTML is rendered from the same entry by `Blocks.render_entry/2`;
  # this is that render with markers, so the page looks the same in edit mode.
  defp render_annotated(schema, id, field, stored) do
    key = field_key(schema, id, field)
    Process.put(@stack_key, [key | Process.get(@stack_key, [])])

    try do
      case load(schema, id) do
        {:ok, entry} ->
          html =
            entry
            |> Map.get(:"entry_#{field}")
            |> Villain.parse(entry, annotate_blocks: true)
            |> IO.iodata_to_binary()

          wrap_field(html, key)

        {:error, _} ->
          stored
      end
    rescue
      error ->
        Logger.error("""
        ==> FrontendEdit: could not render #{key} for edit mode, showing the stored HTML.
        #{Exception.format(:error, error, __STACKTRACE__)}
        """)

        stored
    after
      Process.put(@stack_key, tl(Process.get(@stack_key, [key])))
    end
  end

  defp load(schema, id) do
    previous = Process.get(@loading_key)
    Process.put(@loading_key, true)

    try do
      EntryQuery.get(schema, id)
    after
      if previous, do: Process.put(@loading_key, previous), else: Process.delete(@loading_key)
    end
  end

  defp wrap_field(html, key),
    do: ["<!-- [+:F<", key, ">] -->", html, "<!-- [-:F<", key, ">] -->"] |> IO.iodata_to_binary()
end
