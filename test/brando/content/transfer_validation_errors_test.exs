defmodule Brando.Content.TransferValidationErrorsTest do
  # The preview's "Entry validation" problem names each field under its
  # label. A field with no input in the form (a page's expiry is set in the
  # status drawer) goes by its humanized name, without a complaint about the
  # form in the log.
  use Brando.ConnCase, async: false

  import ExUnit.CaptureLog, only: [capture_log: 1]

  alias Brando.Content.Transfer
  alias Brando.Factory
  alias Brando.Pages.Page

  test "a field outside the form is named without logging" do
    user = Factory.insert(:random_user)
    publish_at = DateTime.utc_now() |> DateTime.add(2, :day) |> DateTime.truncate(:second)
    unpublish_at = DateTime.add(publish_at, -1, :day)
    page = Factory.insert(:page, creator: user, publish_at: publish_at, unpublish_at: unpublish_at)

    assert {:ok, exported} = Transfer.export([%{schema: Page, id: page.id}], user, media: false)
    assert {:ok, archive} = Transfer.read(exported.binary)
    key = Enum.find(archive.bundle["entries"], &(&1["schema"] == to_string(Page)))["key"]
    target = %{"mode" => "create", "publication" => "source", "attributes" => %{"uri" => "copy-#{page.id}"}}

    log =
      capture_log(fn ->
        assert {:ok, plan} = Transfer.preview(archive, %{key => target}, user)
        assert Enum.any?(plan.problems, &(&1 =~ "Unpublish at: Must be after the publishing date"))
      end)

    refute log =~ "Could not get field"
  end
end
