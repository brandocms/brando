defmodule Brando.SSGSSHFixtures do
  @moduledoc """
  A site's SSH files for tests of rsync deploys (`Brando.SSG.SSH`): a key
  file, accepted host keys and a reviewed target
  (`Brando.SSG.TargetReview`), written as `Brando.SSG.DeployFiles` keeps
  them, so a deploy with a fake runner gets past its checks.
  """

  alias Brando.SSG.DeployFiles

  @host_key "AAAAC3NzaC1lZDI1NTE5AAAAIMRFzTKqWAU2MmY9UVN3ZoZSvU9eRSHMLtR+ApYIr5Ru"
  @other_host_key "AAAAC3NzaC1lZDI1NTE5AAAAII1D6qhw+zPShuc4dGscFyEo7378HljjgkBL5vOOfNfT"

  @doc "An ed25519 host key's base64 data, and another's."
  def host_key, do: @host_key
  def other_host_key, do: @other_host_key

  @doc "A line as `ssh-keyscan` prints it for `entry` (`host` or `[host]:port`)."
  def keyscan_line(entry, data \\ @host_key), do: "#{entry} ssh-ed25519 #{data}"

  @doc """
  Gives `site` a key file and accepts the host key for each of `entries`
  (`host` on port 22, or `[host]:port`). The key file is not a key: a
  deploy with a fake runner only looks for it.
  """
  def trust_hosts(site, entries) do
    :ok = DeployFiles.write(site, :key, "not a key\n")
    :ok = DeployFiles.write(site, :known_hosts, Enum.map(entries, &[keyscan_line(&1), "\n"]))
    site
  end

  @doc """
  An editor of `site` in a group with the publishing `capability` (a name
  such as `"brando.publishing.build"`), made by `superuser`, for tests with
  capabilities on.
  """
  def publishing_member(site, superuser, capability) do
    user = Brando.Factory.insert(:random_user, role: :editor)
    {:ok, _} = Brando.Tenant.Access.grant(user, site, :editor)
    scope = Brando.Authorization.Scope.site(superuser, site)

    {:ok, group} =
      Brando.Authorization.Groups.create(
        scope,
        %{name: "Publishing #{System.unique_integer([:positive])}"},
        ["brando.admin.access", "brando.publishing.read", capability]
      )

    {:ok, :ok} = Brando.Authorization.Groups.add_member(scope, group.id, user.id)
    user
  end

  @doc """
  Writes `site`'s target state as reviewed for `target` on `port`, with the
  host keys it accepted there and nothing uploaded or confirmed. Accept the
  host first (`trust_hosts/2`).
  """
  def review_target(site, target, port \\ 22) do
    keys = site |> Brando.SSG.SSH.accepted_keys(target, port) |> Enum.map(&{&1.type, &1.data}) |> Enum.sort()
    state = %{target: target, port: port, host_keys: keys, reviewed: true, uploaded: [], confirmed: [], found: nil}
    :ok = DeployFiles.write(site, :target_state, :erlang.term_to_binary(state))
    site
  end
end
