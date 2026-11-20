defmodule Brando.Images.Rerender do
  @moduledoc false
  # The entries that show an image render again when its processing changed
  # what a render reads from it. This is the one place that decides, for
  # every processing: an image size run (Utilities → Image sizes), the image
  # editor's crop, a focal point saved in the image drawer, or a new file.
  #
  # What a render reads from an image record is `render_inputs/1`: the
  # picture markup (`Brando.HTML.Images`) takes the path, the sizes and
  # formats, the dimensions, the CDN flag, the dominant color, the focal
  # point, the texts, the fetch priority and the config target (for the
  # config's srcset). Processing writes the sizes, formats, dimensions,
  # status and config fingerprint; when none of the inputs changed, the
  # stored renders are the same and nothing is queued. Adopting an image
  # (`Brando.Images.Adoption`) writes only its config fingerprint, which no
  # render reads, so it queues nothing either.
  #
  # The entries (`entries/1`) are queued once, in the bulk render lane
  # (`Brando.Content.RenderQueue.enqueue_map/2`):
  #
  #   * the image's owners (`Brando.Content.Usage.owners/2`): entries with
  #     it in a block's ref or variable, a page's variables, a gallery they
  #     show, or an asset field; only entries that have blocks to render
  #     count, so a global set or a user is left out, and none in the trash;
  #   * for an entry that holds it in an asset field (a project's cover), the
  #     entries that show that entry from elsewhere, as an entry's save finds
  #     them (`Brando.Worker.EntryCascade.showing_block_ids/2`): through its
  #     identifier, or a datasource of its schema. They are resolved here
  #     rather than by queueing a cascade, whose renders would not hold.
  #
  # Within a size run, the renders are held under the run's key and tagged
  # with the run (`Brando.Images.SizeRun`), so a page that shows many of the
  # run's images renders once, after the last of them.

  alias Brando.Content.BlockReferences
  alias Brando.Content.Identifier
  alias Brando.Content.RenderQueue
  alias Brando.Content.RenderRun
  alias Brando.Content.Usage
  alias Brando.Worker.EntryCascade

  import Ecto.Query, only: [from: 2]

  require Logger

  @render_inputs ~w(path sizes formats width height cdn dominant_color focal alt title credits fetchpriority config_target)a

  @doc "What a render reads from an image record."
  @spec render_inputs(map()) :: map()
  def render_inputs(image) do
    image
    |> Map.take(@render_inputs)
    |> Map.update(:focal, nil, &plain/1)
  end

  # An embedded focal point and the map it was cast from compare the same
  defp plain(%_{} = struct), do: struct |> Map.from_struct() |> Map.delete(:__meta__)
  defp plain(value), do: value

  @doc "Did processing change what a render reads from the image?"
  @spec changed?(map(), map()) :: boolean()
  def changed?(before, processed), do: render_inputs(before) != render_inputs(processed)

  @doc """
  Queues the renders of the entries that show `processed`, the image as
  processing left it, when a render reads anything from it that `before`
  did not have. Options:

    * `:hold` — the key the renders are held under
      (`RenderQueue.enqueue_map/2`);
    * `:run` — a run id the renders carry (`RenderRun.within_run/2`).

  Never raises: the image is processed whatever happens to its entries'
  renders, and a failure is logged.
  """
  @spec after_processing(map(), map(), keyword()) :: [{:ok, Oban.Job.t()}]
  def after_processing(before, processed, opts \\ []) do
    if changed?(before, processed), do: queue([processed.id], opts), else: []
  rescue
    error ->
      Logger.error("==> Image #{processed.id}: its entries were not queued to render: #{Exception.message(error)}")
      []
  end

  @doc "Queues the renders of the entries that show any of `image_ids` (see `after_processing/3`)."
  @spec queue([integer()], keyword()) :: [{:ok, Oban.Job.t()}]
  def queue(image_ids, opts \\ []) do
    case entries(image_ids) do
      entries when map_size(entries) == 0 ->
        []

      entries ->
        enqueue = fn -> RenderQueue.enqueue_map(entries, Keyword.take(opts, [:hold])) end
        if run = opts[:run], do: RenderRun.within_run(run, enqueue), else: enqueue.()
    end
  end

  @doc """
  The entries that show any of `image_ids`, as `%{schema => [entry_id]}`:
  its owners that have blocks to render, and the entries that show an owner
  holding it in an asset field.
  """
  @spec entries([integer()]) :: %{optional(module()) => [integer()]}
  def entries([]), do: %{}

  def entries(image_ids) do
    owners = :image |> Usage.owners(image_ids) |> Map.values() |> Enum.concat()

    showing =
      :image
      |> Usage.field_owners(image_ids)
      |> showing_block_ids()
      |> BlockReferences.reject_blocks_belonging_to_entry(nil)
      |> Enum.flat_map(fn {schema, ids} -> Enum.map(ids, &{schema, &1}) end)

    (owners ++ showing)
    |> Enum.uniq()
    |> Enum.filter(fn {schema, _id} -> renders?(schema) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {schema, ids} -> {schema, out_of_trash(schema, ids)} end)
    |> Enum.reject(fn {_schema, ids} -> ids == [] end)
    |> Map.new()
  end

  # `Usage` lists a page in the trash that holds the image in a page
  # variable: its render is not served, and is not queued
  defp out_of_trash(schema, ids) do
    if :deleted_at in schema.__schema__(:fields) do
      kept = MapSet.new(Brando.Repo.all(from(e in schema, where: e.id in ^ids and is_nil(e.deleted_at), select: e.id)))
      Enum.filter(ids, &MapSet.member?(kept, &1))
    else
      ids
    end
  end

  defp showing_block_ids([]), do: []

  defp showing_block_ids(field_owners) do
    identifiers = identifiers(field_owners)

    field_owners
    |> Enum.map(fn {schema, id} -> {schema, Map.get(identifiers, {schema, id})} end)
    |> Enum.uniq()
    |> Enum.flat_map(fn {schema, identifier_id} -> EntryCascade.showing_block_ids(schema, identifier_id) end)
    |> Enum.uniq()
  end

  # `%{{schema, entry_id} => identifier_id}`, one query per schema
  defp identifiers(entries) do
    entries
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {schema, ids} ->
      Brando.Repo.all(
        from(i in Identifier, where: i.schema == ^schema and i.entry_id in ^ids, select: {i.entry_id, i.id})
      )
      |> Enum.map(fn {entry_id, identifier_id} -> {{schema, entry_id}, identifier_id} end)
    end)
    |> Map.new()
  end

  # An entry with blocks has a stored render; a global set or a user has none
  defp renders?(schema) do
    Code.ensure_loaded?(schema) and function_exported?(schema, :__blocks_fields__, 0) and
      schema.__blocks_fields__() != []
  end
end
