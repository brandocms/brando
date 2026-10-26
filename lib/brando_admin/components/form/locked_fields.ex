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

  A locked input keeps the value the server put in the form
  (`server_values/4`): the stored entry's, with its input's `default:` when
  empty (the browser shows the default for a date, date-time or color
  input), a new entry's default params, a translation or a revision's
  working copy. A value that reached the form from the browser (a recovery
  copy, a picker) is not one.

  A `:slug` input declared `readonly: true` or `disabled: true` is not
  locked: the browser's Slug hook writes it from its source field, and
  nothing on the server does.
  """

  alias Brando.Blueprint.Forms.Form
  alias Brando.Trait.Creator
  alias Ecto.Changeset

  # Input types whose value the browser fills in, so a lock for everyone
  # would lose it
  @client_filled [:slug]

  @doc """
  `params` without the fields `user` may not change in `schema`'s `blueprint`
  form. A locked input whose value in `values` (`server_values/4`) differs
  from `entry`'s takes that value, cast again.
  """
  @spec lock(map() | nil, module(), struct() | nil, map() | atom(), map(), struct()) :: map() | nil
  def lock(params, schema, %Form{} = blueprint, user, values, entry) when is_map(params) do
    params = drop(params, schema, blueprint, user)
    Enum.reduce(locked_inputs(blueprint, user), params, &keep(&2, schema, &1, values, entry))
  end

  def lock(params, _schema, _blueprint, _user, _values, _entry), do: params

  @doc """
  The value of each of `user`'s locked inputs in `changeset`, which the
  server built, by field; an empty one takes its input's `default:`. What
  `lock/6` keeps.
  """
  @spec server_values(Changeset.t(), module(), struct() | nil, map() | atom()) :: map()
  def server_values(%Changeset{} = changeset, schema, %Form{} = blueprint, user) do
    for input <- locked_inputs(blueprint, user), key = key(schema, input.name), key != nil, into: %{} do
      {key, changeset |> Changeset.get_field(key) |> or_default(Map.get(input, :opts))}
    end
  end

  def server_values(_changeset, _schema, _blueprint, _user), do: %{}

  defp or_default(nil, opts) when is_list(opts) do
    case Keyword.get(opts, :default) do
      default when is_function(default, 0) -> default.()
      default -> default
    end
  end

  defp or_default(value, _opts), do: value

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
        (input.superuser_fieldset and not superuser?) or
          locked?(Map.get(input, :opts), superuser?, Map.get(input, :type) in @client_filled),
        do: input
  end

  defp locked?(opts, superuser?, client_filled?) when is_list(opts) do
    Enum.any?([:readonly, :disabled], fn key ->
      case Keyword.get(opts, key) do
        true -> not client_filled?
        :unless_superuser -> not superuser?
        _ -> false
      end
    end)
  end

  defp locked?(_opts, _superuser?, _client_filled?), do: false

  # The server's value for a locked input, cast again, when the entry's
  # differs. A relation or an embed is only dropped: its value is not one to
  # cast. A media input keeps its foreign key.
  defp keep(params, schema, %{name: name}, values, entry) do
    with key when key != nil <- key(schema, name),
         {:ok, value} <- Map.fetch(values, key),
         true <- value != Map.get(entry, key) do
      Map.put(params, to_string(key), value)
    else
      _ -> params
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
