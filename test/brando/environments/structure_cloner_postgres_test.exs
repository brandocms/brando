defmodule Brando.Environments.StructureClonerPostgresTest do
  # Not async: the shared-table configuration test mutates application env.
  use ExUnit.Case, async: false

  alias Brando.Environments.StructureCloner.Postgres, as: Cloner
  alias Brando.Tenant.SharedTables

  @target "tenant_acme_production"

  describe "rewrite/4" do
    test "requalifies tenant objects into the target schema" do
      dump = ~s|CREATE TABLE "public"."pages" ("id" bigint NOT NULL);|

      assert {:ok, rewritten} = Cloner.rewrite(dump, "public", @target, ["pages"])
      assert rewritten == ~s|CREATE TABLE "#{@target}"."pages" ("id" bigint NOT NULL);|
    end

    test "keeps foreign keys to shared tables pointing at the source schema" do
      dump = """
      ALTER TABLE ONLY "public"."pages"
        ADD CONSTRAINT "pages_creator_id_fkey" FOREIGN KEY ("creator_id")
        REFERENCES "public"."users"("id");
      """

      assert {:ok, rewritten} = Cloner.rewrite(dump, "public", @target, ["pages"])
      assert rewritten =~ ~s|ALTER TABLE ONLY "#{@target}"."pages"|
      assert rewritten =~ ~s|REFERENCES "public"."users"("id")|
      refute rewritten =~ ~s|REFERENCES "#{@target}"."users"|
    end

    test "requalifies sequences the dump declares" do
      dump = """
      CREATE SEQUENCE "public"."pages_id_seq";
      ALTER TABLE ONLY "public"."pages" ALTER COLUMN "id"
        SET DEFAULT "nextval"('"public"."pages_id_seq"'::"regclass");
      """

      assert {:ok, rewritten} = Cloner.rewrite(dump, "public", @target, ["pages"])
      assert rewritten =~ ~s|CREATE SEQUENCE "#{@target}"."pages_id_seq"|
      assert rewritten =~ ~s|'"#{@target}"."pages_id_seq"'|
      refute rewritten =~ ~s|"public"."pages_id_seq"|
    end

    test "leaves an enum type in the source schema" do
      dump = ~s|CREATE TABLE "public"."posts" ("state" "public"."post_state" NOT NULL);|

      assert {:ok, rewritten} = Cloner.rewrite(dump, "public", @target, ["posts"])
      assert rewritten =~ ~s|CREATE TABLE "#{@target}"."posts"|
      assert rewritten =~ ~s|"public"."post_state"|
      refute rewritten =~ ~s|"#{@target}"."post_state"|
    end

    test "leaves an extension type in the source schema" do
      dump = ~s|CREATE TABLE "public"."persons" ("email" "public"."citext");|

      assert {:ok, rewritten} = Cloner.rewrite(dump, "public", @target, ["persons"])
      assert rewritten =~ ~s|"public"."citext"|
      refute rewritten =~ ~s|"#{@target}"."citext"|
    end

    test "leaves a trigger function in the source schema" do
      dump = ~s|CREATE TRIGGER "t" BEFORE INSERT ON "public"."pages" EXECUTE FUNCTION "public"."touch"();|

      assert {:ok, rewritten} = Cloner.rewrite(dump, "public", @target, ["pages"])
      assert rewritten =~ ~s|ON "#{@target}"."pages"|
      assert rewritten =~ ~s|FUNCTION "public"."touch"()|
    end

    test "leaves every oban table in the source schema" do
      dump = ~s|CREATE UNLOGGED TABLE "public"."oban_peers" ("name" text);|

      assert {:ok, rewritten} = Cloner.rewrite(dump, "public", @target, ["pages"])
      assert rewritten == dump
    end

    test "rewrites references between two tenant tables" do
      dump = ~s|REFERENCES "public"."content_blocks"("id")|

      assert {:ok, rewritten} =
               Cloner.rewrite(dump, "public", @target, ["pages", "content_blocks"])

      assert rewritten == ~s|REFERENCES "#{@target}"."content_blocks"("id")|
    end
  end

  describe "clone_structure/2" do
    test "rejects a target prefix that is not a safe identifier" do
      assert {:error, {:invalid_schema_identifier, "tenant_acme; DROP SCHEMA public"}} =
               Cloner.clone_structure("public", "tenant_acme; DROP SCHEMA public")
    end
  end

  describe "shared table classification" do
    test "pins registry, auth, and job tables to public" do
      for table <- ~w(users users_tokens sites environments oban_jobs oban_peers schema_migrations) do
        assert SharedTables.member?(table), "expected #{table} to be shared"
      end
    end

    test "treats content tables as tenant-scoped" do
      for table <- ~w(pages content_blocks images sites_identities sites_seos revisions) do
        refute SharedTables.member?(table), "expected #{table} to be tenant-scoped"
      end
    end

    test "splits a table list into tenant and shared" do
      assert {["pages", "images"], ["users", "oban_peers"]} =
               SharedTables.split(["pages", "users", "images", "oban_peers"])
    end

    test "honours application-declared shared tables" do
      refute SharedTables.member?("billing_accounts")

      previous = Application.get_env(:brando, :shared_tables)
      Application.put_env(:brando, :shared_tables, ["billing_accounts"])
      on_exit(fn -> Application.put_env(:brando, :shared_tables, previous) end)

      assert SharedTables.member?("billing_accounts")
      assert "billing_accounts" in SharedTables.all()
      refute "billing_accounts" in SharedTables.list()
      refute SharedTables.member?("pages")
    end
  end
end
