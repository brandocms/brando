defmodule Brando.Blueprint.Snapshot do
  @moduledoc """
  Should have

    - traits
    - attributes
    - assets
    - relations

  - Check migrations directory for `*_application_domain_schema_<padded_version>`
  - If not found, create a migration
  """

  alias Brando.Blueprint.Snapshot

  defstruct attributes: nil,
            assets: nil,
            relations: nil,
            traits: nil,
            version: nil,
            updated_at: nil

  @type t :: %__MODULE__{}
  @type snapshot :: __MODULE__.t()

  @default_opts [snapshot_path: "priv/blueprints/snapshots"]

  @spec get_current_version(module) :: integer
  def get_current_version(module) do
    # First check if the module has a @schema_version attribute (for Brando modules)
    if function_exported?(module, :__schema_version__, 0) do
      module.__schema_version__()
    else
      # Fall back to snapshot file system for app modules
      get_snapshot_version(module)
    end
  end

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
    traits = module.__traits__()
    assets = Brando.Blueprint.Assets.__assets__(module)
    attributes = Brando.Blueprint.Attributes.__attributes__(module)
    relations = Brando.Blueprint.Relations.__relations__(module)

    %Snapshot{
      traits: traits,
      assets: assets,
      attributes: attributes,
      relations: relations,
      updated_at: DateTime.utc_now(),
      version: get_next_snapshot_version(module)
    }
  end

  defp build_path(module, opts) do
    # Get the application name from the module
    app_name = module.__naming__().application |> String.downcase() |> String.to_atom()

    # Get the priv dir for that specific application
    priv_dir =
      case :code.priv_dir(app_name) do
        {:error, :bad_name} ->
          # Fallback to default path for development or if app not found
          Keyword.get(opts, :snapshot_path, "priv")

        priv_dir_charlist ->
          priv_dir_charlist |> to_string()
      end

    snapshot_path =
      Enum.map_join(
        [module.__naming__().application, module.__naming__().domain, module.__naming__().schema],
        "_",
        &String.downcase/1
      )

    Path.join([priv_dir, "blueprints/snapshots", snapshot_path])
  end

  defp build_filename(module, version, opts) do
    snapshot_path = build_path(module, opts)
    File.mkdir_p!(snapshot_path)
    filename = "#{String.pad_leading(to_string(version), 3, "0")}.snapshot"
    Path.join([snapshot_path, filename])
  end

  defp get_snapshot_version(module, opts \\ @default_opts) do
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
