defmodule Brando.Worker.TranslationSync do
  @moduledoc """
  Computes pending versions for the synchronized targets of a translation
  group after its source was saved (`Brando.Translations.sync_group/2`), or
  for one target after it was saved (`Brando.Translations.resync_target/2`).
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias Brando.Tenant.Job, as: TenantJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"group_id" => group_id, "member_id" => member_id}} = job) do
    TenantJob.run(job, fn ->
      case Brando.Translations.resync_target(group_id, member_id) do
        {:ok, _} -> refresh_listing(group_id)
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  def perform(%Oban.Job{args: %{"group_id" => group_id} = args} = job) do
    TenantJob.run(job, fn ->
      case Brando.Translations.sync_group(group_id, minor: Map.get(args, "minor", false)) do
        {:ok, _} -> refresh_listing(group_id)
        # The source was deleted since the save; there is nothing to sync from.
        {:error, :source_not_found} -> {:cancel, :source_not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  # Listings show each language's open work (`Brando.Translations.listing_status/2`).
  defp refresh_listing(group_id) do
    if schema = Brando.Translations.group_schema(group_id),
      do: BrandoAdmin.LiveView.Listing.update_list_entries(schema)

    :ok
  end
end
