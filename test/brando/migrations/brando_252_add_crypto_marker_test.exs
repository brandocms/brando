defmodule Brando.Migrations.Brando252AddCryptoMarkerTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates,
    only: [column_definitions: 2, down: 2, indexes: 2, query!: 1, table?: 2, up: 1]

  @file_name "brando_252_add_crypto_marker.exs"

  test "creates the one-row marker table in public, and rolls back" do
    expected = column_definitions("public", "crypto_marker")
    expected_indexes = indexes("public", "crypto_marker")
    query!("DROP TABLE public.crypto_marker")

    version = up(@file_name)

    assert column_definitions("public", "crypto_marker") == expected
    assert indexes("public", "crypto_marker") == expected_indexes
    assert Brando.Tenant.SharedTables.member?("crypto_marker")
    # It starts empty: the running application writes it
    assert Repo.aggregate(Brando.Crypto.Marker, :count) == 0

    assert_raise Postgrex.Error, ~r/crypto_marker_one_row/, fn ->
      Repo.transaction(
        fn ->
          query!(
            "INSERT INTO public.crypto_marker (id, value, host, inserted_at, updated_at) VALUES (2, '', '', now(), now())"
          )
        end,
        mode: :savepoint
      )
    end

    down(@file_name, version)

    refute table?("public", "crypto_marker")
  end
end
