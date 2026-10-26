defmodule Brando.Sites.DeployConfigTest do
  # An rsync deploy mirrors the build with --delete, as the server's user and
  # SSH identity, to the target anyone who may deploy can set. It takes only
  # a remote [user@]host:/absolute/path, on a host the operator allows.
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Sites.DeployConfig

  defp rsync(target), do: DeployConfig.changeset(%DeployConfig{}, %{strategy: :rsync, target: target})

  test "a remote destination is a valid rsync target" do
    for target <- [
          "deploy@example.com:/srv/www",
          "example.com:/srv/www/",
          "web_1@static-01.example.com:/var/www/site.example.com/public",
          "deploy@10.0.0.5:/srv/www",
          "deploy@[2001:db8::1]:/srv/www"
        ] do
      assert rsync(target).valid?, target
      assert DeployConfig.valid_rsync_target?(target)
    end
  end

  test "local paths, options and other rsync syntax are refused" do
    for target <- [
          # The audit's three: a local directory, an rsync option, an ssh option as the host
          "/tmp/local-dest",
          "--log-file=/tmp/marker.log",
          "u@-oProxyCommand=true:/srv/www",
          "-oProxyCommand=true:/srv/www",
          "-e@example.com:/srv/www",
          "relative/dir",
          "./here",
          "example.com:relative",
          "example.com::module",
          "rsync://example.com/module",
          "deploy@example.com:/srv/www; touch /tmp/x",
          "deploy@example.com:/srv/$(id)",
          "deploy@example.com:/srv/www\n",
          "deploy@example.com:/srv/w w",
          "user@name@example.com:/srv"
        ] do
      refute rsync(target).valid?, inspect(target)
      refute DeployConfig.valid_rsync_target?(target)
    end
  end

  test "an operator's host list limits where rsync deploys go" do
    put_test_env(DeployConfig, rsync_hosts: ["static.example.com"])

    assert rsync("deploy@Static.Example.com:/srv/www").valid?
    refute rsync("deploy@other.example.com:/srv/www").valid?
  end
end
