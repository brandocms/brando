defmodule Mix.Tasks.Brando.CreateadminTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  alias Brando.Users.Model.User

  import ExUnit.CaptureIO

  test "brando.createadmin succeeds" do
    cap = capture_io(fn -> Mix.Tasks.Brando.Createadmin.run(["--email=my@email.com", "--username=user", "--password=asdf1234", "--fullname=Roger Wilco"]) end)
    assert String.contains?(cap, "Created new admin")
    assert String.contains?(cap, "user")
    assert String.contains?(cap, "my@email.com")
    user = User.get(username: "user")
    assert user
    assert User.is_admin?(user)
  end

  test "brando.createadmin fails" do
    assert_raise KeyError, fn -> Mix.Tasks.Brando.Createadmin.run(["--email=my@email.com", "--username=user", "--fullname=Roger Wilco"]) end
  end

  test "brando.createadmin dupes" do
    assert String.contains?(capture_io(fn -> Mix.Tasks.Brando.Createadmin.run(["--email=my@email.com", "--username=user", "--password=asdf1234", "--fullname=Roger Wilco"]) end), "Created new admin")
    user = User.get(username: "user")
    assert user
    cap = capture_io(fn -> Mix.Tasks.Brando.Createadmin.run(["--email=my@email.com", "--username=user", "--password=asdf1234", "--fullname=Roger Wilco"]) end)
    assert String.contains?(cap, "Error creating admin.")
    assert String.contains?(cap, "[email: :unique]")
  end

  test "brando.createadmin no args" do
    assert_raise Mix.Error, fn -> Mix.Tasks.Brando.Createadmin.run([]) end
  end
end