defmodule BrandoAdmin.Components.Form.LockedFields do
  @moduledoc """
  Entry fields the form shows a user but does not let them change, taken out
  of the params before the cast. A value the browser sends for one is not an
  edit, whether the input renders locked or not:

    * for everyone, a top-level input declared `readonly: true` or
      `disabled: true`;
    * for anyone but a superuser, a top-level input declared
      `readonly: :unless_superuser` or `disabled: :unless_superuser`, and every
      field of a `superuser` fieldset;
    * for everyone, a field the schema's `:creator` trait lists as `derived`
      (one a processing pipeline writes, such as an image's `sizes`) that the
      form has no input for.

  An image's `path` is one: the crop editor writes to it, so a path set from
  the form would write outside the media root.

  A locked input keeps its saved value, or one the server put in the form
  (`server_values/5`): a new entry's default params, a translation or a
  revision's working copy. A value that reached the form from the browser
  (a recovery copy, a picker) is not one. While the saved value is empty it
  takes the input's `default:` (`defaults/3`), as the browser shows a date,
  date-time or color input's.

  A locked `:slug` input whose value is empty is filled in from its source
  on the server (`derive_slugs/5`), as the browser's Slug hook fills in an
  unlocked one, so a new entry still gets its slug.
  """

  alias Brando.Blueprint.Forms.Form
  alias Brando.Trait.Creator
  alias BrandoAdmin.Components.Form.SlugHook
  alias Ecto.Changeset

  @doc """
  `params` without the fields `user` may not change in `schema`'s `blueprint`
  form. A locked input takes its value in `values` (`server_values/5`) when
  it differs from `entry`'s, or its default in `defaults` (`defaults/3`)
  while `entry`'s is empty, cast again.
  """
  @spec lock(map() | nil, module(), struct() | nil, map() | atom(), {map(), map()}, struct()) :: map() | nil
  def lock(params, schema, %Form{} = blueprint, user, {values, defaults}, entry) when is_map(params) do
    params = drop(params, schema, blueprint, user)
    Enum.reduce(locked_inputs(blueprint, user), params, &keep(&2, schema, &1, {values, defaults}, entry))
  end

  def lock(params, _schema, _blueprint, _user, _values, _entry), do: params

  @doc """
  `params` (after `lock/6`) with a slug for each of `user`'s locked `:slug`
  inputs that `changeset`, cast from them, leaves empty: generated from its
  `source:` fields in `changeset` as the browser's Slug hook generates one,
  with its `prefix:` and `camel_case:`. The Slug hook fills in an empty slug
  only, so a saved entry's slug stays its URL. Cast again when it differs.
  """
  @spec derive_slugs(map() | nil, Changeset.t(), module(), struct() | nil, map() | atom()) :: map() | nil
  def derive_slugs(params, %Changeset{} = changeset, schema, %Form{} = blueprint, user) when is_map(params) do
    for %{type: :slug, name: name, opts: opts} <- locked_inputs(blueprint, user),
        is_list(opts) and opts[:source] != nil,
        key = key(schema, name),
        key != nil,
        blank?(Changeset.get_field(changeset, key)),
        slug = generate_slug(changeset, opts),
        slug != "",
        reduce: params,
        do: (params -> Map.put(params, to_string(key), slug))
  end

  def derive_slugs(params, _changeset, _schema, _blueprint, _user), do: params

  # As `assets/src/hooks/Slug`: the sources' values joined with `-`, then
  # slugified, and the prefix in front of a slug that isn't empty
  defp generate_slug(changeset, opts) do
    joined = opts[:source] |> List.wrap() |> Enum.map_join("-", &source_value(Changeset.get_field(changeset, &1)))
    slug = if opts[:camel_case], do: SlugHook.camel_case(joined), else: SlugHook.slugify(joined)

    case slug do
      "" -> ""
      slug -> slug_prefix(opts[:prefix], changeset) <> slug
    end
  end

  # The value as its input holds it: a date as `2026-10-26`, a date-time as
  # the DateTimePicker writes it (`toISOString`, `2026-10-26T12:30:00.000Z`).
  # A language map, an embed or a list has no single input.
  defp source_value(nil), do: ""
  defp source_value(%DateTime{} = value), do: value |> DateTime.shift_zone!("Etc/UTC") |> iso_milliseconds()
  defp source_value(%NaiveDateTime{} = value), do: value |> DateTime.from_naive!("Etc/UTC") |> iso_milliseconds()
  defp source_value(value) when is_struct(value), do: if(String.Chars.impl_for(value), do: to_string(value), else: "")
  defp source_value(value) when is_map(value) or is_list(value), do: ""
  defp source_value(value), do: to_string(value)

  defp iso_milliseconds(%DateTime{microsecond: {microsecond, _}} = value),
    do: DateTime.to_iso8601(%{value | microsecond: {div(microsecond, 1000) * 1000, 3}})

  defp slug_prefix(prefix, changeset) when is_function(prefix, 1), do: prefix.(changeset) || ""
  defp slug_prefix(prefix, _changeset) when is_binary(prefix), do: prefix
  defp slug_prefix(_prefix, _changeset), do: ""

  defp blank?(value), do: value in [nil, ""]

  @doc """
  The values `changeset`, which the server built, gives `user`'s locked
  inputs where they differ from `entry`'s, by field: what `lock/6` keeps.
  """
  @spec server_values(Changeset.t(), module(), struct() | nil, map() | atom(), struct()) :: map()
  def server_values(%Changeset{} = changeset, schema, %Form{} = blueprint, user, entry) do
    for input <- locked_inputs(blueprint, user),
        key = key(schema, input.name),
        key != nil,
        value <- [Changeset.get_field(changeset, key)],
        value != Map.get(entry, key),
        into: %{},
        do: {key, value}
  end

  def server_values(_changeset, _schema, _blueprint, _user, _entry), do: %{}

  @doc "The `default:` of each of `user`'s locked inputs that has one, resolved, by field."
  @spec defaults(module(), struct() | nil, map() | atom()) :: map()
  def defaults(schema, %Form{} = blueprint, user) do
    for %{opts: opts} = input <- locked_inputs(blueprint, user),
        is_list(opts) and Keyword.has_key?(opts, :default),
        key = key(schema, input.name),
        key != nil,
        into: %{},
        do: {key, resolve(Keyword.get(opts, :default))}
  end

  def defaults(_schema, _blueprint, _user), do: %{}

  defp resolve(default) when is_function(default, 0), do: default.()
  defp resolve(default), do: default

  @doc "The params keys `drop/4` takes out: the field names, and a media input's foreign key."
  @spec keys(module(), struct() | nil, map() | atom()) :: [atom()]
  def keys(schema, %Form{} = blueprint, user), do: params_for(schema, fields(schema, blueprint, user))
  def keys(_schema, _blueprint, _user), do: []

  @doc "`params` without the fields `user` may not change in `schema`'s `blueprint` form."
  @spec drop(map() | nil, module(), struct() | nil, map() | atom()) :: map() | nil
  def drop(params, schema, %Form{} = blueprint, user) when is_map(params),
    do: Map.drop(params, schema |> keys(blueprint, user) |> Enum.map(&to_string/1))

  def drop(params, _schema, _blueprint, _user), do: params

  @doc "The field names `drop/4` takes out."
  @spec fields(module(), struct(), map() | atom()) :: [atom()]
  def fields(schema, %Form{} = blueprint, user) do
    inputs = for %{name: name} <- inputs(blueprint), do: name
    derived = Creator.derived(schema) -- inputs
    Enum.uniq(derived ++ Enum.map(locked_inputs(blueprint, user), & &1.name))
  end

  # The top-level inputs and subforms of every fieldset, with the fieldset's
  # `superuser` flag
  defp inputs(%Form{tabs: tabs}) do
    for %{fields: fieldsets} <- tabs, %{fields: fields} = fieldset <- fieldsets, field <- fields do
      Map.put(field, :superuser_fieldset, Map.get(fieldset, :superuser, false))
    end
  end

  defp locked_inputs(blueprint, user) do
    superuser? = superuser?(user)

    for input <- inputs(blueprint),
        (input.superuser_fieldset and not superuser?) or locked_for?(input, superuser?),
        do: input
  end

  @doc """
  Whether `user` may not change top-level `input` by its own `readonly:` and
  `disabled:` options: what the form renders locked. A superuser fieldset
  is not rendered for anyone else, so it is not asked here.
  """
  @spec locked_input?(map(), map() | atom()) :: boolean()
  def locked_input?(input, user), do: locked_for?(input, superuser?(user))

  defp locked_for?(input, superuser?),
    do: locked?(Map.get(input, :opts), superuser?)

  defp locked?(opts, superuser?) when is_list(opts) do
    Enum.any?([:readonly, :disabled], fn key ->
      case Keyword.get(opts, key) do
        true -> true
        :unless_superuser -> not superuser?
        _ -> false
      end
    end)
  end

  defp locked?(_opts, _superuser?), do: false

  # The server's value for a locked input, cast again, when the entry's
  # differs; its default while the entry's is empty. A relation or an embed
  # is only dropped: its value is not one to cast. A media input keeps its
  # foreign key.
  defp keep(params, schema, %{name: name}, {values, defaults}, entry) do
    with key when key != nil <- key(schema, name),
         {:ok, value} <- server_value(key, values, defaults, entry) do
      Map.put(params, to_string(key), value)
    else
      _ -> params
    end
  end

  defp server_value(key, values, defaults, entry) do
    saved = Map.get(entry, key)

    case Map.fetch(values, key) do
      {:ok, value} when value != saved -> {:ok, value}
      _ when is_nil(saved) -> Map.fetch(defaults, key)
      _ -> :error
    end
  end

  defp key(schema, name) do
    case schema.__schema__(:association, name) do
      %Ecto.Association.BelongsTo{owner_key: key} -> key
      nil -> if name in schema.__schema__(:embeds), do: nil, else: name
      _many -> nil
    end
  end

  # A media input (`input :cover, :image`) sends its foreign key, `cover_id`
  defp params_for(schema, fields) do
    Enum.flat_map(fields, fn field ->
      case schema.__schema__(:association, field) do
        %Ecto.Association.BelongsTo{owner_key: key} -> [field, key]
        _ -> [field]
      end
    end)
  end

  defp superuser?(%{role: :superuser}), do: true
  defp superuser?(_user), do: false
end
