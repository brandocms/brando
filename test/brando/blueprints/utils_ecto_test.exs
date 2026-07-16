defmodule Brando.Blueprint.UtilsEctoTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.Utils

  test "schema options omit Blueprint-only metadata" do
    opts = %{cast: true, module: Example, required: true, on_delete: :delete_all, source: :author_id}

    assert Utils.to_ecto_opts(:belongs_to, opts) == [source: :author_id]
  end

  test "embed defaults are applied without overwriting explicit configuration" do
    assert Utils.to_ecto_opts(:embeds_one, %{}) == [on_replace: :update]
    assert Utils.to_ecto_opts(:embeds_many, %{on_replace: :raise}) == [on_replace: :raise]
  end

  test "changeset options retain validation metadata" do
    opts = %{cast: true, module: Example, required: true, on_replace: :delete}

    assert Utils.to_changeset_opts(:has_many, opts) |> Map.new() == %{
             on_replace: :delete,
             required: true
           }
  end
end
