defmodule Brando.Content.Proposals.FormatMessageTest do
  # A `format_message:` reaches a proposal's problems as it reaches the form.
  # Grouped, one at a time: it takes the authorization lock (Brando.Authorization.Groups.lock!/0),
  # which a test's sandbox transaction holds until the test ends
  use Brando.ConnCase, async: true, group: :shared_locks

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.CreateEntry
  alias Brando.FormatProposalTest.Note
  alias Brando.Test.Users

  defp create(subtitle) do
    user = Users.insert_user(role: :superuser)
    fields = %{title: "New", slug: "new", year: 2024, subtitle: subtitle}

    {:ok, proposal} = Proposals.prepare([%CreateEntry{schema: Note, ref: "new", fields: fields}], user)
    proposal
  end

  test "the format_message is the problem's message" do
    assert [%{code: :invalid, target: {:new, "new"}, message: message}] = create("No full stop").problems
    assert message =~ "ends with a full stop"
    refute message =~ "has invalid format"
  end

  test "a value matching the format is no problem" do
    assert create("A full stop.").problems == []
  end
end
