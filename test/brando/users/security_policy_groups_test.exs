defmodule Brando.Users.SecurityPolicyGroupsTest do
  # Groups authorization is an application setting, so this runs alone.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Authorization.Group
  alias Brando.Authorization.Migration
  alias Brando.Factory
  alias Brando.Users
  alias Brando.Users.SecurityPolicy
  alias Brando.Users.TwoFactor

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    owner = Factory.insert(:random_user, role: :superuser)
    editor = Factory.insert(:random_user, role: :editor)
    user = Factory.insert(:random_user, role: :user)
    {:ok, _} = Migration.run()

    secret = TwoFactor.new_secret()
    {:ok, _codes} = TwoFactor.enable(owner, secret, TwoFactor.current_code(secret), proof: "admin")

    %{owner: owner, editor: editor, user: user}
  end

  test "with groups authorization, the policy names groups", %{owner: owner, editor: editor, user: user} do
    assert Users.superuser?(owner)
    refute Users.superuser?(editor)

    editors = Repo.one!(from g in Group, where: g.preset == :editor, limit: 1)

    assert {:ok, _} =
             SecurityPolicy.update(
               %{"two_factor" => "selected", "two_factor_group_ids" => [to_string(editors.id)]},
               owner
             )

    assert TwoFactor.required?(editor)
    refute TwoFactor.required?(user)
    # Roles do not count with groups authorization
    {:ok, _} =
      SecurityPolicy.update(
        %{"two_factor" => "selected", "two_factor_roles" => ["user"], "two_factor_group_ids" => []},
        owner
      )

    refute TwoFactor.required?(user)
    assert SecurityPolicy.without_two_factor_count(SecurityPolicy.get()) == 0
  end

  test "only an installation superuser saves it", %{editor: editor} do
    assert {:error, :forbidden} = SecurityPolicy.update(%{"two_factor" => "everyone"}, editor)
  end
end
