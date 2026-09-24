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

  defp row(overrides \\ %{}) do
    struct(
      Row,
      Map.merge(
        %{
          title: "Entry",
          url: "/entry",
          meta_title: "A good meta title for this entry, in range",
          meta_description: String.duplicate("x", 140)
        },
        overrides
      )
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
