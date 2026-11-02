defmodule Brando.Content.Proposals.LockedFieldsTest do
  # A proposal writes no field the forms lock for anyone but a superuser
  # (`LockedFields.held_keys/2`), in either authorization mode, as a transfer
  # bundle doesn't. Only its author can approve and apply a proposal, and each
  # checks again, so the author's role decides.
  use Brando.ConnCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.{Codec, CreateEntry, SetFields, Tools}
  alias Brando.Factory
  alias Brando.LockedProposalTest.Note
  alias Brando.Test.Users

  @group ~w(brando.admin.access brando.locked_proposal_test.note.create brando.locked_proposal_test.note.read
            brando.locked_proposal_test.note.update brando.locked_proposal_test.note.publish)

  defp editor(:legacy), do: Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})

  defp editor(:groups) do
    user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    scope = Scope.standalone(Repo.one!(from u in Brando.Users.User, where: u.role == :superuser, limit: 1))
    {:ok, group} = Groups.create(scope, %{name: "Note editors"}, @group)
    {:ok, :ok} = Groups.add_member(scope, group.id, user.id)
    user
  end

  defp put_mode(:legacy), do: %{superuser: Users.insert_user(role: :superuser)}

  defp put_mode(:groups) do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    superuser = Users.insert_user(role: :superuser)
    {:ok, _} = Migration.run()
    %{superuser: superuser}
  end

  defp note do
    Repo.insert!(%Note{
      title: "Saved",
      slug: "saved-#{System.unique_integer([:positive])}",
      subtitle: "Stored",
      year: 2020,
      status: :draft
    })
  end

  defp codes(proposal), do: Enum.map(proposal.problems, & &1.code)

  defp approve_and_apply(proposal, user) do
    with {:ok, _} <- Proposals.approve(proposal.id, proposal.version, user),
         do: Proposals.apply(proposal.id, proposal.version, user)
  end

  for mode <- [:legacy, :groups] do
    describe "#{mode}:" do
      setup do
        put_mode(unquote(mode))
      end

      test "a non-superuser's change of a locked field is refused, and nothing written" do
        user = editor(unquote(mode))
        note = note()
        ops = [%SetFields{target: {Note, note.id}, fields: %{subtitle: "Proposed", title: "Proposed"}}]

        assert {:ok, proposal} = Proposals.propose(ops, user)
        assert codes(proposal) == [:protected_field]
        assert {:error, _} = approve_and_apply(proposal, user)
        assert Repo.get!(Note, note.id).subtitle == "Stored"
      end

      test "a status a form locks is refused too" do
        user = editor(unquote(mode))

        assert {:ok, proposal} =
                 Proposals.prepare([%SetFields{target: {Note, note().id}, fields: %{status: "disabled"}}], user)

        assert :protected_field in codes(proposal)
      end

      test "a non-superuser's new entry can't name one" do
        user = editor(unquote(mode))
        ops = [%CreateEntry{schema: Note, ref: "new", fields: %{title: "New", subtitle: "Proposed"}}]

        assert {:ok, proposal} = Proposals.prepare(ops, user)
        assert codes(proposal) == [:protected_field]
      end

      # What it can't name, it gets as a form's new entry does, in the review's
      # preview and in the save.
      test "a non-superuser's new entry takes the locked fields' defaults and derived slug" do
        user = editor(unquote(mode))
        ops = [%CreateEntry{schema: Note, ref: "new", fields: %{title: "Første notat"}}]

        assert {:ok, proposal} = Proposals.propose(ops, user)
        assert proposal.problems == []

        assert {:ok, %{{:new, "new"} => changeset}} = Proposals.materialize(proposal, user)
        assert Ecto.Changeset.get_field(changeset, :slug) == "forste-notat"

        assert {:ok, _} = approve_and_apply(proposal, user)

        saved = Repo.get_by!(Note, title: "Første notat")
        assert {saved.slug, saved.subtitle, saved.year, saved.status} == {"forste-notat", "Standard", 2024, :draft}
      end

      test "a non-superuser's other fields still go through" do
        user = editor(unquote(mode))
        note = note()

        assert {:ok, proposal} =
                 Proposals.propose([%SetFields{target: {Note, note.id}, fields: %{title: "Proposed"}}], user)

        assert proposal.problems == []
        assert {:ok, _} = approve_and_apply(proposal, user)

        saved = Repo.get!(Note, note.id)
        assert {saved.title, saved.subtitle} == {"Proposed", "Stored"}
      end

      test "a superuser's proposal still writes one", %{superuser: user} do
        note = note()

        assert {:ok, proposal} =
                 Proposals.propose([%SetFields{target: {Note, note.id}, fields: %{subtitle: "Proposed"}}], user)

        assert proposal.problems == []
        assert {:ok, _} = approve_and_apply(proposal, user)
        assert Repo.get!(Note, note.id).subtitle == "Proposed"
      end

      test "a superuser's new entry can name one", %{superuser: user} do
        ops = [%CreateEntry{schema: Note, ref: "new", fields: %{title: "New", subtitle: "Proposed"}}]

        assert {:ok, proposal} = Proposals.prepare(ops, user)
        refute :protected_field in codes(proposal)
      end
    end
  end

  # A form's default doesn't reach a superuser, who can name the field
  test "a superuser's new entry still has to name a required locked field" do
    %{superuser: user} = put_mode(:legacy)
    ops = [%CreateEntry{schema: Note, ref: "new", fields: %{title: "New"}}]

    assert {:ok, proposal} = Proposals.prepare(ops, user)
    assert codes(proposal) == [:invalid]
  end

  # The review is of what its author would save, whoever reads it
  test "a colleague's preview of a new entry holds what its author's role holds" do
    %{superuser: superuser} = put_mode(:legacy)
    user = editor(:legacy)

    by_editor = [%CreateEntry{schema: Note, ref: "new", fields: %{title: "From an editor"}}]
    assert {:ok, proposal} = Proposals.prepare(by_editor, user)
    assert proposal.problems == []
    assert {:ok, %{{:new, "new"} => changeset}} = Proposals.materialize(proposal, superuser, shared: true)
    assert Ecto.Changeset.get_field(changeset, :slug) == "from-an-editor"

    named = %{title: "From a superuser", slug: "named", subtitle: "Named", year: 1999}
    assert {:ok, proposal} = Proposals.prepare([%CreateEntry{schema: Note, ref: "new", fields: named}], superuser)
    assert proposal.problems == []
    assert {:ok, %{{:new, "new"} => changeset}} = Proposals.materialize(proposal, user, shared: true)
    assert Ecto.Changeset.get_field(changeset, :slug) == "named"
    assert Ecto.Changeset.get_field(changeset, :subtitle) == "Named"
  end

  describe "describe_content_type" do
    defp described(user) do
      {:ok, %{fields: fields} = described} =
        Tools.call("describe_content_type", %{"content_type" => Codec.content_type(Note)}, %Tools.Context{actor: user})

      {Enum.map(fields, & &1.name), described}
    end

    test "leaves out for a non-superuser what a proposal may not name" do
      put_mode(:legacy)
      {names, _} = described(editor(:legacy))

      assert "title" in names
      assert names -- ~w(slug subtitle year status) == names
    end

    test "lists it for a superuser" do
      %{superuser: user} = put_mode(:legacy)
      {names, _} = described(user)

      assert ~w(slug status subtitle title year) -- names == []
    end
  end

  # A stored proposal is checked again at apply, on the role as it is then
  test "a proposal its author lost the superuser role since can't be applied" do
    %{superuser: user} = put_mode(:legacy)
    note = note()

    assert {:ok, proposal} =
             Proposals.propose([%SetFields{target: {Note, note.id}, fields: %{subtitle: "Proposed"}}], user)

    assert {:ok, _} = Proposals.approve(proposal.id, proposal.version, user)

    demoted = user |> Ecto.Changeset.change(role: :editor) |> Repo.update!()

    assert {:error, _} = Proposals.apply(proposal.id, proposal.version, demoted)
    assert Repo.get!(Note, note.id).subtitle == "Stored"
  end

  test "a superuser can't approve an editor's proposal for them" do
    %{superuser: reviewer} = put_mode(:legacy)
    note = note()

    assert {:ok, proposal} =
             Proposals.propose([%SetFields{target: {Note, note.id}, fields: %{subtitle: "Proposed"}}], editor(:legacy))

    assert {:error, message} = Proposals.approve(proposal.id, proposal.version, reviewer)
    assert message =~ "another user"
    assert Repo.get!(Note, note.id).subtitle == "Stored"
  end
end
