defmodule Brando.SSG.SSH do
  @moduledoc """
  How a static site's rsync deploys reach their target: with the site's own
  key pair and the host keys an admin accepted for the target's host and
  port, both kept in its deploy files (`Brando.SSG.DeployFiles`). The server
  user's ssh config, keys, agent and known hosts play no part: every rsync
  to a target runs with `rsync_ssh_args/3`, through `rsync/5`.

  The key pair is ed25519, made with `:public_key` when rsync settings are
  saved for a site that has none (`ensure_key/2`) or when an admin rotates
  it (`rotate_key/2`). Only the private key is kept; the public key shown
  (`public_key/1`) is derived from it, with the comment `brando-<site key>`.
  A rotated key's predecessor stays authorized on a host until someone
  removes it from `authorized_keys` there.

  `test_connection/3` checks the target as a deploy does, fetches the host's
  keys with `ssh-keyscan`, and with accepted keys runs a dry run (`rsync -an`
  from an empty directory, so nothing is sent or deleted).
  `accept_host_keys/3` stores the keys a test showed.

  Each acts for someone who may deploy the site (with capabilities on;
  otherwise who may manage its publishing, `Brando.SSG.Builds.can_manage?/2`),
  on the site's settings as stored.
  Commands run through the deploy's runner (`:runner`, or the `:brando,
  :ssg_deploy_runner` config, `System.cmd/3` by default) with time limits.
  """

  alias Brando.Sites.DeployConfig
  alias Brando.Sites.Site
  alias Brando.SSG.Builds
  alias Brando.SSG.DeployFiles
  alias Brando.Tenant.Lock
  alias Brando.Tenant.Registry

  # Seconds: to connect, for ssh-keyscan's answer, and for rsync's silence
  @connect_timeout 10
  @keyscan_timeout 10
  @test_io_timeout 30
  @deploy_io_timeout 300
  @lock_timeout :timer.seconds(5)

  @remote_output_limit 2_000

  @type host_key :: %{type: String.t(), data: String.t(), fingerprint: String.t()}

  @typedoc """
  What a connection test found: the target and port it tested, the host's
  keys and those accepted for that host and port, whether they are the same
  (`:accepted`), none are accepted (`:new`) or they differ (`:changed`), and
  with accepted keys the dry run's outcome.
  """
  @type test_result :: %{
          target: String.t(),
          port: pos_integer(),
          host_keys: [host_key()],
          accepted_keys: [host_key()],
          host_key_state: :accepted | :new | :changed,
          dry_run: nil | :ok | {:error, term()}
        }

  ## The key

  @doc "The site's public key, one line in OpenSSH form."
  @spec public_key(Site.t()) :: {:ok, String.t()} | {:error, :no_key | :unreadable_key}
  def public_key(%Site{} = site) do
    case DeployFiles.read(site, :key) do
      {:ok, pem} -> derive_public_key(pem, site)
      {:error, :enoent} -> {:error, :no_key}
      {:error, _reason} -> {:error, :unreadable_key}
    end
  end

  # Nothing read from the private key goes into an error
  defp derive_public_key(pem, site) do
    # The private key, and its public half beside it
    [{{:ECPrivateKey, _version, _private, {:namedCurve, _oid}, _public, _attributes} = key, _} | _public_key] =
      :ssh_file.decode(pem, :openssh_key_v1)

    line = :ssh_file.encode([{:ssh_file.extract_public_key(key), [comment: comment(site)]}], :openssh_key)
    {:ok, String.trim_trailing(line)}
  rescue
    _error -> {:error, :unreadable_key}
  catch
    _kind, _error -> {:error, :unreadable_key}
  end

  defp comment(%Site{key: key}), do: "brando-#{key}"

  @doc """
  Makes the site's key pair when it has none, for `actor`. Returns the
  public key.
  """
  @spec ensure_key(Site.t(), term()) :: {:ok, String.t()} | {:error, term()}
  def ensure_key(%Site{} = site, actor) do
    acting(site, actor, fn site -> DeployFiles.with_lock(site, fn -> key_or_new(site) end) end)
  end

  defp key_or_new(site) do
    case public_key(site) do
      {:error, :no_key} -> write_key(site)
      result -> result
    end
  end

  @doc """
  Replaces the site's key pair with a new one, for `actor`: deploys use it
  at once. Returns the new public key.
  """
  @spec rotate_key(Site.t(), term()) :: {:ok, String.t()} | {:error, term()}
  def rotate_key(%Site{} = site, actor) do
    acting(site, actor, fn site -> DeployFiles.with_lock(site, fn -> write_key(site) end) end)
  end

  defp write_key(site) do
    {:ECPrivateKey, _version, private, {:namedCurve, _oid}, public, _attributes} =
      :public_key.generate_key({:namedCurve, :ed25519})

    with :ok <- DeployFiles.write(site, :key, encode_private_key(private, public, comment(site))),
         do: public_key(site)
  end

  # The OpenSSH private key format (PROTOCOL.key in OpenSSH), unencrypted.
  # `:ssh_file.encode/2` writes an ed25519 key's private part without the
  # public half OpenSSH expects after it, which ssh cannot load.
  defp encode_private_key(private, public, comment) do
    type = "ssh-ed25519"
    check = :crypto.strong_rand_bytes(4)
    keys = check <> check <> string(type) <> string(public) <> string(private <> public) <> string(comment)

    blob =
      "openssh-key-v1" <>
        <<0>> <>
        string("none") <>
        string("none") <>
        string("") <> <<1::32>> <> string(string(type) <> string(public)) <> string(keys <> padding(keys))

    Enum.join(
      ["-----BEGIN OPENSSH PRIVATE KEY-----"] ++ wrap(Base.encode64(blob)) ++ ["-----END OPENSSH PRIVATE KEY-----", ""],
      "\n"
    )
  end

  defp wrap(<<line::binary-size(70), rest::binary>>) when rest != "", do: [line | wrap(rest)]
  defp wrap(line), do: [line]

  defp string(value), do: <<byte_size(value)::32, value::binary>>

  defp padding(keys) do
    case rem(byte_size(keys), 8) do
      0 -> ""
      used -> for byte <- 1..(8 - used), into: "", do: <<byte>>
    end
  end

  ## Host keys and the connection test

  @doc """
  Tests the site's stored rsync target for `actor`: checks it as a deploy
  does (`Brando.Sites.DeployConfig.check_rsync_target/2`) before connecting,
  fetches the host's keys, and with accepted keys runs a dry run. Takes the
  deploy's `:runner`.
  """
  @spec test_connection(Site.t(), term(), keyword()) :: {:ok, test_result()} | {:error, term()}
  def test_connection(%Site{} = site, actor, opts \\ []) do
    acting(site, actor, fn site ->
      with {:ok, target, port} <- stored_target(site),
           :ok <- check_target(target, site),
           {:ok, _public_key} <- public_key(site),
           {:ok, host_keys} <- scan(target, port, opts) do
        accepted = accepted_keys(site, target, port)
        state = host_key_state(host_keys, accepted)

        {:ok,
         %{
           target: target,
           port: port,
           host_keys: host_keys,
           accepted_keys: accepted,
           host_key_state: state,
           dry_run: if(state == :accepted, do: dry_run(site, target, port, opts))
         }}
      end
    end)
  end

  @doc """
  Accepts the host keys a connection test showed (`test_connection/3`), for
  `actor`: they replace those accepted before for the same host and port.
  Refused when the site's stored target or port is no longer the one tested,
  the keys accepted for it are no longer those the test saw
  (`:host_keys_changed`), or a deploy would refuse the target. Keys other
  than those accepted wait for a running deploy, which reads them again for
  its real run (`:deploy_running` after a few seconds).
  """
  @spec accept_host_keys(Site.t(), term(), test_result()) :: :ok | {:error, term()}
  def accept_host_keys(%Site{} = site, actor, %{target: _, port: _, host_keys: [_ | _], accepted_keys: _} = test) do
    acting(site, actor, &accept_tested(&1, test))
  end

  def accept_host_keys(%Site{}, _actor, _result), do: {:error, :no_host_keys}

  defp accept_tested(site, %{target: target, port: port} = test) do
    with {:ok, ^target, ^port} <- stored_target(site) |> same_target(target, port),
         :ok <- check_target(target, site),
         do: outside_deploy(site, test, fn -> DeployFiles.with_lock(site, fn -> accept_unchanged(site, test) end) end)
  end

  defp outside_deploy(site, test, fun) do
    if key_set(test.host_keys) == key_set(test.accepted_keys) do
      fun.()
    else
      case Lock.with_timeout(Lock.deploy_key(site.id), @lock_timeout, fun) do
        {:ok, result} -> result
        :busy -> {:error, :deploy_running}
      end
    end
  end

  defp accept_unchanged(site, %{target: target, port: port} = test) do
    if key_set(accepted_keys(site, target, port)) == key_set(test.accepted_keys),
      do: write_known_hosts(site, target, port, test.host_keys),
      else: {:error, :host_keys_changed}
  end

  defp same_target({:ok, target, port}, target, port), do: {:ok, target, port}
  defp same_target({:ok, _target, _port}, _tested, _tested_port), do: {:error, :target_changed}
  defp same_target(error, _target, _port), do: error

  defp write_known_hosts(site, target, port, host_keys) do
    name = known_host(target, port)
    added = for %{type: type, data: data} <- host_keys, do: "#{name} #{type} #{data}"

    kept =
      case DeployFiles.read(site, :known_hosts) do
        {:ok, text} -> {:ok, text |> lines() |> Enum.reject(&(entry_host(&1) == name))}
        {:error, :enoent} -> {:ok, []}
        {:error, _reason} = error -> error
      end

    with {:ok, kept} <- kept, do: DeployFiles.write(site, :known_hosts, Enum.map(kept ++ added, &[&1, "\n"]))
  end

  defp stored_target(%Site{deploy_config: %DeployConfig{strategy: :rsync, target: target, port: port}})
       when is_binary(target) and target != "",
       do: {:ok, target, port || 22}

  defp stored_target(%Site{}), do: {:error, :not_rsync}

  defp check_target(target, site) do
    case DeployConfig.check_rsync_target(target, site) do
      :ok -> :ok
      {:error, :lookup_failed} -> {:error, :deploy_target_lookup_failed}
      {:error, :invalid} -> {:error, :invalid_deploy_target}
    end
  end

  # ssh-keyscan opens one connection per key type, and a server may drop
  # one: some of the accepted keys, and no other, are the accepted host
  defp host_key_state(host_keys, accepted) do
    cond do
      accepted == [] -> :new
      MapSet.subset?(key_set(host_keys), key_set(accepted)) -> :accepted
      true -> :changed
    end
  end

  defp key_set(keys), do: MapSet.new(keys, &{&1.type, &1.data})

  # The entry ssh looks the host up under: as given, lowercased, or with
  # another port than 22 `[host]:port` (an IPv6 literal without its brackets)
  defp known_host(target, port) do
    host = target |> DeployConfig.rsync_host() |> String.downcase()
    if port == 22, do: host, else: "[#{host}]:#{port}"
  end

  defp entry_host(line), do: line |> String.split(" ", parts: 2) |> hd() |> String.downcase()

  # Only lines for the host asked, of a key that reads back as one. One
  # connection for each type of host key a server has: OpenSSH (9.8 and
  # later) holds back a source that opens many without logging in.
  defp scan(target, port, opts) do
    name = known_host(target, port)
    host = DeployConfig.rsync_host(target)
    args = ["-T", to_string(@keyscan_timeout), "-t", "rsa,ecdsa,ed25519", "-p", to_string(port), "--", host]

    with {:ok, {output, _status}} <- run(opts, "ssh-keyscan", args) do
      keys =
        for line <- lines(output),
            [entry, type, data] <- [String.split(line, " ", trim: true)],
            String.downcase(entry) == name,
            {:ok, key} <- [host_key(type, data)],
            uniq: true,
            do: key

      if keys == [], do: {:error, {:no_host_keys, remote_output(output)}}, else: {:ok, keys}
    end
  end

  @doc "The host keys the site accepted for `target`'s host on `port`."
  @spec accepted_keys(Site.t(), String.t(), pos_integer()) :: [host_key()]
  def accepted_keys(%Site{} = site, target, port) do
    name = known_host(target, port)

    case DeployFiles.read(site, :known_hosts) do
      {:ok, text} ->
        for line <- lines(text),
            [^name, type, data] <- [String.split(line, " ", trim: true)],
            {:ok, key} <- [host_key(type, data)],
            do: key

      {:error, _reason} ->
        []
    end
  end

  defp host_key(type, data) do
    with true <- Regex.match?(~r/\A[a-z0-9@.-]{1,64}\z/, type),
         true <- Regex.match?(~r/\A[A-Za-z0-9+\/]+={0,2}\z/, data),
         [{key, _attributes}] <- :ssh_file.decode("#{type} #{data}", :openssh_key) do
      {:ok, %{type: type, data: data, fingerprint: List.to_string(:ssh.hostkey_fingerprint(:sha256, key))}}
    else
      _unreadable -> :error
    end
  rescue
    _error -> :error
  end

  defp lines(text), do: text |> String.split(["\r\n", "\n"]) |> Enum.reject(&(String.trim(&1) == ""))

  # From a directory of its own, made new under a random name; removed only
  # while still empty
  defp dry_run(site, target, port, opts) do
    empty = Path.join(System.tmp_dir!(), "brando-ssh-test-#{Base.url_encode64(:crypto.strong_rand_bytes(12))}")

    with :ok <- File.mkdir(empty) do
      try do
        case rsync(site, target, port, ["-an", "--timeout=#{@test_io_timeout}", "--", empty <> "/", target], opts) do
          {:ok, _output} -> :ok
          {:error, _reason} = error -> error
        end
      after
        File.rmdir(empty)
      end
    end
  end

  ## Every rsync to a target

  @doc """
  The ssh options an rsync to `target` on `port` runs with for the site, as
  rsync's `-e`: its own key and accepted host keys, nothing of the server
  user's. Refused when the site has no key, no host key is accepted for the
  host and port, or its deploy directory may hold no key
  (`Brando.SSG.DeployFiles.check_location/1`).
  """
  @spec rsync_ssh_args(Site.t(), String.t(), pos_integer()) :: {:ok, [String.t()]} | {:error, term()}
  def rsync_ssh_args(%Site{} = site, target, port) when is_integer(port) do
    location = DeployFiles.check_location(site)

    cond do
      location == {:error, :served} ->
        {:error, :deploy_files_served}

      location == {:error, :unsafe_path} ->
        {:error, :deploy_files_unsafe_path}

      not DeployFiles.exists?(site, :key) ->
        {:error, :deploy_key_missing}

      accepted_keys(site, target, port) == [] ->
        {:error, :host_key_not_accepted}

      true ->
        # Paths of plain characters (`check_location/1`): rsync splits this on spaces
        command =
          Enum.join(
            [
              "ssh",
              "-i",
              DeployFiles.path(site, :key),
              "-p",
              to_string(port),
              "-F",
              "none",
              "-o",
              "IdentitiesOnly=yes",
              "-o",
              "IdentityAgent=none",
              "-o",
              "BatchMode=yes",
              "-o",
              "StrictHostKeyChecking=yes",
              "-o",
              "UserKnownHostsFile=#{DeployFiles.path(site, :known_hosts)}",
              "-o",
              "GlobalKnownHostsFile=/dev/null",
              "-o",
              "CheckHostIP=no",
              "-o",
              "ConnectTimeout=#{@connect_timeout}"
            ],
            " "
          )

        {:ok, ["-e", command]}
    end
  end

  @doc """
  Runs rsync with `args` (its options and operands) for the site's `target`
  on `port`, with `rsync_ssh_args/3` before them and a time limit on
  silence. Takes the deploy's `:runner`.
  """
  @spec rsync(Site.t(), String.t(), pos_integer(), [String.t()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def rsync(%Site{} = site, target, port, args, opts \\ []) do
    with {:ok, ssh_args} <- rsync_ssh_args(site, target, port),
         {:ok, {output, status}} <- run(opts, "rsync", ssh_args ++ io_timeout(args) ++ args) do
      cond do
        status == 0 -> {:ok, output}
        String.contains?(output, "Host key verification failed") -> {:error, :host_key_rejected}
        String.contains?(output, "Failed to exec ssh") -> {:error, {:program_missing, "ssh"}}
        true -> {:error, {:rsync_failed, status, output}}
      end
    end
  end

  defp io_timeout(args) do
    if Enum.any?(args, &String.starts_with?(&1, "--timeout=")), do: [], else: ["--timeout=#{@deploy_io_timeout}"]
  end

  defp run(opts, program, args) do
    runner = Keyword.get(opts, :runner) || Application.get_env(:brando, :ssg_deploy_runner, &System.cmd/3)
    {:ok, runner.(program, args, stderr_to_stdout: true)}
  rescue
    error in ErlangError ->
      if error.original == :enoent, do: {:error, {:program_missing, program}}, else: reraise(error, __STACKTRACE__)
  end

  ## Who acts, and what is said

  # The site as stored, for someone who may change where it deploys
  defp acting(%Site{id: id}, actor, fun) do
    case Registry.get_site(id) do
      %Site{} = site -> if may_act?(actor, site), do: fun.(site), else: {:error, :forbidden}
      nil -> {:error, :site_not_found}
    end
  end

  @doc """
  Whether `user` may change where `site` deploys and act on its target, as
  saving the deployment settings asks: a build or schedule grant opens the
  Publishing screen, and only a deploy grant reaches the key and the target.
  """
  @spec may_act?(term(), Site.t()) :: boolean()
  def may_act?(%Brando.Users.User{} = user, %Site{} = site) do
    if Brando.Authorization.enabled?(),
      do: Brando.Authorization.can?(Brando.Authorization.Scope.site(user, site), :deploy, :publishing),
      else: Builds.can_manage?(user, site)
  end

  def may_act?(_actor, _site), do: false

  @doc """
  What a remote host said (rsync's or ssh's output), to show: cut to a
  length, on one line, with control characters and quotes escaped.
  """
  @spec remote_output(binary()) :: String.t()
  def remote_output(output) when is_binary(output) do
    output |> String.trim() |> inspect(printable_limit: @remote_output_limit, limit: @remote_output_limit)
  end

  @doc """
  Why a deploy was refused for a reason of this module's, to write in the
  build log and say on the screen; nil for other reasons. A refusal is not
  retried: the step it names on the Publishing screen must be taken first.
  """
  @spec refusal_message(term()) :: String.t() | nil
  def refusal_message(:deploy_key_missing),
    do:
      "the site has no SSH key. On Publishing, save the deployment settings to make one, add its public key to the host's authorized_keys, then use Test connection."

  def refusal_message(:host_key_not_accepted),
    do:
      "no host key is accepted for the target's host and port. On Publishing, use Test connection and accept the host key."

  def refusal_message(:build_target_changed),
    do:
      "the build was made for another target or port than the site's deployment settings. Make a new build, then deploy it."

  def refusal_message(:host_key_rejected),
    do:
      "the host's key is not the one accepted for it. On Publishing, use Test connection to compare the fingerprints, and accept the new key only if you know why the host changed."

  def refusal_message(:deploy_files_served),
    do:
      "the site's deploy directory is inside a directory the installation serves (media or static files), so it holds no SSH key. Set :sites_path in the config outside them."

  def refusal_message(:deploy_files_unsafe_path),
    do:
      "the site's deploy directory has characters ssh reads specially in its path, so it holds no SSH key. Set :sites_path in the config to a path of letters, digits and . _ + @ - /."

  def refusal_message({:program_missing, program}), do: "#{program} is not installed on this server."
  def refusal_message(_reason), do: nil

  @doc "A deploy or test failure of this module's, to show (see `refusal_message/1`)."
  @spec failure_message(term()) :: String.t()
  def failure_message({:rsync_failed, status, output}),
    do: "rsync exited with status #{status}: #{remote_output(output)}"

  def failure_message({:no_host_keys, output}), do: "the host answered with no SSH host keys: #{output}"
  def failure_message(reason), do: refusal_message(reason) || inspect(reason)
end
