defmodule Brando.Blueprint.Utils do
  @moduledoc false
  alias Brando.Utils

  @strip_ecto_opts [:cast, :module, :required, :unique, :constraints, :sort_param, :drop_param]
  @strip_embeds_opts [:cast, :module, :unique, :constraints]

  def to_ecto_type(:text), do: :string
  def to_ecto_type(:status), do: Brando.Type.Status
  def to_ecto_type(:file), do: Brando.Type.File
  def to_ecto_type(:image), do: Brando.Type.Image
  def to_ecto_type(:language), do: Ecto.Enum
  def to_ecto_type(:enum), do: Ecto.Enum
  def to_ecto_type(:video), do: Brando.Type.Video
  def to_ecto_type(:i18n_string), do: Brando.Type.I18nString
  def to_ecto_type(:slug), do: :string
  def to_ecto_type(:datetime), do: :utc_datetime

  def to_ecto_type(:villain) do
    IO.puts(":villain type is deprecated. Please move to :blocks")
    :map
  end

  def to_ecto_type(type), do: type

  def to_ecto_opts(:language, opts), do: Map.to_list(opts)

  def to_ecto_opts(:belongs_to, opts), do: opts |> Map.drop(@strip_ecto_opts ++ [:on_delete]) |> Map.to_list()

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

  @strip_changeset_opts [:cast, :module]
  def to_changeset_opts(:has_one, opts), do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:belongs_to, opts), do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:many_to_many, opts), do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:has_many, opts), do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:embeds_one, opts), do: opts |> Map.drop(@strip_embeds_opts) |> Map.to_list()

  def to_changeset_opts(:embeds_many, opts), do: opts |> Map.drop(@strip_embeds_opts) |> Map.to_list()

  def to_changeset_opts(_type, opts), do: Map.to_list(opts)

  def translate_error_keys(error_keys, form, schema) do
    gettext_module = schema.__modules__().gettext

    gettext_domain =
      String.downcase("#{schema.__naming__().domain}_#{schema.__naming__().schema}")

    for error_key <- error_keys do
      case Brando.Blueprint.Forms.get_field(error_key, form) do
        nil ->
          require Logger

          Logger.error("""
          (!) Could not get field `#{inspect(error_key)}` from form:

          #{inspect(form, pretty: true)}
          """)

          String.capitalize(to_string(error_key))

        field ->
          msgid =
            if field.__struct__ == Brando.Blueprint.Forms.Subform do
              Map.get(field, :label) || String.capitalize(to_string(field.name))
            else
              Keyword.get(field.opts, :label, String.capitalize(to_string(error_key)))
            end

          Gettext.dgettext(gettext_module, gettext_domain, msgid)
      end
    end
  end

  @doc """
  Processes a list of values and returns the first non-nil value.
  If a value is a tuple with `:strip_tags` as the first element, it sanitizes the value by stripping HTML tags.
  If a value is a tuple with `:strip_tags_and_truncate` as the first element, it sanitizes the value by stripping
  HTML tags and truncating it.

  ## Parameters

    - `values`: A list of values to process.

  ## Returns

    - The first non-nil value from the list, with HTML tags stripped if the value is a tuple with `:strip_tags`.

  ## Examples
      iex> fallback([nil, {:strip_tags, "<p>text</p>"}, "default"])
      "text"

      iex> fallback([nil, nil, "default"])
      "default"

      iex> fallback([nil, {:strip_tags, nil}, "default"])
      "default"
  """
  def fallback(values) when is_list(values) do
    Enum.reduce_while(values, nil, fn
      {:strip_tags, value}, _ ->
        case value do
          nil -> {:cont, nil}
          _ -> {:halt, HtmlSanitizeEx.strip_tags(value)}
        end

      {:strip_tags_and_truncate, value}, _ ->
        case value do
          nil -> {:cont, nil}
          _ -> {:halt, value |> HtmlSanitizeEx.strip_tags() |> Brando.Utils.truncate(160)}
        end

      nil, _ ->
        {:cont, nil}

      value, _ ->
        {:halt, value}
    end)
  end

  def fallback(data, keys) when is_list(keys) do
    Enum.reduce_while(keys, nil, fn
      {:strip_tags, key}, _ ->
        keys = (is_list(key) && key) || List.wrap(key)

        case Utils.try_path(data, keys) do
          nil -> {:cont, nil}
          val -> {:halt, HtmlSanitizeEx.strip_tags(val)}
        end

      {:strip_tags_and_truncate, key}, _ ->
        keys = (is_list(key) && key) || List.wrap(key)

        case Utils.try_path(data, keys) do
          nil -> {:cont, nil}
          value -> {:halt, value |> HtmlSanitizeEx.strip_tags() |> Brando.Utils.truncate(160)}
        end

      key, _ ->
        keys = (is_list(key) && key) || List.wrap(key)

        case Utils.try_path(data, keys) do
          nil -> {:cont, nil}
          val -> {:halt, val}
        end
    end)
  end

  # convert language to a format facebook/opengraph understands
  def encode_locale("en"), do: "en_US"
  def encode_locale("no"), do: "nb_NO"
  def encode_locale("nb"), do: "nb_NO"
  def encode_locale("nn"), do: "nn_NO"
  def encode_locale(locale), do: locale

  defdelegate try_path(map, path), to: Brando.Utils
end
