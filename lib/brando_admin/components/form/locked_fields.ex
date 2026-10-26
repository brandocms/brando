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

  A locked input keeps the value the form has (`lock/5`): one Brando set,
  such as a new entry's default params or a restored draft, is a change in
  the form's changeset and is cast again in place of the browser's value.
  The input's `default:` fills an empty field, as the browser does for a
  date, date-time or color input.

  A `:slug` input is never locked: the browser's Slug hook writes it from
  its source field, and nothing on the server does.
  """

  alias Brando.Blueprint.Forms.Form
  alias Brando.Trait.Creator
  alias Ecto.Changeset

  # Input types whose value the browser fills in, so a lock would lose it
  @client_filled [:slug]

  @doc """
  `params` without the fields `user` may not change in `schema`'s `blueprint`
  form. A locked input whose field `current` (the form's changeset) has a
  change for takes that value instead; an empty one takes the input's
  `default:`.
  """
  @spec lock(map() | nil, module(), struct() | nil, map() | atom(), Changeset.t() | nil) :: map() | nil
  def lock(params, schema, %Form{} = blueprint, user, current) when is_map(params) do
    params = drop(params, schema, blueprint, user)

    case current do
      %Changeset{} -> Enum.reduce(locked_inputs(blueprint, user), params, &keep(&2, schema, &1, current))
      _ -> params
    end
  end

  def lock(params, _schema, _blueprint, _user, _current), do: params

  @doc "`params` without the fields `user` may not change in `schema`'s `blueprint` form."
  @spec drop(map() | nil, module(), struct() | nil, map() | atom()) :: map() | nil
  def drop(params, schema, %Form{} = blueprint, user) when is_map(params),
    do: Map.drop(params, schema |> params_for(fields(schema, blueprint, user)) |> Enum.map(&to_string/1))

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
        Map.get(input, :type) not in @client_filled,
        (input.superuser_fieldset and not superuser?) or locked?(Map.get(input, :opts), superuser?),
        do: input
  end

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

  # The form's change for a locked input, cast again; an empty field's
  # `default:`. A relation or an embed is only dropped: its change is a
  # changeset, not a value to cast. A media input keeps its foreign key.
  defp keep(params, schema, %{name: name} = input, current) do
    case key(schema, name) do
      nil ->
        params

      key ->
        case Map.fetch(current.changes, key) do
          {:ok, value} -> Map.put(params, to_string(key), value)
          :error -> put_default(params, key, Map.get(input, :opts), current)
        end
    end
  end

  defp key(schema, name) do
    case schema.__schema__(:association, name) do
      %Ecto.Association.BelongsTo{owner_key: key} -> key
      nil -> if name in schema.__schema__(:embeds), do: nil, else: name
      _many -> nil
    end
  end

  defp put_default(params, key, opts, current) when is_list(opts) do
    with true <- Keyword.has_key?(opts, :default),
         nil <- Changeset.get_field(current, key) do
      Map.put(params, to_string(key), default(Keyword.get(opts, :default)))
    else
      _ -> params
    end
  end

  defp put_default(params, _key, _opts, _current), do: params

  defp default(default) when is_function(default, 0), do: default.()
  defp default(default), do: default

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
