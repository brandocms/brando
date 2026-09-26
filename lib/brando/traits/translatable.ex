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

  `source_controlled_fields` accepts three kinds of selector:

      source_controlled_fields: [
        # Top-level attributes, assets and belongs_to relations
        :project_year,
        # Variables of the block module whose uid is "hero-banner"
        {:module, "hero-banner", [:layout, :theme]},
        # Fields of the rows in an owned subform
        credits: [:url]
      ]

  Assets are already source-controlled, so listing them only documents the
  intent. A subform must be an owned collection (`has_many` with `cast: true`,
  or `embeds_many`) whose rows are matched by `uid` (`trait :ensure_uid`), and
  its fields must be inputs of that subform in the form; identity and
  bookkeeping fields (`id`, `uid`, `sequence`, timestamps, foreign keys) cannot
  be listed. Module variables are named by the module's `uid`, the identifier
  `Brando.Content.Definition` uses, so the same variable key on another module
  stays language-specific. Variables of table rows and nested subforms cannot
  be addressed.

  Selectors are checked when the Blueprint compiles, except module variables,
  whose modules live in the database: `Brando.Translations.check_config/1`
  reports a module uid or variable that does not exist.

  `:synchronized` requires alternates, which is the default. The mode defaults
  to `:independent`, the behaviour of a plain `trait :translatable`.
  """
  use Brando.Trait

  alias Brando.Blueprint.Assets
  alias Brando.Blueprint.Attributes
  alias Brando.Exception.BlueprintError
  alias Brando.Trait.Translatable.Compiler

  @modes [:independent, :synchronized]

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)

  @identity_fields ~w(id uid sequence inserted_at updated_at deleted_at language)a

  @doc """
  The translation policy a Blueprint declared on this trait:
  `source_controlled_fields` holds the top-level names,
  `source_controlled_subform_fields` maps a subform to its fields, and
  `source_controlled_module_vars` maps a module uid to variable keys.
  """
  def config(opts) do
    selectors = Keyword.get(opts, :source_controlled_fields, [])

    %{
      mode: Keyword.get(opts, :mode, :independent),
      source_controlled_fields: for(name <- List.wrap(selectors), is_atom(name), do: name),
      source_controlled_subform_fields:
        for({name, fields} <- List.wrap(selectors), is_atom(name), is_list(fields), into: %{}, do: {name, fields}),
      source_controlled_module_vars:
        for(
          {:module, uid, keys} <- List.wrap(selectors),
          is_binary(uid) and is_list(keys),
          into: %{},
          do: {uid, Enum.map(keys, &to_string/1)}
        )
    }
  end

  @impl true
  def validate(module, opts) do
    opts = normalize_opts(opts)
    %{mode: mode} = config(opts)

    validate_mode!(module, mode, opts)
    validate_fields!(module, mode, Keyword.get(opts, :source_controlled_fields, []))
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

  defp validate_fields!(module, mode, selectors) do
    unless is_list(selectors) and Enum.all?(selectors, &selector?/1) do
      raise BlueprintError,
        message:
          "#{inspect(module)}: trait :translatable source_controlled_fields must list field names, " <>
            "{subform, [fields]} or {:module, \"uid\", [vars]}, got #{inspect(selectors)}"
    end

    if selectors != [] and mode != :synchronized do
      raise BlueprintError,
        message: "#{inspect(module)}: trait :translatable source_controlled_fields requires mode: :synchronized"
    end

    %{source_controlled_fields: fields} = config(source_controlled_fields: selectors)

    case fields -- controllable_fields(module) do
      [] ->
        :ok

      unknown ->
        raise BlueprintError,
          message:
            "#{inspect(module)}: trait :translatable source_controlled_fields #{inspect(unknown)} " <>
              "are not attributes, assets or belongs_to relations"
    end

    validate_subforms!(module, for({name, fields} <- selectors, is_atom(name), do: {name, fields}))
    validate_module_vars!(module, for({:module, uid, keys} <- selectors, do: {uid, keys}))
  end

  defp selector?(name) when is_atom(name), do: true

  defp selector?({:module, uid, keys}),
    do: is_binary(uid) and uid != "" and is_list(keys) and keys != [] and Enum.all?(keys, &(is_atom(&1) or is_binary(&1)))

  defp selector?({name, fields}) when is_atom(name),
    do: is_list(fields) and fields != [] and Enum.all?(fields, &is_atom/1)

  defp selector?(_), do: false

  defp validate_subforms!(module, subforms) do
    case subforms |> Enum.frequencies_by(&elem(&1, 0)) |> Enum.find(&(elem(&1, 1) > 1)) do
      nil ->
        :ok

      {name, _} ->
        raise BlueprintError,
          message:
            "#{inspect(module)}: trait :translatable source_controlled_fields lists the subform #{inspect(name)} more than once"
    end

    relations = Map.new(Spark.Dsl.Extension.get_entities(module, [:relations]), &{&1.name, &1})
    inputs = subform_inputs(module)

    Enum.each(subforms, fn {name, fields} ->
      validate_owned!(module, name, relations[name])
      validate_subform_fields!(module, name, fields, Map.get(inputs, name, []))
    end)
  end

  # `module: :blocks` and `module: :alternates` are generated relations, not
  # subforms.
  defp validate_owned!(module, name, relation) do
    opts = Map.new((relation && relation.opts) || [])
    schema_module? = is_atom(opts[:module]) and String.starts_with?(to_string(opts[:module]), "Elixir.")

    collection? =
      relation != nil and (relation.type == :embeds_many or (relation.type == :has_many and opts[:cast] == true))

    unless schema_module? and collection? do
      raise BlueprintError,
        message:
          "#{inspect(module)}: trait :translatable source_controlled_fields names #{inspect(name)}, " <>
            "which is not an owned subform (has_many with cast: true, or embeds_many)"
    end
  end

  defp validate_subform_fields!(module, name, fields, inputs) do
    case Enum.filter(fields, &(&1 in @identity_fields or String.ends_with?(to_string(&1), "_id"))) do
      [] ->
        :ok

      identity ->
        raise BlueprintError,
          message:
            "#{inspect(module)}: trait :translatable source_controlled_fields #{inspect(identity)} in " <>
              "#{inspect(name)} identify rows and cannot be source-controlled"
    end

    case fields -- inputs do
      [] ->
        :ok

      unknown ->
        raise BlueprintError,
          message:
            "#{inspect(module)}: trait :translatable source_controlled_fields #{inspect(unknown)} are not " <>
              "inputs of the #{inspect(name)} subform"
    end
  end

  defp validate_module_vars!(module, selectors) do
    case selectors |> Enum.frequencies_by(&elem(&1, 0)) |> Enum.find(&(elem(&1, 1) > 1)) do
      nil ->
        :ok

      {uid, _} ->
        raise BlueprintError,
          message:
            "#{inspect(module)}: trait :translatable source_controlled_fields lists module #{inspect(uid)} " <>
              "more than once"
    end
  end

  # Inputs of each subform in the Blueprint's own forms, read from the module
  # being compiled.
  defp subform_inputs(module) do
    form = if function_exported?(module, :__form__, 0), do: module.__form__()

    case form do
      %{tabs: tabs} ->
        for tab <- tabs,
            fieldset <- tab.fields,
            %Brando.Blueprint.Forms.Subform{name: name, sub_fields: sub_fields} <- fieldset.fields,
            reduce: %{} do
          acc -> Map.update(acc, name, input_names(sub_fields), &Enum.uniq(&1 ++ input_names(sub_fields)))
        end

      _ ->
        %{}
    end
  end

  defp input_names(sub_fields), do: for(%{name: field} <- sub_fields, is_atom(field), do: field)

  # Runs while each translatable Blueprint compiles. Relations are read off
  # Spark, not through `Brando.Blueprint.Relations.__relations__/1`: that module
  # depends on `Brando.Repo`, which reaches the whole application, so the
  # compile-time call put every translatable Blueprint in a compile-connected
  # cycle with itself (see brandocms/brando#2737).
  defp controllable_fields(module) do
    attributes = Enum.map(Attributes.__attributes__(module), & &1.name)
    assets = Enum.map(Assets.__assets__(module), & &1.name)

    relations =
      for %{type: :belongs_to, name: name} <- Spark.Dsl.Extension.get_entities(module, [:relations]), do: name

    attributes ++ assets ++ relations
  end

  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_opts(opts) when is_list(opts), do: opts
end
