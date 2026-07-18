defmodule Brando.Blueprint.Snapshot do
  @moduledoc """
  Versioned Blueprint storage snapshots used by migration generation.

  Snapshot format 3 stores a normalized, storage-only schema, including the
  physical primary-key column. Older snapshots are upgraded in memory and
  replaced with format 3 on the next successful migration generation.
  """

  alias Brando.Blueprint.Migrations.Schema
  alias Brando.Blueprint.Snapshot
  alias Brando.Exception.BlueprintError

  @format_version 3
  @default_opts [snapshot_path: "priv/blueprints/snapshots"]

  defstruct format_version: @format_version,
            migrated_from_format: nil,
            rebaseline?: false,
            schema: nil,
            version: nil,
            updated_at: nil,
            # Legacy format 1 fields. Kept so old external terms can be decoded.
            attributes: nil,
            assets: nil,
            relations: nil,
            traits: nil

  @type t :: %__MODULE__{
          format_version: pos_integer(),
          migrated_from_format: non_neg_integer() | nil,
          rebaseline?: boolean(),
          schema: Schema.t(),
          version: non_neg_integer(),
          updated_at: DateTime.t()
        }

  @doc """
  Returns the current persisted Blueprint schema version.
  """
  @spec get_current_version(module()) :: non_neg_integer()
  def get_current_version(module) do
    if function_exported?(module, :__schema_version__, 0) do
      module.__schema_version__()
    else
      get_snapshot_version(module)
    end
  end

  @doc """
  Loads the latest snapshot, or `nil` when no snapshot exists.

  Corrupt or incompatible snapshots raise a `BlueprintError`; they are never
  silently treated as an empty migration history.
  """
  @spec get_latest_snapshot(module(), keyword()) :: t() | nil
  def get_latest_snapshot(module, opts \\ @default_opts) do
    case get_snapshot_version(module, opts) do
      0 -> nil
      version -> get_snapshot(module, version, opts)
    end
  end

  @doc """
  Loads a specific Blueprint snapshot version.
  """
  @spec get_snapshot(module(), non_neg_integer(), keyword()) :: t() | nil
  def get_snapshot(module, version, opts \\ @default_opts)

  def get_snapshot(_module, 0, _opts), do: nil

  def get_snapshot(module, version, opts) do
    filename = build_filename(module, version, opts)

    case File.read(filename) do
      {:ok, binary} -> decode_snapshot!(binary, filename, module, version)
      {:error, :enoent} -> nil
      {:error, reason} -> raise_snapshot_error!(filename, reason)
    end
  end

  @doc """
  Builds a snapshot for a module.

  Pass migration options to build the next path-relative version, or pass an
  explicit positive integer version when coordinating a migration write.
  """
  @spec build_snapshot(module(), keyword() | pos_integer()) :: t()
  def build_snapshot(module, opts_or_version \\ @default_opts)

  def build_snapshot(module, opts) when is_list(opts) do
    build_snapshot(module, get_snapshot_version(module, opts) + 1)
  end

  def build_snapshot(module, version) when is_integer(version) and version > 0 do
    %Snapshot{
      format_version: @format_version,
      schema: module |> Schema.build() |> Schema.persistable(),
      version: version,
      updated_at: DateTime.utc_now()
    }
  end

  @doc """
  Atomically stores a prepared snapshot and returns its filename.
  """
  @spec store_snapshot(t(), module(), keyword()) :: {:ok, String.t()}
  def store_snapshot(%Snapshot{} = snapshot, module, opts) do
    validate_snapshot!(snapshot, snapshot.version, inspect(module))
    filename = build_filename(module, snapshot.version, opts)
    File.mkdir_p!(Path.dirname(filename))
    atomic_write!(filename, :erlang.term_to_binary(snapshot, compressed: 6))
    {:ok, filename}
  end

  @doc """
  Builds and stores the next snapshot.

  Kept for callers that used the original `store_snapshot/2` API.
  """
  @spec store_snapshot(module(), keyword()) :: {:ok, String.t()}
  def store_snapshot(module, opts \\ @default_opts) when is_atom(module) do
    module
    |> build_snapshot(opts)
    |> store_snapshot(module, opts)
  end

  @doc """
  Serializes migration and snapshot generation for one Blueprint path.
  """
  @spec with_lock(module(), keyword(), (-> term())) :: term()
  def with_lock(module, opts, fun) when is_function(fun, 0) do
    resource = {__MODULE__, Path.expand(build_path(module, opts))}
    :global.trans({resource, self()}, fun)
  end

  @doc """
  Returns the highest numeric snapshot version stored for a Blueprint.
  """
  @spec get_snapshot_version(module(), keyword()) :: non_neg_integer()
  def get_snapshot_version(module, opts \\ @default_opts) do
    module
    |> build_path(opts)
    |> Path.join("*.snapshot")
    |> Path.wildcard()
    |> Enum.map(&snapshot_version!/1)
    |> Enum.max(fn -> 0 end)
  end

  @doc """
  Returns the configured snapshot directory for a Blueprint.
  """
  @spec build_path(module(), keyword()) :: String.t()
  def build_path(module, opts) do
    snapshot_directory =
      Enum.map_join(
        [module.__naming__().application, module.__naming__().domain, module.__naming__().schema],
        "_",
        &String.downcase/1
      )

    case Keyword.get(opts, :snapshot_path) do
      nil ->
        app_name = module.__naming__().application |> String.downcase() |> String.to_atom()

        priv_dir =
          case :code.priv_dir(app_name) do
            {:error, :bad_name} -> "priv"
            priv_dir -> to_string(priv_dir)
          end

        Path.join([priv_dir, "blueprints/snapshots", snapshot_directory])

      custom_path ->
        Path.join([custom_path, snapshot_directory])
    end
  end

  defp build_filename(module, version, opts) do
    filename = "#{String.pad_leading(to_string(version), 3, "0")}.snapshot"
    Path.join(build_path(module, opts), filename)
  end

  defp decode_snapshot!(binary, filename, module, expected_version) do
    snapshot =
      binary
      # Legacy snapshots contain declaration and field-name atoms that may no
      # longer exist in the current code. `binary_to_term(..., [:safe])` cannot
      # decode those atoms, so use Plug's non-executable decoder for this
      # source-controlled migration input and validate the complete shape below.
      |> Plug.Crypto.non_executable_binary_to_term()
      |> migrate_snapshot(module)

    snapshot
    |> validate_snapshot!(expected_version, filename)
    |> canonicalize_database_identifiers()
    |> validate_snapshot!(expected_version, filename)
  rescue
    error in [ArgumentError, ErlangError, KeyError] ->
      reraise BlueprintError.exception(
                message: """
                Could not decode Blueprint snapshot #{filename}.

                The snapshot is corrupt or incompatible with this Brando version.
                Restore it from version control or deliberately re-baseline it before
                generating another migration.

                Decoder error: #{Exception.message(error)}
                """
              ),
              __STACKTRACE__
  end

  defp canonicalize_database_identifiers(snapshot) do
    %{snapshot | schema: Schema.canonicalize_database_identifiers(snapshot.schema)}
  end

  defp migrate_snapshot(%{__struct__: Snapshot} = snapshot, module) do
    case {Map.get(snapshot, :format_version), Map.get(snapshot, :schema)} do
      {@format_version, schema} when is_map(schema) ->
        struct(Snapshot, Map.from_struct(snapshot))

      {2, schema} when is_map(schema) ->
        %Snapshot{
          struct(Snapshot, Map.from_struct(snapshot))
          | format_version: @format_version,
            migrated_from_format: 2,
            schema: Schema.from_v2(schema)
        }

      {legacy_version, _legacy_schema} when legacy_version in [nil, 1] ->
        validate_legacy_snapshot!(snapshot)

        %Snapshot{
          format_version: @format_version,
          migrated_from_format: legacy_version || 1,
          schema: Schema.from_legacy(module, snapshot),
          version: Map.get(snapshot, :version, 0),
          updated_at: Map.get(snapshot, :updated_at)
        }

      {@format_version, invalid_schema} ->
        raise BlueprintError,
          message: "Blueprint snapshot format #{@format_version} has an invalid schema: #{inspect(invalid_schema)}"

      {unsupported_format, _schema} ->
        raise BlueprintError,
          message: "Unsupported Blueprint snapshot format: #{inspect(unsupported_format)}"
    end
  end

  defp migrate_snapshot(other, _module) do
    raise BlueprintError,
      message: "Expected a Brando.Blueprint.Snapshot, got: #{inspect(other, limit: 5)}"
  end

  defp validate_snapshot!(%Snapshot{} = snapshot, expected_version, source) do
    with :ok <- validate_snapshot_version(snapshot.version, expected_version),
         :ok <- validate_snapshot_metadata(snapshot),
         :ok <- Schema.validate(snapshot.schema) do
      snapshot
    else
      {:error, reason} ->
        raise BlueprintError,
          message: "Invalid Blueprint snapshot #{source}: #{inspect(reason, limit: 20)}"
    end
  end

  defp validate_snapshot_version(version, expected_version)
       when is_integer(version) and version > 0 and version == expected_version,
       do: :ok

  defp validate_snapshot_version(version, expected_version),
    do: {:error, {:snapshot_version_mismatch, expected_version, version}}

  defp validate_snapshot_metadata(snapshot) do
    cond do
      snapshot.format_version != @format_version ->
        {:error, {:unsupported_format, snapshot.format_version}}

      not is_boolean(snapshot.rebaseline?) ->
        {:error, {:invalid_rebaseline, snapshot.rebaseline?}}

      not (is_nil(snapshot.migrated_from_format) or
               (is_integer(snapshot.migrated_from_format) and snapshot.migrated_from_format > 0)) ->
        {:error, {:invalid_migrated_from_format, snapshot.migrated_from_format}}

      not match?(%DateTime{}, snapshot.updated_at) ->
        {:error, {:invalid_updated_at, snapshot.updated_at}}

      true ->
        :ok
    end
  end

  defp validate_legacy_snapshot!(snapshot) do
    invalid_field =
      Enum.find([:attributes, :assets, :relations, :traits], fn field ->
        not is_list(Map.get(snapshot, field))
      end)

    if invalid_field do
      raise BlueprintError,
        message: "Invalid legacy Blueprint snapshot field: #{inspect(invalid_field)}"
    end
  end

  defp snapshot_version!(filename) do
    filename
    |> Path.basename(".snapshot")
    |> Integer.parse()
    |> case do
      {version, ""} -> version
      _ -> raise_snapshot_error!(filename, :invalid_version)
    end
  end

  defp atomic_write!(filename, contents) do
    temporary = "#{filename}.tmp.#{System.unique_integer([:positive, :monotonic])}"

    try do
      File.write!(temporary, contents, [:binary, :sync])
      File.rename!(temporary, filename)
    after
      File.rm(temporary)
    end
  end

  defp raise_snapshot_error!(filename, reason) do
    raise BlueprintError,
      message: "Could not read Blueprint snapshot #{filename}: #{inspect(reason)}"
  end
end
