defmodule Brando.SEO.ChecksTest do
  use ExUnit.Case, async: true

  alias Brando.SEO.Audit.Row
  alias Brando.SEO.Check
  alias Brando.SEO.Checks

  defp ctx(overrides \\ %{}) do
    Map.merge(
      %{
        fallback_title: "Site",
        fallback_description: "Site fallback",
        title_counts: %{},
        description_counts: %{},
        sitemap: nil
      },
      overrides
    )
  end

  # What the page shows is its own meta fields unless a test says otherwise,
  # as when the blueprint falls back to the entry's title or intro.
  defp row(overrides \\ %{}) do
    fields =
      Map.merge(
        %{
          title: "Entry",
          url: "/entry",
          meta_title: "A good meta title for this entry, in range",
          meta_description: String.duplicate("x", 140)
        },
        overrides
      )

    struct(
      Row,
      fields
      |> Map.put_new(:shown_title, fields.meta_title)
      |> Map.put_new(:shown_description, fields.meta_description)
    )
  end

  defp status(checks, key), do: Enum.find(checks, &(&1.key == key)).status

  test "a well-configured entry passes everything that can be checked" do
    checks = Checks.run(row(%{has_meta_image: true}), ctx())
    assert Enum.all?(checks, &(&1.status in [:pass, :skip]))
    assert status(checks, :in_sitemap) == :skip
  end

  test "missing description is critical and its length check is skipped" do
    checks = Checks.run(row(%{meta_description: nil}), ctx())
    assert status(checks, :meta_description_present) == :fail
    assert Enum.find(checks, &(&1.key == :meta_description_present)).weight == :critical
    assert status(checks, :meta_description_length) == :skip
    assert status(checks, :meta_description_not_fallback) == :skip
  end

  # "Not checked" alone reads as something the audit forgot.
  test "every skipped check says why it could not run" do
    bare = row(%{meta_title: nil, meta_description: nil, word_count: nil, headings: nil, alternates: []})

    skipped =
      [Checks.run(bare, ctx(%{search_console?: true})), Checks.run(row(%{image_alts: []}), ctx())]
      |> List.flatten()
      |> Enum.filter(&(&1.status == :skip))

    assert skipped != []
    assert Enum.all?(skipped, &(is_binary(&1.hint) and &1.hint != "")), inspect(Enum.reject(skipped, & &1.hint))
  end

  test "a title the page takes from the entry passes; only the site fallback fails" do
    from_entry = Checks.run(row(%{meta_title: nil, shown_title: "Projects we have made for clients"}), ctx())
    assert status(from_entry, :meta_title_present) == :pass
    assert Enum.find(from_entry, &(&1.key == :meta_title_present)).value
    assert status(from_entry, :meta_title_length) == :pass

    assert status(Checks.run(row(%{meta_title: nil}), ctx()), :meta_title_present) == :fail
  end

  test "a description the page takes from the entry warns rather than fails" do
    intro = String.duplicate("i", 140)
    checks = Checks.run(row(%{meta_description: nil, shown_description: intro}), ctx())

    assert status(checks, :meta_description_present) == :warn
    assert status(checks, :meta_description_length) == :pass
  end

  test "duplicates are counted on what the pages show" do
    checks = Checks.run(row(%{meta_title: nil, shown_title: "Shared"}), ctx(%{title_counts: %{"shared" => 2}}))
    assert status(checks, :duplicate_title) == :fail
  end

  test "lengths outside the display range warn, with the measured value" do
    checks = Checks.run(row(%{meta_title: "Hi", meta_description: String.duplicate("y", 200)}), ctx())
    assert status(checks, :meta_title_length) == :warn
    assert status(checks, :meta_description_length) == :warn
    assert Enum.find(checks, &(&1.key == :meta_description_length)).value == 200
  end

  test "repeating the site fallback description is not a pass" do
    checks = Checks.run(row(%{meta_description: " site FALLBACK "}), ctx())
    assert status(checks, :meta_description_not_fallback) == :fail
  end

  test "a cover image satisfies the image check when there is no meta image" do
    assert status(Checks.run(row(%{cover: "images/cover.jpg"}), ctx()), :meta_image) == :pass
    assert status(Checks.run(row(%{cover: nil}), ctx()), :meta_image) == :fail
  end

  test "duplicates are detected from the language-wide counts" do
    counts = %{Checks.normalize(row().meta_description) => 3}
    checks = Checks.run(row(), ctx(%{description_counts: counts}))
    check = Enum.find(checks, &(&1.key == :duplicate_description))
    assert check.status == :fail
    assert check.value == 3
    assert status(checks, :duplicate_title) == :pass
  end

  test "sitemap membership compares paths, tolerating absolute URLs" do
    sitemap = MapSet.new(["/entry"])
    assert status(Checks.run(row(%{url: "https://x.test/entry"}), ctx(%{sitemap: sitemap})), :in_sitemap) == :pass
    assert status(Checks.run(row(%{url: "/other"}), ctx(%{sitemap: sitemap})), :in_sitemap) == :fail
  end

  test "a description that opens with the title warns; an identical one fails" do
    title = "Guided tours of the old town"
    checks = Checks.run(row(%{meta_title: title, meta_description: title <> " — every day in summer"}), ctx())
    assert status(checks, :title_not_description) == :warn

    checks = Checks.run(row(%{meta_title: title, meta_description: " guided tours of the OLD town "}), ctx())
    assert status(checks, :title_not_description) == :fail
  end

  test "thin content warns under the threshold and fails with no body text at all" do
    ctx = ctx(%{thin_content_words: 300})

    check = Enum.find(Checks.run(row(%{word_count: 120}), ctx), &(&1.key == :thin_content))
    assert check.status == :warn
    assert check.value =~ "120"

    assert status(Checks.run(row(%{word_count: 0}), ctx), :thin_content) == :fail
    assert status(Checks.run(row(%{word_count: 300}), ctx), :thin_content) == :pass
    # No block fields on the schema: nothing to count.
    assert status(Checks.run(row(%{word_count: nil}), ctx), :thin_content) == :skip
  end

  test "the thin content threshold is configurable" do
    previous = Application.get_env(:brando, Brando.SEO)
    Application.put_env(:brando, Brando.SEO, thin_content_words: 50)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:brando, Brando.SEO, previous),
        else: Application.delete_env(:brando, Brando.SEO)
    end)

    assert Checks.thin_content_words() == 50
    assert status(Checks.run(row(%{word_count: 60}), ctx()), :thin_content) == :pass
  end

  test "heading structure warns on several H1s and on skipped levels, counting from the title" do
    assert status(Checks.run(row(%{headings: [2, 3, 3, 2]}), ctx()), :heading_structure) == :pass
    assert status(Checks.run(row(%{headings: nil}), ctx()), :heading_structure) == :skip

    check = Enum.find(Checks.run(row(%{headings: [1, 1, 2]}), ctx()), &(&1.key == :heading_structure))
    assert check.status == :warn
    assert check.hint =~ "2 H1"

    check = Enum.find(Checks.run(row(%{headings: [3, 4, 2, 4]}), ctx()), &(&1.key == :heading_structure))
    assert check.hint =~ "H1 → H3"
    assert check.hint =~ "H2 → H4"
  end

  test "images need alt text that is neither empty, a filename nor a generic word" do
    assert status(Checks.run(row(%{image_alts: ["A ferry leaving Oslo harbour"]}), ctx()), :image_alt) == :pass
    assert status(Checks.run(row(%{image_alts: []}), ctx()), :image_alt) == :skip

    check =
      Enum.find(
        Checks.run(row(%{image_alts: [nil, "", "IMG_2041.jpg", "Bilde", "A real description"]}), ctx()),
        &(&1.key == :image_alt)
      )

    assert check.status == :warn
    assert check.value == "4/5"
    assert check.hint =~ "2 of 5"
  end

  test "language versions are compared for length, images, headings and freshness" do
    other = %{
      id: 2,
      language: "no",
      edited_at: ~N[2026-06-01 00:00:00],
      stats: %Brando.SEO.ContentStats{words: 900, headings: [2, 2, 2, 2], image_alts: ["a", "b", "c"]}
    }

    ok =
      row(%{
        word_count: 800,
        headings: [2, 2, 2],
        image_alts: ["a", "b", "c"],
        edited_at: ~N[2026-05-01 00:00:00],
        alternates: [other]
      })

    assert status(Checks.run(ok, ctx()), :translation_parity) == :pass

    behind = %{ok | word_count: 300, headings: [2], image_alts: ["a"], edited_at: ~N[2026-01-01 00:00:00]}
    check = Enum.find(Checks.run(behind, ctx()), &(&1.key == :translation_parity))

    assert check.status == :warn
    assert check.hint =~ "300"
    assert check.hint =~ "2 fewer images"
    assert check.hint =~ "1 headings, against 4"
    assert check.hint =~ "151 days"

    assert status(Checks.run(row(%{alternates: []}), ctx()), :translation_parity) == :skip
  end

  test "scoring weights failures by importance and ignores skips" do
    all_pass = [%Check{key: :a, status: :pass, weight: :critical, label: "a"}, %Check{key: :b, status: :skip, label: "b"}]
    assert Check.score(all_pass) == 100

    mixed = [
      %Check{key: :a, status: :fail, weight: :critical, label: "a"},
      %Check{key: :b, status: :pass, weight: :low, label: "b"},
      %Check{key: :c, status: :warn, weight: :normal, label: "c"}
    ]

    # 0 + 1 + 1 of 7
    assert Check.score(mixed) == 29
    assert Check.score([]) == nil
  end
end
