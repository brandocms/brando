defmodule Brando.Blueprint.Snapshot do
  @moduledoc """
  Should have

    - traits
    - attributes
    - relations

  - Check migrations directory for `*_application_domain_schema_<padded_version>`
  - If not found, create a migration
  """

  alias Brando.Blueprint.Snapshot

  defstruct attributes: nil,
            relations: nil,
            traits: nil,
            version: nil,
            updated_at: nil

  @type t :: %__MODULE__{}
  @type snapshot :: __MODULE__.t()

  @default_opts [snapshot_path: "priv/blueprints/snapshots"]

  @spec get_latest_snapshot(module) :: snapshot | nil
  def get_latest_snapshot(module, opts \\ @default_opts) do
    version = get_snapshot_version(module, opts)
    get_snapshot(module, version, opts)
  end

  @spec get_snapshot(module, integer()) :: snapshot | nil
  def get_snapshot(module, version, opts \\ @default_opts) do
    module
    |> build_filename(version, opts)
    |> File.read!()
    |> :erlang.binary_to_term()
  rescue
    _ -> nil
  end

  @spec store_snapshot(module) :: :ok | no_return
  def store_snapshot(module, opts \\ @default_opts) do
    snapshot = build_snapshot(module)
    filename = build_filename(module, snapshot.version, opts)
    File.write!(filename, :erlang.term_to_binary(snapshot))
  end

  @spec build_snapshot(module) :: snapshot
  def build_snapshot(module) do
    blueprint = module.__blueprint__()

    %Snapshot{
      traits: blueprint.traits,
      attributes: blueprint.attributes,
      relations: blueprint.relations,
      updated_at: DateTime.utc_now(),
      version: get_next_snapshot_version(module)
    }
  end

  defp build_path(module, opts) do
    root_path = Keyword.get(opts, :snapshot_path)

    snapshot_path =
      [
        module.__naming__().application,
        module.__naming__().domain,
        module.__naming__().schema
      ]
      |> Enum.map(&String.downcase/1)
      |> Enum.join("_")

    Path.join(root_path, snapshot_path)
  end

  defp build_filename(module, version, opts) do
    snapshot_path = build_path(module, opts)
    File.mkdir_p!(snapshot_path)
    filename = "#{String.pad_leading(to_string(version), 3, "0")}.snapshot"
    Path.join([snapshot_path, filename])
  end

  defp get_snapshot_version(module, opts \\ @default_opts) do
    # get sequence
    snapshot_path = build_path(module, opts)
    File.mkdir_p!(snapshot_path)

    case Path.wildcard(Path.join(snapshot_path, "*.snapshot")) do
      [] ->
        0

      snapshot_files ->
        snapshot_files
        |> List.last()
        |> Path.basename(".snapshot")
        |> String.to_integer()
    end
  end

  defp get_next_snapshot_version(module) do
    get_snapshot_version(module) + 1
  end

end
