defmodule Brando.SSG.TargetReview do
  @moduledoc """
  What an rsync deploy may delete on its target: a path Brando uploaded or an
  admin confirmed, never one on the keep list (`Brando.Sites.DeployConfig`'s
  `:keep_paths`). The receiving rsync enforces it, with filter rules that
  protect every other path (`Brando.SSG.TargetPaths.plan/3`), so a file that
  appears on the target at any moment is never deleted. Dry runs only
  report.

  The target's state is one file (`Brando.SSG.DeployFiles`'s
  `:target_state`), read and written holding the deploy lock
  that `Brando.SSG.Deploy` holds: the target, port and accepted host
  keys it is for, whether an admin reviewed it, the paths Brando may have
  uploaded, the paths an admin confirmed, and what the target was last found
  to hold (`found`): the review's listing before the first deploy, the
  unknown files after each, and whether Brando's block was written to its
  `.htaccess` (`:block`, `Brando.SSG.TargetHtaccess`). A changed target or
  port, or other accepted host keys, makes the target unreviewed and its
  lists unused.

  - `review/3`, after a connection test, lists an unreviewed target and
    fetches its `.htaccess`; `confirm/5` keeps what the admin ticked and
    confirms the rest of the listing it names (a digest).
  - `deploy/4` refuses a target that is not the reviewed one, then: lists the
    target to refuse a collision rsync would clear the way for, adds the
    build's paths to the uploaded list, runs rsync with the rules, keeps the
    build's paths as the uploaded list, and lists the unknown files.
  - `keep/3` adds ticked unknown entries to the keep list; `confirm/5` with
    `:unknown` confirms the rest, and `delete_unknown/4` queues a deploy of
    the site's deployed build when the job runs.

  Each acts for someone who may configure the site's publishing
  (`Brando.SSG.Builds.can_configure?/2`), on the site as stored;
  `confirm/5` with `:unknown` and `delete_unknown/4` also for someone who
  may deploy it.
  """

  alias Brando.Sites.DeployConfig
  alias Brando.Sites.Site
  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.SSG.DeployFiles
  alias Brando.SSG.Htaccess
  alias Brando.SSG.SSH
  alias Brando.SSG.TargetHtaccess
  alias Brando.SSG.TargetPaths
  alias Brando.Tenant.Lock
  alias Brando.Tenant.Registry

  require Logger

  # A listing longer than this is cut short, and confirms nothing
  @listing_limit 100_000
  @lock_timeout :timer.seconds(5)
  @name_limit 200

  @typedoc """
  What the target was last found to hold: its paths, a digest the screen
  names it by (with the keep list it was shown with, from `status/2` and
  `review/3`), and for a review the `.htaccess` at its root (`{:ok, text}`,
  `:too_large`, `{:error, reason}`, or nil when there is none).
  """
  @type found :: %{paths: [TargetPaths.path()], digest: String.t(), htaccess: term()}

  @type state :: %{
          target: String.t(),
          port: pos_integer(),
          host_keys: [{String.t(), String.t()}],
          reviewed: boolean(),
          uploaded: [TargetPaths.path()],
          confirmed: [TargetPaths.path()],
          found: found() | nil,
          block: boolean()
        }

  @typedoc "What the Publishing screen shows of the site's target."
  @type status :: %{
          target: String.t(),
          port: pos_integer(),
          reviewed: boolean(),
          found: found() | nil,
          keep: [TargetPaths.path()]
        }

  ## The screen

  @doc """
  What the Publishing screen shows `actor` of the site's stored rsync
  target: whether it is reviewed, what it was last found to hold, and the
  keep list. Nil without rsync settings.
  """
  @spec status(Site.t(), term()) :: {:ok, status() | nil} | {:error, term()}
  def status(%Site{} = site, actor) do
    acting(site, actor, fn site ->
      with {:ok, target, port} <- stored_target(site),
           {:ok, state} <- read_state(site) do
        current = for_target(state, target, port, host_keys(site, target, port))

        {:ok,
         %{
           target: target,
           port: port,
           reviewed: match?(%{reviewed: true}, current),
           found: current && current.found && shown(current.found, site),
           keep: keep_paths(site)
         }}
      else
        {:error, :not_rsync} -> {:ok, nil}
        error -> error
      end
    end)
  end

  @doc """
  Lists the site's stored target when it is not reviewed, for `actor`, and
  keeps the listing for `confirm/5`: `{:ok, :reviewed}` for a reviewed
  target. A listing that fails or is cut short is an error, not an empty
  target. Takes the deploy's `:runner`.
  """
  @spec review(Site.t(), term(), keyword()) :: {:ok, :reviewed | found()} | {:error, term()}
  def review(%Site{} = site, actor, opts \\ []), do: acting(site, actor, &review_stored(&1, opts))

  defp review_stored(site, opts) do
    with {:ok, target, port} <- stored_target(site),
         keys = host_keys(site, target, port),
         {:ok, state} <- read_state(site) do
      if match?(%{reviewed: true}, for_target(state, target, port, keys)),
        do: {:ok, :reviewed},
        else: list_for_review(site, target, port, keys, opts)
    end
  end

  defp list_for_review(site, target, port, keys, opts) do
    with {:ok, paths} <- listing(site, target, port, opts) do
      found = %{
        paths: paths,
        digest: TargetPaths.digest({target, port, keys, paths}),
        htaccess: if(".htaccess" in paths, do: fetch_htaccess(site, target, port, opts))
      }

      locked(site, &store_review(&1, target, port, keys, found))
    end
  end

  defp store_review(site, target, port, keys, found) do
    cond do
      stored_target(site) != {:ok, target, port} or host_keys(site, target, port) != keys ->
        {:error, :target_changed}

      # Another admin confirmed while this listed
      match?({:ok, %{reviewed: true}}, current_state(site, target, port)) ->
        {:ok, :reviewed}

      true ->
        state = %{
          target: target,
          port: port,
          host_keys: keys,
          reviewed: false,
          uploaded: [],
          confirmed: [],
          found: found,
          block: block_written_to?(site, target) or block_found?(found)
        }

        with :ok <- write_state(site, state), do: {:ok, shown(found, site)}
    end
  end

  @doc """
  Confirms the listing named by `digest`, for `actor`: the ticked top-level
  entries are kept (added to the keep list when their names may be on it,
  left alone otherwise), the rest of the listing may be deleted. `kind` is
  `:review` for a target not reviewed yet, which it makes reviewed, or
  `:unknown` for the unknown files of a reviewed one, which `actor` must
  also be one who may deploy: any later deploy carries the confirmation out.
  Refused when the stored listing is another (`:stale_listing`) or the
  target changed.
  """
  @spec confirm(Site.t(), term(), :review | :unknown, String.t(), [String.t()]) :: :ok | {:error, term()}
  def confirm(%Site{} = site, actor, kind, digest, ticked) when kind in [:review, :unknown] and is_binary(digest) do
    with :ok <- may_confirm(site, actor, kind),
         do: acting(site, actor, fn site -> locked(site, &confirm_stored(&1, kind, digest, ticked)) end)
  end

  defp may_confirm(site, actor, :unknown),
    do: Brando.Authorization.Operations.authorize(actor, :deploy, :publishing, site.id)

  defp may_confirm(_site, _actor, :review), do: :ok

  defp confirm_stored(site, kind, digest, ticked) do
    with {:ok, target, port} <- stored_target(site),
         {:ok, state} <- current_state(site, target, port),
         :ok <- confirmable(state, kind, digest, site),
         {:ok, keep} <- keep_ticked(site, state.found, ticked) do
      ticked = MapSet.new(ticked)

      confirmed =
        for path <- state.found.paths,
            not TargetPaths.kept?(path, keep),
            TargetPaths.top(path) not in ticked,
            TargetPaths.rule_path?(path),
            do: path

      write_state(site, %{state | reviewed: true, confirmed: union(state.confirmed, confirmed), found: nil})
    end
  end

  defp confirmable(%{found: %{} = found, reviewed: reviewed}, kind, digest, site)
       when (kind == :review and not reviewed) or (kind == :unknown and reviewed) do
    if shown(found, site).digest == digest, do: :ok, else: {:error, :stale_listing}
  end

  defp confirmable(_state, _kind, _digest, _site), do: {:error, :stale_listing}

  # A listing as the screen shows it, with the keep list that marks it: its
  # digest names both
  defp shown(found, site), do: %{found | digest: TargetPaths.digest({found.digest, keep_paths(site)})}

  @doc "Adds the ticked top-level entries of the unknown files to the keep list, for `actor`."
  @spec keep(Site.t(), term(), [String.t()]) :: :ok | {:error, term()}
  def keep(%Site{} = site, actor, ticked) do
    acting(site, actor, fn site -> locked(site, &keep_stored(&1, ticked)) end)
  end

  defp keep_stored(site, ticked) do
    with {:ok, target, port} <- stored_target(site),
         {:ok, %{found: %{}} = state} <- current_state(site, target, port),
         {:ok, _keep} <- keep_ticked(site, state.found, ticked),
         do: :ok
  end

  @doc """
  Confirms the unknown files named by `digest` but the ticked ones (as
  `confirm/5`), for `actor`, and queues a deploy of whichever build is the
  site's deployed one when the job runs, which deletes them.
  """
  @spec delete_unknown(Site.t(), term(), String.t(), [String.t()]) :: {:ok, Oban.Job.t()} | {:error, term()}
  def delete_unknown(%Site{} = site, actor, digest, ticked) do
    with :ok <- confirm(site, actor, :unknown, digest, ticked) do
      %{"site_id" => site.id, "action" => "redeploy", "creator_id" => actor.id}
      |> Brando.Worker.SSGDeploy.new(tags: ["ssg-deploy", "site:#{site.id}"])
      |> Oban.insert()
    end
  end

  @doc "Adds `path` to the keep list, for `actor`."
  @spec add_keep_path(Site.t(), term(), String.t()) :: :ok | {:error, term()}
  def add_keep_path(%Site{} = site, actor, path) do
    if TargetPaths.keep_entry?(path),
      do: change_keep(site, actor, &Enum.uniq(&1 ++ [path])),
      else: {:error, :invalid_keep_path}
  end

  @doc "Takes `path` off the keep list, for `actor`."
  @spec remove_keep_path(Site.t(), term(), String.t()) :: :ok | {:error, term()}
  def remove_keep_path(%Site{} = site, actor, path), do: change_keep(site, actor, &List.delete(&1, path))

  defp change_keep(site, actor, fun) do
    acting(site, actor, fn site -> locked(site, &save_keep(&1, fun.(keep_paths(&1)))) end)
  end

  # The ticked names of the listing that may be on the keep list, added to it
  defp keep_ticked(site, found, ticked) do
    tops = found.paths |> Enum.map(&TargetPaths.top/1) |> MapSet.new()
    added = Enum.filter(ticked, &(&1 in tops and TargetPaths.keep_entry?(&1)))
    keep = Enum.uniq(keep_paths(site) ++ added)

    with :ok <- save_keep(site, keep), do: {:ok, keep}
  end

  defp save_keep(site, keep) do
    if keep == keep_paths(site) do
      :ok
    else
      case Registry.update_site(site, %{deploy_config: %{keep_paths: keep}}) do
        {:ok, _site} -> :ok
        {:error, changeset} -> {:error, {:invalid_keep_paths, changeset}}
      end
    end
  end

  ## Deploying

  @doc """
  Why a deploy to the site's stored rsync target would be refused before it
  copies anything: the site has no key (`:deploy_key_missing`), no host key
  is accepted (`:host_key_not_accepted`), or the target is not reviewed
  (`:target_not_reviewed`), among the refusals of `deploy/4`. `:ok`
  otherwise, and for another strategy.
  """
  @spec deployable(Site.t()) :: :ok | {:error, term()}
  def deployable(%Site{} = site) do
    with {:ok, target, port} <- stored_target(site),
         {:ok, _ssh_args} <- SSH.rsync_ssh_args(site, target, port),
         {:ok, state} <- read_state(site),
         {:ok, _state} <- reviewed(state, site, target, port, host_keys(site, target, port)) do
      :ok
    else
      {:error, :not_rsync} -> :ok
      error -> error
    end
  end

  @doc """
  Deploys the build to `target` on `port` with the site's reviewed state, as
  the moduledoc says. Call it holding the deploy lock. Returns lines for the
  build log. Takes the deploy's `:runner`.
  """
  @spec deploy(Build.t(), String.t(), pos_integer(), keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def deploy(%Build{site: %Site{} = site} = build, target, port, opts) do
    keys = host_keys(site, target, port)

    with {:ok, _ssh_args} <- SSH.rsync_ssh_args(site, target, port),
         {:ok, state} <- read_state(site),
         {:ok, state} <- reviewed(state, site, target, port, keys),
         do: deploy_reviewed(build, state, keep_paths(site), opts)
  after
    File.rm(DeployFiles.path(build.site, :filter))
  end

  defp deploy_reviewed(%Build{site: site} = build, state, keep, opts) do
    %{target: target, port: port} = state
    htaccess = TargetHtaccess.mode(build, block_written?(state))
    plan = TargetPaths.plan(build.build_path, state.uploaded ++ state.confirmed, keep, TargetHtaccess.hidden(htaccess))
    plan = %{plan | upload: plan.upload -- TargetHtaccess.replaced(htaccess)}
    source = String.trim_trailing(build.build_path, "/") <> "/"

    with {:ok, listing} <- listing(site, target, port, opts),
         :ok <- check_collisions(plan, listing),
         {:ok, notes} <- run(build, source, state, plan, htaccess, keep, opts) do
      deployed = Map.merge(state, %{uploaded: plan.upload, confirmed: [], found: nil, block: htaccess == :write})
      # The merged file is the host's, not unknown
      known = if htaccess == :write, do: keep ++ TargetHtaccess.replaced(htaccess), else: keep

      # Failing here leaves the union: more than this build, nothing unknown
      case write_state(site, deployed) do
        :ok ->
          {:ok, notes ++ list_unknown(site, deployed, source, known, opts)}

        {:error, reason} ->
          Logger.warning("SSG target state of site #{site.key} not written: #{inspect(reason)}")
          {:ok, notes}
      end
    end
  end

  # The real run: the merged `.htaccess` first, as rsync keeps the first of
  # two files of one name, then the build. The build's paths count as
  # uploaded, and a block as written (a run that fails halfway may have
  # written it), in the last write before it.
  defp run(%Build{site: site} = build, source, state, plan, htaccess, keep, opts) do
    %{target: target, port: port} = state
    block? = block_written?(state) or htaccess == :write
    uploading = Map.merge(state, %{uploaded: union(state.uploaded, plan.upload), block: block?})

    SSH.with_temporary_dir("brando-ssg-merged", fn dir ->
      with {:ok, step} <- TargetHtaccess.prepare(htaccess, build, target, port, keep, dir, opts),
           :ok <- DeployFiles.write(site, :filter, [step.rules, plan.rules]),
           :ok <- write_state(site, uploading, :uploaded_list),
           {:ok, _output} <-
             SSH.rsync(
               site,
               target,
               port,
               ["-az", "--delete"] ++ filter_args(site) ++ ["--"] ++ step.sources ++ [source, target],
               opts
             ),
           do: {:ok, step.notes}
    end)
  end

  # From before the `.htaccess` step, a state has no `:block`
  defp block_written?(state), do: Map.get(state, :block, false)

  # A block written to the path before its host keys or port changed is
  # removed as any other
  defp block_written_to?(site, target) do
    case read_state(site) do
      {:ok, %{target: ^target} = state} -> block_written?(state)
      _other -> false
    end
  end

  # A block on the target counts as written: the state of another target
  # may have replaced the one that said so
  defp block_found?(%{htaccess: {:ok, text}}), do: Htaccess.block?(text)
  defp block_found?(_found), do: false

  defp filter_args(site), do: ["--from0", "--filter=merge " <> DeployFiles.path(site, :filter)]

  # The build's own target, still the site's: one reviewed, with the host
  # keys accepted now
  defp reviewed(state, site, target, port, keys) do
    cond do
      not match?({:ok, ^target, ^port}, stored_target(site)) -> {:error, :build_target_changed}
      match?(%{reviewed: true}, for_target(state, target, port, keys)) -> {:ok, state}
      true -> {:error, :target_not_reviewed}
    end
  end

  # rsync clears a path the build needs for a directory whatever the rules
  # say, and fails on one the build needs for a file. Refused here when the
  # path holds what it may not delete; a file that appears there during the
  # run is the limit of this check.
  defp check_collisions(plan, listing) do
    on_target = MapSet.new(listing)
    deletable = MapSet.new(plan.deletable)

    Enum.find_value(plan.upload, :ok, &collision(&1, on_target, deletable, listing))
  end

  defp collision(path, on_target, deletable, listing) do
    file = String.trim_trailing(path, "/")
    directory = file <> "/"

    collides? =
      if TargetPaths.directory?(path),
        do: file in on_target and file not in deletable,
        else: directory in on_target and Enum.any?(listing, &(String.starts_with?(&1, directory) and &1 not in deletable))

    if collides?, do: {:error, {:target_collision, file}}
  end

  # What the target holds beyond the build and the keep list, for the screen.
  # Its failure does not fail the deploy.
  defp list_unknown(site, state, source, keep, opts) do
    nonce = TargetPaths.nonce()

    args =
      ["-an", "--delete"] ++
        filter_args(site) ++ [TargetPaths.listing_format(nonce), "--", source, state.target]

    with :ok <- DeployFiles.write(site, :filter, TargetPaths.keep_rules(keep)),
         {:ok, output} <- SSH.rsync(site, state.target, state.port, args, opts),
         {:ok, paths} <- limited(TargetPaths.parse_listing(output, nonce)),
         found = %{paths: paths, digest: TargetPaths.digest({state.target, state.port, state.host_keys, paths})},
         :ok <- write_state(site, %{state | found: found}) do
      if paths == [], do: [], else: ["The target holds #{length(paths)} paths Brando did not put there: see Publishing"]
    else
      # The build is copied by now: this listing only tells the screen
      {:error, {:listing_cut_short, count, limit}} ->
        ["The target holds #{count} paths Brando did not put there, more than the #{limit} Publishing lists"]

      {:error, reason} ->
        ["Could not list what the target holds beyond the build: #{failure_message(reason)}"]
    end
  end

  ## Listing the target

  # Everything the target holds: a dry run that would delete it all, from an
  # empty directory. Always `-n`: without it these arguments delete.
  defp listing(site, target, port, opts) do
    nonce = TargetPaths.nonce()

    SSH.with_temporary_dir("brando-ssg-listing", fn empty ->
      args = ["-an", "--delete", TargetPaths.listing_format(nonce), "--", empty <> "/", target]

      with {:ok, output} <- SSH.rsync(site, target, port, args, opts),
           do: limited(TargetPaths.parse_listing(output, nonce))
    end)
  end

  defp limited(paths) do
    count = length(paths)
    if count > @listing_limit, do: {:error, {:listing_cut_short, count, @listing_limit}}, else: {:ok, Enum.sort(paths)}
  end

  defp fetch_htaccess(site, target, port, opts) do
    case TargetHtaccess.fetch(site, target, port, opts) do
      {:ok, nil, _mode} -> nil
      {:ok, text, _mode} -> {:ok, text}
      {:error, :htaccess_too_large} -> :too_large
      {:error, _reason} = error -> error
    end
  end

  ## The state file

  # `fun` gets the site as stored once the lock is held
  defp locked(site, fun) do
    case Lock.with_timeout(Lock.deploy_key(site.id), @lock_timeout, fn -> fun.(Registry.get_site(site.id)) end) do
      {:ok, result} -> result
      :busy -> {:error, :deploy_running}
    end
  end

  # The state when it is for the site's target, port and accepted host keys
  defp current_state(site, target, port) do
    with {:ok, state} <- read_state(site) do
      case for_target(state, target, port, host_keys(site, target, port)) do
        nil -> {:error, :target_changed}
        state -> {:ok, state}
      end
    end
  end

  defp for_target(%{target: target, port: port, host_keys: keys} = state, target, port, keys) when keys != [], do: state
  defp for_target(_state, _target, _port, _keys), do: nil

  defp read_state(site) do
    case DeployFiles.read(site, :target_state) do
      {:ok, binary} -> decode_state(binary)
      {:error, :enoent} -> {:ok, nil}
      {:error, reason} -> {:error, {:target_state_unreadable, reason}}
    end
  end

  defp decode_state(binary) do
    case :erlang.binary_to_term(binary, [:safe]) do
      %{target: _, port: _, host_keys: _, reviewed: _, uploaded: _, confirmed: _, found: _} = state -> {:ok, state}
      _other -> {:error, {:target_state_unreadable, :format}}
    end
  rescue
    ArgumentError -> {:error, {:target_state_unreadable, :format}}
  end

  defp write_state(site, state, step \\ :state) do
    case DeployFiles.write(site, :target_state, :erlang.term_to_binary(state)) do
      :ok -> :ok
      {:error, reason} -> {:error, {:target_state_not_written, step, reason}}
    end
  end

  defp host_keys(site, target, port),
    do: site |> SSH.accepted_keys(target, port) |> Enum.map(&{&1.type, &1.data}) |> Enum.sort()

  defp keep_paths(%Site{deploy_config: %DeployConfig{keep_paths: keep}}) when is_list(keep), do: keep
  defp keep_paths(%Site{}), do: %DeployConfig{}.keep_paths

  defp union(paths, more), do: paths |> Enum.concat(more) |> Enum.uniq() |> Enum.sort()

  defp stored_target(%Site{deploy_config: %DeployConfig{strategy: :rsync, target: target, port: port}})
       when is_binary(target) and target != "",
       do: {:ok, target, port || 22}

  defp stored_target(%Site{}), do: {:error, :not_rsync}

  # The site as stored, for someone who may configure its publishing
  defp acting(%Site{id: id}, actor, fun) do
    case Registry.get_site(id) do
      %Site{} = site -> if Builds.can_configure?(actor, site), do: fun.(site), else: {:error, :forbidden}
      nil -> {:error, :site_not_found}
    end
  end

  ## What is said

  @doc """
  A path read from the target, to show: as it is when it is plain, else
  quoted with its control characters escaped; cut to a length.
  """
  @spec display(String.t()) :: String.t()
  def display(path) do
    plain? =
      String.valid?(path) and not Regex.match?(~r/[\x00-\x1f\x7f]/, path) and path == String.trim(path) and
        String.length(path) <= @name_limit

    if plain?, do: path, else: inspect(path, printable_limit: @name_limit, binaries: :as_strings)
  end

  @doc """
  Why a deploy was refused for a reason of this module's, to write in the
  build log; nil for other reasons. A refusal is not retried.
  """
  @spec refusal_message(term()) :: String.t() | nil
  def refusal_message(:target_not_reviewed),
    do:
      "the target is not reviewed for its host keys. On Publishing, use Test connection and confirm what the target holds before the first deploy."

  def refusal_message({:target_collision, path}),
    do:
      "the build and the target have a file and a directory at #{display(path)}, and the target's holds what Brando may not delete. Keep or delete it on the host, or confirm it on Publishing."

  def refusal_message({:target_state_unreadable, _reason}),
    do: "the target's state could not be read. On Publishing, test the connection and review the target again."

  def refusal_message({:target_state_not_written, :uploaded_list, reason}),
    do: "the list of files Brando uploads could not be written (#{inspect(reason)}), so nothing was copied."

  def refusal_message({:listing_cut_short, count, limit}),
    do:
      "the target holds #{count} paths, more than the #{limit} a deploy lists before it runs, so nothing was copied. Remove files from the target to deploy to it."

  def refusal_message(reason), do: TargetHtaccess.refusal_message(reason)

  @doc "A failure of this module's or `Brando.SSG.SSH`'s, to show."
  @spec failure_message(term()) :: String.t()
  def failure_message(reason), do: refusal_message(reason) || SSH.failure_message(reason)
end
