defmodule Brando.FrontendEdit.Manifest do
  @moduledoc """
  What the frontend script needs to know about an edit-mode page, built from
  the markers in its HTML.

      %{
        owners: %{"Brando.Pages.Page:12:blocks" => %{label: "About", kind: "Page", editable: true, ...}},
        blocks: %{"uid" => %{target: "uid", owner: "Brando.Pages.Page:12:blocks", label: "Text"}},
        fields: %{"Brando.Pages.Page:12:title" => %{label: "Title", entry: "About", editable: true, ...}}
      }

  `blocks` maps every marked block to the block a click on it opens (see
  `Brando.FrontendEdit.Targets`). Blocks whose owner the admin may not edit
  are listed with `editable: false` on their owner, so the page can say so
  instead of ignoring the click.
  """

  import Ecto.Query

  alias Brando.Authorization.Boundary
  alias Brando.FrontendEdit
  alias Brando.FrontendEdit.Fields
  alias Brando.FrontendEdit.Targets
  alias Brando.Type.I18nString

  @field_marker ~r/<!-- \[\+:F<([^>]+)>\] -->/
  @block_marker ~r/<!-- \[\+:B<([^>]+)>\] -->/
  @entry_field_marker ~r/<!-- \[\+:[EW]<([^>]+)>\] -->/

  @doc "The field keys marked in `html`, in order of appearance."
  def field_keys(html), do: @field_marker |> Regex.scan(html, capture: :all_but_first) |> List.flatten() |> Enum.uniq()

  @doc "The entry field keys marked in `html` (`editable_field`, `editable`), in order."
  def entry_field_keys(html),
    do: @entry_field_marker |> Regex.scan(html, capture: :all_but_first) |> List.flatten() |> Enum.uniq()

  @doc "The block uids marked in `html`, in order of appearance."
  def block_uids(html), do: @block_marker |> Regex.scan(html, capture: :all_but_first) |> List.flatten() |> Enum.uniq()

  @doc "Builds the manifest for `html` as seen by `user`."
  @spec build(binary(), map()) :: map()
  def build(html, user) do
    owners =
      html
      |> field_keys()
      |> Enum.flat_map(fn key ->
        case FrontendEdit.parse_field_key(key) do
          {:ok, owner} -> [{key, owner}]
          :error -> []
        end
      end)

    roots = root_owners(owners)
    chains = html |> block_uids() |> Targets.chains()

    blocks =
      Enum.flat_map(chains, fn {uid, chain} ->
        root = Targets.root(chain)

        case Map.fetch(roots, root.id) do
          {:ok, key} -> [{uid, %{target: Targets.target(chain).uid, owner: key}}]
          :error -> []
        end
      end)
      |> Map.new()

    targets = chains |> Map.values() |> Enum.map(&Targets.target/1) |> Map.new(&{&1.uid, &1})
    labels = labels(Map.values(targets))

    blocks =
      Map.new(blocks, fn {uid, block} -> {uid, Map.put(block, :label, Map.get(labels, block.target))} end)

    %{
      owners: Map.new(owners, fn {key, owner} -> {key, describe_owner(owner, user)} end),
      blocks: blocks,
      fields: entry_fields(html, user)
    }
  end

  # Entry fields marked by `editable_field`/`editable`: what the field is
  # called, whose it is, and whether `user` may edit it here.
  defp entry_fields(html, user) do
    html
    |> entry_field_keys()
    |> Enum.flat_map(fn key ->
      case Fields.parse_key(key) do
        {:ok, {schema, id, field} = owner} ->
          entry = load_entry(schema, id)

          [
            {key,
             %{
               label: Fields.label(schema, field),
               kind: Brando.Blueprint.get_singular(schema),
               entry: entry && title(schema, entry),
               editable: not is_nil(entry) and editable?(owner, user),
               shared: schema == Brando.Pages.Fragment
             }}
          ]

        :error ->
          []
      end
    end)
    |> Map.new()
  end

  # root block id => field key, read from each owner's join table.
  defp root_owners(owners) do
    Enum.reduce(owners, %{}, fn {key, {schema, id, field}}, acc ->
      join_schema = Module.concat([schema, field |> to_string() |> Macro.camelize()])

      from(join in join_schema, where: join.entry_id == ^id, select: join.block_id)
      |> Brando.Repo.all()
      |> Enum.reduce(acc, &Map.put_new(&2, &1, key))
    end)
  end

  @doc false
  def describe_owner({schema, id, field}, user) do
    entry = load_entry(schema, id)

    %{
      kind: Brando.Blueprint.get_singular(schema),
      label: entry && title(schema, entry),
      field: to_string(field),
      editable: not is_nil(entry) and editable?({schema, id, field}, user),
      shared: schema == Brando.Pages.Fragment,
      usage: if(schema == Brando.Pages.Fragment, do: fragment_usage(id), else: nil)
    }
  end

  @doc """
  Whether `user` may edit the entry's block field from the frontend: the
  schema has an admin form showing that field, and the user may update the
  entry.
  """
  def editable?({schema, id, field}, user) do
    function_exported?(schema, :__admin_route__, 2) and form_field?(schema, field) and
      Boundary.authorize_record(user, :update, schema, id) == :ok
  end

  # A block field, or an input, on the schema's default admin form.
  defp form_field?(schema, field) do
    case function_exported?(schema, :__form__, 1) && schema.__form__(:default) do
      %{blocks: blocks} -> Enum.any?(blocks, &(&1.name == field)) or not is_nil(Fields.input(schema, field))
      _ -> false
    end
  end

  @doc "How many entries embed the fragment `id` in a block."
  defdelegate fragment_usage(id), to: Targets

  @doc "The entry's title as the admin shows it, or nil."
  def title(schema, entry) do
    if function_exported?(schema, :__identifier__, 2) do
      case schema.__identifier__(entry, []) do
        %{title: title} when is_binary(title) and title != "" -> title
        _ -> fallback_title(entry)
      end
    else
      fallback_title(entry)
    end
  rescue
    _ -> fallback_title(entry)
  end

  defp fallback_title(entry), do: Map.get(entry, :title) || Map.get(entry, :name) || Map.get(entry, :key)

  defp load_entry(schema, id), do: Brando.Repo.get(schema, id)

  @doc """
  Display names for target blocks: the module's name, the container's, or
  the embedded fragment's title.
  """
  def labels(blocks) do
    module_refs =
      for %{type: :module, module_id: id} = block <- blocks, id, uniq: true, do: {id, block.module_origin || :local}

    container_ids = for %{type: :container, container_id: id} <- blocks, id, uniq: true, do: id
    fragment_ids = for %{type: :fragment, fragment_id: id} <- blocks, id, uniq: true, do: id

    # Through the render source cache, which also resolves shared-library modules.
    modules = Map.new(module_refs, &{&1, module_label(&1)})

    containers = names(Brando.Content.Container, container_ids, & &1.name)
    fragments = names(Brando.Pages.Fragment, fragment_ids, &(&1.title || &1.key))

    Map.new(blocks, &{&1.uid, block_label(&1, modules, containers, fragments)})
  end

  defp module_label({id, origin}) do
    with %{name: name} <- Brando.Content.fetch_module(id, origin), do: I18nString.localized(name)
  end

  defp block_label(block, modules, containers, fragments) do
    case block.type do
      :module -> Map.get(modules, {block.module_id, block.module_origin || :local})
      :container -> Map.get(containers, block.container_id)
      :fragment -> Map.get(fragments, block.fragment_id)
      _ -> nil
    end
  end

  defp names(_schema, [], _fun), do: %{}

  defp names(schema, ids, fun) do
    from(record in schema, where: record.id in ^ids)
    |> Brando.Repo.all()
    |> Map.new(&{&1.id, fun.(&1)})
  end
end
