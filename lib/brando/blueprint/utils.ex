defmodule Brando.Blueprint.Utils do
  @moduledoc """
  Stable helper surface imported while Blueprint schemas compile.

  Ecto conversion stays here to avoid adding dependencies to every generated
  schema. Runtime value resolution and form error translation are delegated to
  focused modules that do not pull their dependencies into schema compilation.
  """

  @strip_ecto_opts [:cast, :module, :required, :unique, :constraints, :sort_param, :drop_param, :rename_from]
  @strip_embeds_opts [:cast, :module, :unique, :constraints]
  @strip_changeset_opts [:cast, :module]
  @status_type Module.concat(["Brando", "Type", "Status"])
  @file_type Module.concat(["Brando", "Type", "File"])
  @image_type Module.concat(["Brando", "Type", "Image"])
  @video_type Module.concat(["Brando", "Type", "Video"])
  @i18n_string_type Module.concat(["Brando", "Type", "I18nString"])

  @doc """
  Maps a Blueprint attribute type to its Ecto schema type.
  """
  @spec to_ecto_type(term()) :: term()
  def to_ecto_type(:text), do: :string
  def to_ecto_type(:status), do: @status_type
  def to_ecto_type(:file), do: @file_type
  def to_ecto_type(:image), do: @image_type
  def to_ecto_type(:language), do: Ecto.Enum
  def to_ecto_type(:enum), do: Ecto.Enum
  def to_ecto_type(:video), do: @video_type
  def to_ecto_type(:i18n_string), do: @i18n_string_type
  def to_ecto_type(:slug), do: :string
  def to_ecto_type(:datetime), do: :utc_datetime

  def to_ecto_type(:villain) do
    IO.puts(":villain type is deprecated. Please move to :blocks")
    :map
  end

  def to_ecto_type(type), do: type

  @doc """
  Removes Blueprint-only metadata and returns options accepted by Ecto schema macros.
  """
  @spec to_ecto_opts(term(), map()) :: keyword()
  def to_ecto_opts(:language, opts), do: Map.to_list(opts)

  def to_ecto_opts(:belongs_to, opts),
    do: opts |> Map.drop(@strip_ecto_opts ++ [:on_delete]) |> Map.to_list()

  def to_ecto_opts(:has_one, opts), do: opts |> Map.drop(@strip_ecto_opts) |> Map.to_list()
  def to_ecto_opts(:many_to_many, opts), do: opts |> Map.drop(@strip_ecto_opts) |> Map.to_list()
  def to_ecto_opts(:has_many, opts), do: opts |> Map.drop(@strip_ecto_opts) |> Map.to_list()

  def to_ecto_opts(:embeds_one, opts) do
    opts
    |> Map.put_new(:on_replace, :update)
    |> Map.drop(@strip_ecto_opts)
    |> Map.to_list()
  end

  def to_ecto_opts(:embeds_many, opts) do
    opts
    |> Map.put_new(:on_replace, :delete)
    |> Map.drop(@strip_ecto_opts)
    |> Map.to_list()
  end

  def to_ecto_opts(PolymorphicEmbed, opts) do
    opts
    |> Map.put(:array?, false)
    |> Map.put(:default, nil)
    |> Map.drop(@strip_ecto_opts)
    |> Map.to_list()
  end

  def to_ecto_opts({:array, PolymorphicEmbed}, opts) do
    opts
    |> Map.put(:array?, true)
    |> Map.put(:default, [])
    |> Map.drop(@strip_ecto_opts)
    |> Map.to_list()
  end

  def to_ecto_opts(_type, opts), do: opts |> Map.drop(@strip_ecto_opts) |> Map.to_list()

  @doc """
  Removes Blueprint-only metadata and returns options accepted by Ecto cast helpers.
  """
  @spec to_changeset_opts(term(), map()) :: keyword()
  def to_changeset_opts(:has_one, opts), do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:belongs_to, opts),
    do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:many_to_many, opts),
    do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:has_many, opts), do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()
  def to_changeset_opts(:embeds_one, opts), do: opts |> Map.drop(@strip_embeds_opts) |> Map.to_list()
  def to_changeset_opts(:embeds_many, opts), do: opts |> Map.drop(@strip_embeds_opts) |> Map.to_list()
  def to_changeset_opts(_type, opts), do: Map.to_list(opts)

  @doc """
  Translates changeset error keys using their configured Blueprint form labels.
  """
  def translate_error_keys(error_keys, form, schema) do
    error_translator = Module.concat(["Brando", "Blueprint", "ErrorTranslator"])
    error_translator.translate_keys(error_keys, form, schema)
  end

  @doc """
  Returns the first non-nil value, optionally stripping tags or truncating it.
  """
  def fallback(values) do
    value_helpers = Module.concat(["Brando", "Blueprint", "Value"])
    value_helpers.fallback(values)
  end

  @doc """
  Resolves the first non-nil path from `data`.
  """
  def fallback(data, paths) do
    value_helpers = Module.concat(["Brando", "Blueprint", "Value"])
    value_helpers.fallback(data, paths)
  end

  @doc """
  Converts a language code to an Open Graph locale.
  """
  def encode_locale(locale) do
    value_helpers = Module.concat(["Brando", "Blueprint", "Value"])
    value_helpers.encode_locale(locale)
  end

  @doc """
  Safely traverses `data` using `path`.
  """
  def try_path(data, path) do
    value_helpers = Module.concat(["Brando", "Blueprint", "Value"])
    value_helpers.try_path(data, path)
  end
end
