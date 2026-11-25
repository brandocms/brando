defmodule Brando.SSGSSHFixtures do
  @moduledoc """
  A site's SSH files for tests of rsync deploys (`Brando.SSG.SSH`): a key
  file and accepted host keys, written as `Brando.SSG.DeployFiles` keeps
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
end
