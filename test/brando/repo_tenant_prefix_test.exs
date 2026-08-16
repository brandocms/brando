defmodule Brando.RepoTenantPrefixTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Changeset, only: [change: 2]
  import Ecto.Query, only: [from: 2]

  alias Brando.Tenant
  alias Brando.Tenant.Registry

  defmodule Record do
    use Ecto.Schema

    schema "tenant_prefix_records" do
      field :name, :string
      field :deleted_at, :utc_datetime
    end
  end

  @tenant_prefix "tenant_repo-test_preview"
  @override_prefix "tenant_repo-test_override"

  setup do
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(@tenant_prefix)

    for prefix <- [@tenant_prefix, @override_prefix] do
      Ecto.Adapters.SQL.query!(BrandoIntegration.Repo, ~s(CREATE SCHEMA "#{prefix}"))

      Ecto.Adapters.SQL.query!(
        BrandoIntegration.Repo,
        ~s|CREATE TABLE "#{prefix}".tenant_prefix_records (id serial PRIMARY KEY, name text, deleted_at timestamp)|
      )
    end

    on_exit(fn -> Tenant.put_prefix(nil) end)
    :ok
  end

  test "automatically applies the process tenant prefix to reads and writes" do
    record = Brando.Repo.insert!(%Record{name: "Preview"})

    assert record.__meta__.prefix == @tenant_prefix
    assert %Record{id: record_id, name: "Preview"} = Brando.Repo.get(Record, record.id)
    assert record_id == record.id
    assert [%Record{id: ^record_id}] = Brando.Repo.all(Record)
    assert %Record{id: ^record_id} = Brando.Repo.one(Record)
    assert Brando.Repo.aggregate(Record, :count) == 1

    record
    |> change(name: "Updated")
    |> Brando.Repo.update!()

    assert %Record{name: "Updated"} = Brando.Repo.get!(Record, record.id)

    query = from(row in Record, where: row.id == ^record.id)
    assert {1, nil} = Brando.Repo.soft_delete_all(query)
    assert %Record{deleted_at: deleted_at} = Brando.Repo.get!(Record, record.id)
    refute is_nil(deleted_at)
  end

  test "an explicit prefix overrides process context" do
    record = Brando.Repo.insert!(%Record{name: "Override"}, prefix: @override_prefix)

    assert record.__meta__.prefix == @override_prefix
    assert Brando.Repo.all(Record) == []

    assert [%Record{id: record_id}] = Brando.Repo.all(Record, prefix: @override_prefix)
    assert record_id == record.id
  end

  test "schemas marked public ignore the process tenant prefix" do
    assert {:ok, site} =
             Registry.create_site(%{
               name: "Public site",
               key: "public-site",
               languages: ["en"],
               default_language: "en",
               status: :active,
               delivery_mode: :dynamic
             })

    assert Brando.Repo.get!(Brando.Sites.Site, site.id).__meta__.prefix == "public"
    assert Brando.Users.User.__schema__(:prefix) == "public"
    assert Brando.Users.UserToken.__schema__(:prefix) == "public"
  end
end
