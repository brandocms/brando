defmodule Brando.Translations.PairingTest do
  # Linking fragments that share their keys as each other's language
  # versions: `Brando.Translations.Pairing` and `mix brando.fragments.pair`
  use Brando.ConnCase, async: false

  import Brando.MigrationTemplates, only: [provision: 1, rows: 2, query!: 2]
  import ExUnit.CaptureIO
  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Pages.Fragment
  alias Brando.Repo
  alias Brando.Translations.Pairing

  defp fragment!(language, key, attrs \\ []),
    do: Factory.insert(:fragment, Keyword.merge([parent_key: "footer", key: key, language: language], attrs))

  defp links,
    do:
      Repo.all(
        from(a in Fragment.Alternate, select: {a.entry_id, a.linked_entry_id}, order_by: [:entry_id, :linked_entry_id])
      )

  defp status(plan, key), do: Enum.find_value(plan, &(&1.values == ["footer", key] && &1.status))

  defp both_ways(ids), do: Enum.sort(for a <- ids, b <- ids, a != b, do: {a, b})

  test "plans every key, and links only the ones it can, in one go and once" do
    no = fragment!(:no, "contact")
    en = fragment!(:en, "contact")
    only = fragment!(:no, "hours")
    twin_a = fragment!(:no, "address")
    twin_b = fragment!(:no, "address")
    fragment!(:en, "address")
    fragment!(:en, "trashed", deleted_at: DateTime.utc_now())
    fragment!(:no, "trashed")

    plan = Pairing.plan(Fragment)
    assert links() == []

    assert status(plan, "contact") == :link
    assert status(plan, "hours") == :one_language
    assert status(plan, "address") == :same_language
    # A fragment in the trash is no candidate
    assert status(plan, "trashed") == :one_language

    assert for(%{language: "no", id: id} <- Enum.find(plan, &(&1.values == ["footer", "address"])).entries, do: id) ==
             [twin_a.id, twin_b.id]

    assert [%{values: ["footer", "contact"], status: :linked}] = Pairing.apply(Fragment, plan)
    assert links() == both_ways([no.id, en.id])
    refute Enum.any?(links(), fn {a, b} -> only.id in [a, b] end)

    # A second run changes nothing
    plan = Pairing.plan(Fragment)
    assert status(plan, "contact") == :linked
    assert Pairing.apply(Fragment, plan) == []
    assert links() == both_ways([no.id, en.id])
  end

  test "completes a link left one way, and links three languages as one group" do
    no = fragment!(:no, "contact")
    en = fragment!(:en, "contact")
    # A language the site no longer lists still counts
    de = fragment!(:no, "contact")
    query!("UPDATE pages_fragments SET language = 'de' WHERE id = $1", [de.id])
    Repo.insert!(%Fragment.Alternate{entry_id: no.id, linked_entry_id: en.id})

    assert [%{status: :link, missing: missing}] = Pairing.plan(Fragment)
    assert length(missing) == 5

    assert [%{status: :linked}] = Pairing.apply(Fragment, Pairing.plan(Fragment))
    assert links() == both_ways([no.id, en.id, de.id])
  end

  test "never extends a link that disagrees" do
    no = fragment!(:no, "contact")
    fragment!(:en, "contact")
    other = fragment!(:en, "help")
    Repo.insert!(%Fragment.Alternate{entry_id: no.id, linked_entry_id: other.id})
    Repo.insert!(%Fragment.Alternate{entry_id: other.id, linked_entry_id: no.id})

    plan = Pairing.plan(Fragment)

    assert Enum.map(plan, &{&1.values, &1.links}) == [
             {["footer", "contact"], links()},
             {["footer", "help"], links()}
           ]

    assert status(plan, "contact") == :linked_elsewhere
    assert Pairing.apply(Fragment, plan) == []
    assert links() == Enum.sort([{no.id, other.id}, {other.id, no.id}])
  end

  describe "a candidate changed between the plan and the apply" do
    setup do
      %{no: fragment!(:no, "contact"), en: fragment!(:en, "contact"), plan: nil}
      |> then(&Map.put(&1, :plan, Pairing.plan(Fragment)))
    end

    test "renamed", c do
      c.en |> Ecto.Changeset.change(key: "kontakt") |> Repo.update!()
      assert [%{status: :changed}] = Pairing.apply(Fragment, c.plan)
      assert links() == []
    end

    test "trashed", c do
      c.en |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()
      assert [%{status: :changed}] = Pairing.apply(Fragment, c.plan)
      assert links() == []
    end

    test "linked by an editor", c do
      other = fragment!(:en, "help")
      :ok = Fragment.Alternate.add(c.no.id, other.id)

      assert [%{status: :changed}] = Pairing.apply(Fragment, c.plan)
      assert links() == Enum.sort([{c.no.id, other.id}, {other.id, c.no.id}])
    end

    test "joined by another fragment with the keys", c do
      fragment!(:en, "contact")
      assert [%{status: :changed}] = Pairing.apply(Fragment, c.plan)
      assert links() == []
    end
  end

  # Edge case 8: same ids and keys in two environments, synchronized in one
  test "links only the named environment's fragments" do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(Fragment, translatable: [mode: :independent], translatable_sites: %{"acme" => [mode: :synchronized]})
    environments = ["tenant_acme_production", "tenant_other_production"]

    for prefix <- environments do
      provision(prefix)

      for {id, language} <- [{1, "no"}, {2, "en"}] do
        query!(
          ~s{INSERT INTO "#{prefix}".pages_fragments (id, parent_key, key, language, inserted_at, updated_at)
             VALUES ($1, 'footer', 'contact', $2, now(), now())},
          [id, language]
        )
      end
    end

    linked = fn prefix ->
      rows(~s{SELECT entry_id, linked_entry_id FROM "#{prefix}".pages_fragments_alternates ORDER BY 1}, [])
    end

    Brando.Tenant.with_prefix("tenant_acme_production", fn ->
      assert [%{status: :linked}] = Pairing.apply(Fragment, Pairing.plan(Fragment))
    end)

    assert linked.("tenant_acme_production") == [[1, 2], [2, 1]]
    assert linked.("tenant_other_production") == []
    assert rows("SELECT count(*) FROM public.pages_fragments_alternates", []) == [[0]]
  end

  describe "mix brando.fragments.pair" do
    # The shell is global, and tests that run side by side can leave it
    # switched to the one that sends messages, which prints nothing
    setup do
      shell = Mix.shell()
      Mix.shell(Mix.Shell.IO)
      on_exit(fn -> Mix.shell(shell) end)
    end

    test "lists without --apply, and links with it" do
      no = fragment!(:no, "contact")
      en = fragment!(:en, "contact")
      fragment!(:no, "address")
      fragment!(:no, "address")

      output = capture_io(fn -> Mix.Tasks.Brando.Fragments.Pair.run([]) end)
      assert output =~ "footer/contact: en ##{en.id}, no ##{no.id}"
      assert output =~ "footer/address"
      assert output =~ "--apply"
      assert links() == []

      output = capture_io(fn -> Mix.Tasks.Brando.Fragments.Pair.run(["--apply"]) end)
      assert output =~ "Linked 1 key(s)"
      assert links() == both_ways([no.id, en.id])

      output = capture_io(fn -> Mix.Tasks.Brando.Fragments.Pair.run(["--apply"]) end)
      assert output =~ "Already linked: 1 key(s)"
      assert output =~ "Linked 0 key(s)"
    end

    test "rejects a fragment key before applying the plan" do
      fragment!(:no, "contact")
      fragment!(:en, "contact")

      assert_raise Mix.Error, ~r/unexpected argument footer\/address/, fn ->
        Mix.Tasks.Brando.Fragments.Pair.run(["--apply", "footer/address"])
      end

      assert links() == []
    end

    test "takes a site and an environment only in tenant mode" do
      assert_raise Mix.Error, ~r/tenant mode/, fn ->
        Mix.Tasks.Brando.Fragments.Pair.run(["--site", "acme", "--environment", "production"])
      end
    end
  end

  # A Mix task names `Brando.Pages.Fragment` before anything has loaded it;
  # a module compiled to disk and not loaded stands in for it here.
  @tag :tmp_dir
  test "matched_by/1 reads a schema that is not loaded yet", %{tmp_dir: dir} do
    module = Module.concat(__MODULE__, "Unloaded#{System.unique_integer([:positive])}")

    [{^module, beam}] =
      Code.compile_quoted(
        quote do
          defmodule unquote(module) do
            def __translatable_matched_by__, do: [:parent_key, :key]
          end
        end
      )

    File.write!(Path.join(dir, "#{module}.beam"), beam)
    :code.delete(module)
    :code.purge(module)
    Code.prepend_path(dir)
    on_exit(fn -> Code.delete_path(dir) end)

    refute :code.is_loaded(module)
    assert Brando.Translations.matched_by(module) == [:parent_key, :key]
  end
end
