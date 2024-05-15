defmodule Brando.Blueprint.Utils do
  @strip_ecto_opts [:cast, :module, :required, :unique, :constraints]
  @strip_embeds_opts [:cast, :module, :unique, :constraints]

  def to_ecto_type(:text), do: :string
  def to_ecto_type(:status), do: Brando.Type.Status
  def to_ecto_type(:file), do: Brando.Type.File
  def to_ecto_type(:image), do: Brando.Type.Image
  def to_ecto_type(:language), do: Ecto.Enum
  def to_ecto_type(:enum), do: Ecto.Enum
  def to_ecto_type(:video), do: Brando.Type.Video
  def to_ecto_type(:villain), do: {:array, PolymorphicEmbed}
  def to_ecto_type(:slug), do: :string
  def to_ecto_type(:datetime), do: :utc_datetime
  def to_ecto_type(type), do: type

  def to_ecto_opts(:language, opts), do: Map.to_list(opts)

  def to_ecto_opts(:belongs_to, opts),
    do: opts |> Map.drop(@strip_ecto_opts ++ [:on_delete]) |> Map.to_list()

  def to_ecto_opts(:many_to_many, opts), do: opts |> Map.drop(@strip_ecto_opts) |> Map.to_list()
  def to_ecto_opts(:has_many, opts), do: opts |> Map.drop(@strip_ecto_opts) |> Map.to_list()

  def to_ecto_opts(:embeds_one, opts) do
    opts
    |> Map.put_new(:on_replace, :update)
    |> Map.drop(@strip_ecto_opts)
    |> Map.to_list()
  end

  def to_ecto_opts(:embeds_many, opts), do: opts |> Map.drop(@strip_ecto_opts) |> Map.to_list()
  def to_ecto_opts(_type, opts), do: opts |> Map.drop(@strip_ecto_opts) |> Map.to_list()

  @strip_changeset_opts [:cast, :module]
  def to_changeset_opts(:belongs_to, opts),
    do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:many_to_many, opts),
    do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:has_many, opts),
    do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:embeds_one, opts),
    do: opts |> Map.drop(@strip_embeds_opts) |> Map.to_list()

  def to_changeset_opts(:embeds_many, opts),
    do: opts |> Map.drop(@strip_embeds_opts) |> Map.to_list()

  def to_changeset_opts(_type, opts), do: Map.to_list(opts)

  def translate_error_keys(error_keys, form, schema) do
    gettext_module = schema.__modules__().gettext

    gettext_domain =
      String.downcase("#{schema.__naming__().domain}_#{schema.__naming__().schema}_forms")

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
              field.label
            else
              Keyword.get(field.opts, :label, String.capitalize(to_string(error_key)))
            end

          Gettext.dgettext(gettext_module, gettext_domain, msgid)
      end
    end
  end
end
