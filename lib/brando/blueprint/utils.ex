defmodule Brando.Blueprint.Utils do
  def to_ecto_type(:text), do: :string
  def to_ecto_type(:status), do: Brando.Type.Status
  def to_ecto_type(:image), do: Brando.Type.Image
  def to_ecto_type(:language), do: Ecto.Enum
  def to_ecto_type(:enum), do: Ecto.Enum
  def to_ecto_type(:video), do: Brando.Type.Video
  def to_ecto_type(:villain), do: {:array, :map}
  def to_ecto_type(:slug), do: :string
  def to_ecto_type(:datetime), do: :utc_datetime
  def to_ecto_type(type), do: type

  @strip_ecto_opts [:cast, :module, :required, :unique]
  def to_ecto_opts(:language, opts), do: Map.to_list(opts)
  def to_ecto_opts(:belongs_to, opts), do: opts |> Map.drop(@strip_ecto_opts) |> Map.to_list()
  def to_ecto_opts(:many_to_many, opts), do: opts |> Map.drop(@strip_ecto_opts) |> Map.to_list()
  def to_ecto_opts(:has_many, opts), do: opts |> Map.drop(@strip_ecto_opts) |> Map.to_list()
  def to_ecto_opts(:embeds_one, opts), do: opts |> Map.drop(@strip_ecto_opts) |> Map.to_list()
  def to_ecto_opts(:embeds_many, opts), do: opts |> Map.drop(@strip_ecto_opts) |> Map.to_list()
  def to_ecto_opts(_type, opts), do: Map.to_list(opts)

  @strip_changeset_opts [:cast, :module]
  def to_changeset_opts(:belongs_to, opts),
    do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:many_to_many, opts),
    do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:has_many, opts),
    do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:embeds_one, opts),
    do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(:embeds_many, opts),
    do: opts |> Map.drop(@strip_changeset_opts) |> Map.to_list()

  def to_changeset_opts(_type, opts), do: Map.to_list(opts)
end
