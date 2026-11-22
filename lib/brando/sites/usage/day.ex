defmodule Brando.Sites.Usage.Day do
  @moduledoc """
  What one site used on one UTC day (`Brando.Sites.Usage`).

  Two writers own different columns of the row, and either may create it:
  the traffic flush adds to `requests` and `bytes_sent`, and the measuring
  sets the sizes and `measured_at`. A row with traffic and no measurement
  has no sizes: its storage is unknown, not zero.

  `databases` has one entry per schema the site has: each environment's, and
  each archive of one (`"archive" => true`), as
  `%{"schema" => …, "environment" => key or nil, "archive" => boolean, "bytes" => integer}`.
  """
  use Ecto.Schema

  # A shared table (`Brando.Tenant.SharedTables`), next to the sites
  @schema_prefix "public"

  @type t :: %__MODULE__{}

  schema "sites_usage_days" do
    belongs_to :site, Brando.Sites.Site
    field :day, :date
    field :requests, :integer, default: 0
    field :bytes_sent, :integer, default: 0
    field :media_bytes, :integer
    field :builds_bytes, :integer
    field :databases, {:array, :map}
    field :measured_at, :utc_datetime_usec
  end

  @doc "Whether the row holds a measurement."
  @spec measured?(t()) :: boolean()
  def measured?(%__MODULE__{measured_at: measured_at}), do: not is_nil(measured_at)

  @doc "The databases' bytes, archives included."
  @spec database_bytes(t()) :: non_neg_integer()
  def database_bytes(%__MODULE__{databases: databases}),
    do: databases |> List.wrap() |> Enum.map(& &1["bytes"]) |> Enum.sum()

  @doc "The site's storage on a measured day: media, kept builds and databases; nil when unmeasured."
  @spec storage_bytes(t()) :: non_neg_integer() | nil
  def storage_bytes(%__MODULE__{} = day) do
    if measured?(day), do: day.media_bytes + day.builds_bytes + database_bytes(day)
  end
end
