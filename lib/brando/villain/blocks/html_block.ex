defmodule Brando.Villain.Blocks.HtmlBlock do
  @moduledoc """
  An HTML ref: markup a superuser writes, with named, typed parameters that
  editors fill in.

  `text` is the template. It names each parameter as `{{ key }}`, and
  `params` declares them: a key, a label for the editor's form and a type.
  `values` holds what the editor typed, by key. On render (`render/1`) each
  `{{ key }}` of a declared parameter is replaced by its value, checked
  against its type and escaped for it; an invalid or missing value renders
  as nothing. Any other `{{ … }}` is left as it was, for the Liquid pass that
  renders the page.

  A template without parameters renders as it is.

  Only a superuser changes `text` or `params` (`Brando.Content.RefGuard`);
  anyone who can edit the entry fills in `values`.
  """
  use Brando.Villain.Block,
    type: "html"

  alias Brando.Villain.Parser

  @types [:id, :number, :url, :text]
  @key_format ~r/\A[a-z][a-z0-9_]*\z/
  @placeholder ~r/\{\{\s*([a-z][a-z0-9_]*)\s*\}\}/

  defmodule Param do
    @moduledoc """
    A parameter of an HTML ref's template: `key` names it in the markup as
    `{{ key }}`, `label` names it in the editor's form, and `type` says what
    it takes and how it is escaped (`Brando.Villain.Blocks.HtmlBlock`).
    """
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field :key, :string
      field :label, :string
      field :type, Ecto.Enum, values: [:id, :number, :url, :text], default: :text
    end

    def changeset(struct, params \\ %{}) do
      struct
      |> cast(params, [:key, :label, :type])
      |> update_change(:key, &String.trim/1)
      |> validate_required([:key, :type])
      |> validate_format(:key, ~r/\A[a-z][a-z0-9_]*\z/,
        message: "must start with a lowercase letter and hold only lowercase letters, digits and _"
      )
      |> validate_length(:key, max: 64)
    end
  end

  defmodule Data do
    @moduledoc false
    use Ecto.Schema

    import Ecto.Changeset

    alias Brando.Villain.Blocks.HtmlBlock

    @primary_key false

    embedded_schema do
      field :text, :string
      embeds_many :params, HtmlBlock.Param, on_replace: :delete
      field :values, :map, default: %{}
    end

    def changeset(struct, params \\ %{}) do
      struct
      |> cast(params, [:text, :values])
      |> update_change(:values, &HtmlBlock.normalize_values/1)
      |> cast_embed(:params, sort_param: :sort_param_ids, drop_param: :drop_param_ids)
      |> validate_change(:params, fn :params, params ->
        keys = for %{action: action} = cs <- params, action not in [:replace, :delete], do: get_field(cs, :key)
        if keys == Enum.uniq(keys), do: [], else: [params: "has a key twice"]
      end)
      |> HtmlBlock.validate_values()
    end
  end

  @doc "The parameter types."
  def types, do: @types

  @doc "Whether `key` is a valid parameter key."
  def valid_key?(key) when is_binary(key), do: Regex.match?(@key_format, key)
  def valid_key?(_), do: false

  def protected_attrs do
    # Module sync leaves the block's template, its parameters and the values
    # editors gave them alone: the template is the block's own.
    [:text, :params, :values]
  end

  @doc """
  `data`'s template with each declared parameter's value in place of its
  `{{ key }}`, escaped for the parameter's type. A template without
  parameters is returned as it is.
  """
  @spec render(map() | nil) :: String.t()
  def render(nil), do: ""

  def render(data) do
    text = Map.get(data, :text) || ""

    case params_by_key(data) do
      params when params == %{} ->
        text

      params ->
        values = Map.get(data, :values) || %{}

        Regex.replace(@placeholder, text, fn placeholder, key ->
          case params do
            %{^key => type} -> escape(type, value(values, key))
            _ -> placeholder
          end
        end)
    end
  end

  @doc """
  `value` as it goes into the markup for a parameter of `type`, or `""`
  when it is not a valid value of that type:

    * `:id` — letters, digits, `_` and `-` only. Safe anywhere, a script
      included.
    * `:number` — an integer or a decimal number. Safe anywhere.
    * `:url` — an `https:` or a relative address, escaped for a quoted
      attribute.
    * `:text` — any text, escaped for element content and quoted
      attributes.

  `{` and `}` are escaped too, so a value never forms Liquid for the page's
  Liquid pass.
  """
  @spec escape(atom() | String.t(), term()) :: String.t()
  def escape(type, value) do
    case cast_value(type, value) do
      {:ok, value} -> encode(type, value)
      :error -> ""
    end
  end

  @doc "Whether `value` is valid for a parameter of `type`. An empty value is."
  @spec valid_value?(atom() | String.t(), term()) :: boolean()
  def valid_value?(_type, value) when value in [nil, ""], do: true
  def valid_value?(type, value), do: cast_value(type, value) != :error

  defp cast_value(_type, value) when value in [nil, ""], do: :error

  defp cast_value(type, value) when is_integer(value) or is_float(value), do: cast_value(type, to_string(value))

  defp cast_value(type, value) when is_binary(value) do
    case to_type(type) do
      :id -> if Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, value), do: {:ok, value}, else: :error
      :number -> if Regex.match?(~r/\A-?\d+(\.\d+)?\z/, value), do: {:ok, value}, else: :error
      :url -> url(value)
      :text -> {:ok, value}
      nil -> :error
    end
  end

  defp cast_value(_type, _value), do: :error

  # `Brando.Villain.Parser.safe_url/1`, and then only https or no scheme
  defp url(value) do
    case Parser.safe_url(value) do
      nil ->
        :error

      safe ->
        read = safe |> HtmlEntities.decode() |> String.replace(~r/[\x00-\x20]/, "")

        case Regex.run(~r/^([a-z][a-z0-9+.-]*):/i, read, capture: :all_but_first) do
          nil -> {:ok, safe}
          [scheme] -> if String.downcase(scheme) == "https", do: {:ok, safe}, else: :error
        end
    end
  end

  defp encode(type, value) do
    case to_type(type) do
      :url -> value |> Parser.escape_attr() |> escape_braces()
      :text -> value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string() |> escape_braces()
      _ -> value
    end
  end

  defp escape_braces(value), do: value |> String.replace("{", "&#123;") |> String.replace("}", "&#125;")

  defp to_type(type) when type in @types, do: type

  defp to_type(type) when is_binary(type) do
    Enum.find(@types, &(Atom.to_string(&1) == type))
  end

  defp to_type(_), do: nil

  defp value(values, key), do: Map.get(values, key)

  @doc "`data`'s declared parameters as a map of key to type."
  @spec params_by_key(map()) :: %{String.t() => atom()}
  def params_by_key(data) do
    for param <- Map.get(data, :params) || [],
        key = field(param, :key),
        is_binary(key),
        into: %{},
        do: {key, to_type(field(param, :type))}
  end

  defp field(%{} = param, key), do: Map.get(param, key, Map.get(param, Atom.to_string(key)))

  @doc """
  Values as stored: string keys, and each value a string. A number is
  stored as the text it was typed as; anything else is dropped.
  """
  def normalize_values(values) when is_map(values) do
    for {key, value} <- values, value = normalize_value(value), value != :drop, into: %{} do
      {to_string(key), value}
    end
  end

  def normalize_values(_), do: %{}

  defp normalize_value(nil), do: ""
  defp normalize_value(value) when is_binary(value), do: value
  defp normalize_value(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp normalize_value(_), do: :drop

  @doc """
  Adds an error on `:values` for each declared parameter whose value is not
  valid for its type.
  """
  def validate_values(%Ecto.Changeset{} = changeset) do
    data = Ecto.Changeset.apply_changes(changeset)

    case invalid_keys(data) do
      [] ->
        changeset

      keys ->
        Ecto.Changeset.add_error(changeset, :values, "has an invalid value for %{keys}", keys: Enum.join(keys, ", "))
    end
  end

  @doc "The keys of `data`'s declared parameters whose value is not valid for its type."
  @spec invalid_keys(map()) :: [String.t()]
  def invalid_keys(data) do
    values = Map.get(data, :values) || %{}

    for {key, type} <- params_by_key(data), not valid_value?(type, Map.get(values, key)), do: key
  end
end
