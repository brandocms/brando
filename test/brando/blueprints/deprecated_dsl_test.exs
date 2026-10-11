defmodule Brando.Blueprint.DeprecatedDslTest do
  # Captures the compiler's stderr, which is global.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO, only: [capture_io: 2]

  test "a legacy listing field or template warns at its own line and says the change is manual" do
    unique = System.unique_integer([:positive])

    source = """
    defmodule Brando.Blueprint.DeprecatedDslTest.Legacy#{unique} do
      use Brando.Blueprint,
        application: "Brando",
        domain: "DeprecatedDslTest",
        schema: "Legacy#{unique}",
        singular: "legacy",
        plural: "legacies",
        gettext_module: Brando.Gettext

      listings do
        listing do
          field :title, :string, columns: 4
          template "{{ entry.title }}", columns: 6
        end
      end
    end
    """

    stderr = capture_io(:stderr, fn -> Code.compile_string(source, "lib/legacy_listing.ex") end)

    assert stderr =~ "field/3 in a listing is no longer supported"
    assert stderr =~ "template/2 in a listing is no longer supported"
    assert stderr =~ "lib/legacy_listing.ex:12"
    assert stderr =~ "lib/legacy_listing.ex:13"
    assert stderr =~ "guides/blueprint_listings.md#rows"
    refute stderr =~ "Migrate with mix brando.migrate54"
  end

  test "syntax mix brando.migrate54 rewrites still points at the task, with the line" do
    unique = System.unique_integer([:positive])

    source = """
    defmodule Brando.Blueprint.DeprecatedDslTest.Query#{unique} do
      use Brando.Blueprint,
        application: "Brando",
        domain: "DeprecatedDslTest",
        schema: "Query#{unique}",
        singular: "query",
        plural: "queries",
        gettext_module: Brando.Gettext

      listings do
        listing do
          listing_query %{status: :published}
        end
      end
    end
    """

    stderr = capture_io(:stderr, fn -> Code.compile_string(source, "lib/legacy_query.ex") end)

    assert stderr =~ "listing_query/1 is deprecated"
    assert stderr =~ "mix brando.migrate54"
    assert stderr =~ "lib/legacy_query.ex:12"
  end
end
