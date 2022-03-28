defmodule Brando.Trait.ScheduledPublishing do
  @moduledoc """
  Adds `publish_at`
  """
  use Brando.Trait
  import Ecto.Changeset

  attributes do
    attribute :publish_at, :datetime
  end

  # Status changed to :published, but no publish_at set = Set to utc_now
  def before_save(%{changes: %{status: :published}} = changeset, _user) do
    if get_field(changeset, :publish_at) == nil do
      put_change(changeset, :publish_at, DateTime.truncate(DateTime.utc_now(), :second))
    else
      changeset
    end
  end

  def before_save(changeset, _user) do
    changeset
  end
end
