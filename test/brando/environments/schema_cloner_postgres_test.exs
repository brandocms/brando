defmodule Brando.Environments.SchemaCloner.PostgresTest do
  use ExUnit.Case, async: true

  alias Brando.Environments.SchemaCloner.Postgres

  test "rewrites only the source schema's quoted identifier" do
    dump = """
    CREATE SCHEMA "tenant_acme_staging";
    CREATE TABLE "tenant_acme_staging"."pages" ("id" bigint);
    INSERT INTO "tenant_acme_staging"."pages" VALUES (1);
    """

    assert {:ok, rewritten} =
             Postgres.rewrite_schema(
               dump,
               "tenant_acme_staging",
               "tenant_acme_preview"
             )

    refute rewritten =~ ~s|"tenant_acme_staging"|
    assert rewritten =~ ~s|CREATE SCHEMA "tenant_acme_preview"|
    assert rewritten =~ ~s|"tenant_acme_preview"."pages"|
  end

  test "refuses a dump that does not contain the exact source identifier" do
    assert {:error, {:source_schema_not_found_in_dump, "tenant_acme_staging"}} =
             Postgres.rewrite_schema(
               ~s|CREATE SCHEMA "public";|,
               "tenant_acme_staging",
               "tenant_acme_preview"
             )
  end

  test "does not rewrite schema-like values inside COPY data" do
    dump = """
    CREATE SCHEMA "tenant_acme_staging";
    COPY "tenant_acme_staging"."records" ("value") FROM stdin;
    "tenant_acme_staging"
    \\.
    ALTER TABLE "tenant_acme_staging"."records" OWNER TO "postgres";
    """

    assert {:ok, rewritten} =
             Postgres.rewrite_schema(dump, "tenant_acme_staging", "tenant_acme_preview")

    assert rewritten =~ ~s|COPY "tenant_acme_preview"."records"|
    assert rewritten =~ ~s|\n"tenant_acme_staging"\n\\.|
    assert rewritten =~ ~s|ALTER TABLE "tenant_acme_preview"."records"|
  end
end
