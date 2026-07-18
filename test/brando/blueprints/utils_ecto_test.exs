defmodule Brando.Blueprint.UtilsEctoTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.Utils

  test "Blueprint attribute types map to their Ecto representations" do
    assert Utils.to_ecto_type(:text) == :string
    assert Utils.to_ecto_type(:slug) == :string
    assert Utils.to_ecto_type(:datetime) == :utc_datetime
    assert Utils.to_ecto_type(:timestamp) == :naive_datetime
    assert Utils.to_ecto_type(:uuid) == Ecto.UUID
    assert Utils.to_ecto_type(:language) == Ecto.Enum
    assert Utils.to_ecto_type(:enum) == Ecto.Enum
    assert Utils.to_ecto_type(:status) == Brando.Type.Status
    assert Utils.to_ecto_type(:file) == Brando.Type.File
    assert Utils.to_ecto_type(:image) == Brando.Type.Image
    assert Utils.to_ecto_type(:video) == Brando.Type.Video
    assert Utils.to_ecto_type(:i18n_string) == Brando.Type.I18nString
    assert Utils.to_ecto_type(:decimal) == :decimal
    assert Utils.to_ecto_type({:array, :enum}) == {:array, Ecto.Enum}
    assert Utils.to_ecto_type({:array, Ecto.Enum}) == {:array, Ecto.Enum}
  end

  test "schema options omit Blueprint-only metadata" do
    opts = %{
      cast: true,
      constraint_name: "custom_author_fkey",
      module: Example,
      null: false,
      required: true,
      on_delete: :delete_all,
      source: :author_id
    }

    assert Utils.to_ecto_opts(:belongs_to, opts) == [source: :author_id]

    assert Utils.to_ecto_opts(:integer, %{null: false, precision: 10, scale: 2, default: 0}) ==
             [default: 0]

    assert Utils.to_ecto_opts(:language, %{
             languages: [[value: "en", text: "English"]],
             required: true,
             values: [:en]
           }) == [values: [:en]]
  end

  test "embed defaults are applied without overwriting explicit configuration" do
    assert Utils.to_ecto_opts(:embeds_one, %{}) == [on_replace: :update]
    assert Utils.to_ecto_opts(:embeds_many, %{on_replace: :raise}) == [on_replace: :raise]
  end

  test "changeset options retain only options consumed by Ecto casting" do
    opts = %{
      cast: true,
      constraint_name: "custom_items_fkey",
      foreign_key: :item_ref,
      module: Example,
      on_replace: :delete,
      required: true,
      required_message: "select an item"
    }

    assert Utils.to_changeset_opts(:has_many, opts) |> Map.new() == %{
             required: true,
             required_message: "select an item"
           }
  end
end
