defmodule Brando.Trait.Translatable do
  @moduledoc """
  Adds language metadata and optional alternate-entry relationships.

      trait :translatable

  ## Synchronized translations

      trait :translatable,
        mode: :synchronized,
        source_controlled_fields: [:project_year, :featured]

  In `:synchronized` mode one entry of a translation group — its source —
  controls block structure, media and the fields listed in
  `source_controlled_fields`. Saving the source computes a pending version for
  each synchronized translation (see `Brando.Translations`); translated text
  already in a translation is kept.

  `source_controlled_fields` accepts top-level attribute, asset and
  `belongs_to` relation names. Assets are already source-controlled, so listing
  them only documents the intent. Fields inside subforms and block-module
  variables cannot be addressed yet.

  `:synchronized` requires alternates, which is the default. The mode defaults
  to `:independent`, the behaviour of a plain `trait :translatable`.
  """
  use Brando.Trait

  alias Brando.Blueprint.Assets
  alias Brando.Blueprint.Attributes
  alias Brando.Blueprint.Relations
  alias Brando.Exception.BlueprintError
  alias Brando.Trait.Translatable.Compiler

  @modes [:independent, :synchronized]

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)

  @doc "The translation policy a Blueprint declared on this trait."
  def config(opts) do
    %{
      mode: Keyword.get(opts, :mode, :independent),
      source_controlled_fields: Keyword.get(opts, :source_controlled_fields, [])
    }
  end

  @impl true
  def validate(module, opts) do
    opts = normalize_opts(opts)
    %{mode: mode, source_controlled_fields: fields} = config(opts)

    validate_mode!(module, mode, opts)
    validate_fields!(module, mode, fields)
    true
  end

  defp validate_mode!(module, mode, opts) do
    unless mode in @modes do
      raise BlueprintError,
        message: "#{inspect(module)}: trait :translatable mode must be one of #{inspect(@modes)}, got #{inspect(mode)}"
    end

    if mode == :synchronized and Keyword.get(opts, :alternates, true) == false do
      raise BlueprintError,
        message: "#{inspect(module)}: trait :translatable, mode: :synchronized requires alternates"
    end
  end

  defp validate_fields!(module, mode, fields) do
    unless is_list(fields) and Enum.all?(fields, &is_atom/1) do
      raise BlueprintError,
        message: "#{inspect(module)}: trait :translatable source_controlled_fields must be a list of field names"
    end

    if fields != [] and mode != :synchronized do
      raise BlueprintError,
        message: "#{inspect(module)}: trait :translatable source_controlled_fields requires mode: :synchronized"
    end

    case fields -- controllable_fields(module) do
      [] ->
        :ok

      unknown ->
        raise BlueprintError,
          message:
            "#{inspect(module)}: trait :translatable source_controlled_fields #{inspect(unknown)} " <>
              "are not attributes, assets or belongs_to relations"
    end
  end

  @impl true
  def after_save(entry, _changeset, _user) do
    # `minor: true` arrives with the editor's "Save minor text corrections".
    Brando.Translations.source_saved(entry, minor: false)
  end

  defp controllable_fields(module) do
    attributes = Enum.map(Attributes.__attributes__(module), & &1.name)
    assets = Enum.map(Assets.__assets__(module), & &1.name)

    relations =
      for %{type: :belongs_to, name: name} <- Relations.__relations__(module), do: name

    attributes ++ assets ++ relations
  end

  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_opts(opts) when is_list(opts), do: opts
end
