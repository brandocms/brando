defmodule Brando.SSG.Deploy do
  @moduledoc """
  Deploys and rolls back persistent SSG artifacts.

  This is deliberately separate from Florist's OTP release deployment. A
  rollback here republishes an older static artifact; it does not switch the
  running Phoenix release or mutate its ephemeral `priv/static` directory.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Repo
  alias Brando.Sites.Site
  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.Tenant.Lock

  @public_opts [prefix: "public"]

  @doc "Deploys a ready or archived build using its snapshotted configuration."
  @spec deploy(Build.t(), keyword()) :: {:ok, Build.t()} | {:error, term()}
  def deploy(%Build{} = build, opts \\ []) do
    Brando.Authorization.Operations.run(:deploy, :publishing, build.site_id, opts, fn ->
      Lock.with("ssg-deploy:#{build.site_id}", fn -> deploy_locked(build.id, opts) end)
      |> notify_webhook(opts)
    end)
  end

  @doc "Redeploys an older artifact and makes it the site's current static release."
  @spec rollback(Site.t(), Build.t(), keyword()) :: {:ok, Build.t()} | {:error, term()}
  def rollback(site, build, opts \\ [])

  def rollback(%Site{id: site_id}, %Build{site_id: site_id} = build, opts) do
    deploy(build, Keyword.put(opts, :event, :rollback))
  end

  def rollback(%Site{}, %Build{}, _opts), do: {:error, :build_belongs_to_another_site}

  @doc "Prunes old ready, archived, and failed artifact directories while retaining history rows."
  @spec prune(Site.t(), pos_integer()) :: {:ok, [Build.t()]} | {:error, term()}
  def prune(%Site{} = site, keep) when is_integer(keep) and keep > 0 do
    candidates =
      from(build in Build,
        where:
          build.site_id == ^site.id and build.status in [:ready, :archived, :failed] and
            is_nil(build.pruned_at),
        order_by: [desc: build.build_number],
        offset: ^keep
      )
      |> Repo.all(@public_opts)

    candidates
    |> Enum.reduce_while({:ok, []}, fn build, {:ok, pruned} ->
      with :ok <- remove_build_path(site, build),
           {:ok, updated} <- Builds.update(build, %{pruned_at: DateTime.utc_now()}) do
        {:cont, {:ok, [updated | pruned]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, pruned} -> {:ok, Enum.reverse(pruned)}
      error -> error
    end
  end

  def prune(%Site{}, keep), do: {:error, {:invalid_retention_count, keep}}

  defp deploy_locked(build_id, opts) do
    build = Builds.get_build(build_id)

    with %Build{} <- build,
         true <- build.site.status == :active,
         true <- build.status in [:ready, :deployed, :archived],
         true <- managed_build_path?(build),
         true <- is_nil(build.pruned_at) and File.dir?(build.build_path),
         :ok <- run_strategy(build, opts) do
      mark_deployed(build)
    else
      nil -> {:error, :build_not_found}
      false -> {:error, :build_not_deployable}
      {:error, _reason} = error -> error
    end
  end

  defp run_strategy(%Build{deploy_config: config} = build, opts) do
    case config["strategy"] do
      "rsync" -> deploy_rsync(build, config["target"], opts)
      "s3" -> deploy_s3(build, config["target"], opts)
      "cloudflare_pages" -> {:error, :cloudflare_pages_not_implemented}
      nil -> {:error, :deploy_strategy_not_configured}
      strategy -> {:error, {:unsupported_deploy_strategy, strategy}}
    end
  end

  defp deploy_rsync(_build, target, _opts) when target in [nil, ""],
    do: {:error, :deploy_target_not_configured}

  defp deploy_rsync(build, target, opts) do
    runner = Keyword.get(opts, :runner, &System.cmd/3)
    args = ["-az", "--delete", String.trim_trailing(build.build_path, "/") <> "/", target]

    case runner.("rsync", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, exit_status} -> {:error, {:rsync_failed, exit_status, output}}
    end
  rescue
    exception -> {:error, {:rsync_failed, Exception.message(exception)}}
  end

  defp deploy_s3(_build, target, _opts) when target in [nil, ""],
    do: {:error, :deploy_target_not_configured}

  defp deploy_s3(build, target, opts) do
    with {:ok, bucket, prefix} <- parse_s3_target(target),
         request = Keyword.get(opts, :s3_request, &ExAws.request/1),
         {:ok, existing_keys} <- list_s3_keys(bucket, prefix, request),
         :ok <- delete_s3_keys(bucket, existing_keys, request) do
      upload_s3_files(build, bucket, prefix, request)
    end
  rescue
    exception -> {:error, {:s3_upload_failed, Exception.message(exception)}}
  end

  defp upload_s3_files(build, bucket, prefix, request) do
    build.build_path
    |> regular_files()
    |> Enum.reduce_while(:ok, fn path, :ok ->
      case upload_s3_file(build, bucket, prefix, path, request) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp upload_s3_file(build, bucket, prefix, path, request) do
    key = path |> Path.relative_to(build.build_path) |> then(&Path.join(prefix, &1))
    operation = ExAws.S3.put_object(bucket, key, File.read!(path), content_type: MIME.from_path(path))

    case request.(operation) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, {:s3_upload_failed, key, reason}}
    end
  end

  defp list_s3_keys(bucket, prefix, request, continuation_token \\ nil, keys \\ []) do
    opts =
      [prefix: s3_prefix(prefix)]
      |> then(fn opts ->
        if continuation_token, do: Keyword.put(opts, :continuation_token, continuation_token), else: opts
      end)

    operation = ExAws.S3.list_objects_v2(bucket, opts)

    case request.(operation) do
      {:ok, %{body: body}} ->
        page_keys = Enum.map(Map.get(body, :contents, []), & &1.key)
        all_keys = keys ++ page_keys

        if body[:is_truncated] in [true, "true"] and body[:next_continuation_token] do
          list_s3_keys(bucket, prefix, request, body.next_continuation_token, all_keys)
        else
          {:ok, all_keys}
        end

      {:error, reason} ->
        {:error, {:s3_list_failed, reason}}

      response ->
        {:error, {:invalid_s3_list_response, response}}
    end
  end

  defp delete_s3_keys(_bucket, [], _request), do: :ok

  defp delete_s3_keys(bucket, keys, request) do
    keys
    |> Enum.chunk_every(1_000)
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      case bucket |> ExAws.S3.delete_all_objects(chunk) |> request.() do
        {:ok, _response} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:s3_delete_failed, reason}}}
      end
    end)
  end

  defp s3_prefix(""), do: ""
  defp s3_prefix(prefix), do: String.trim_trailing(prefix, "/") <> "/"

  defp parse_s3_target(target) do
    case URI.parse(target) do
      %URI{scheme: "s3", host: bucket, path: path} when is_binary(bucket) and bucket != "" ->
        {:ok, bucket, path |> Kernel.||("/") |> String.trim("/")}

      _invalid ->
        {:error, {:invalid_s3_target, target}}
    end
  end

  defp regular_files(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
  end

  defp managed_build_path?(%Build{site: %Site{} = site, build_path: build_path}) do
    Path.dirname(Path.expand(build_path)) == Path.expand(Builds.build_root(site))
  end

  defp managed_build_path?(%Build{}), do: false

  defp mark_deployed(build) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      from(other in Build,
        where:
          other.site_id == ^build.site_id and other.status == :deployed and
            other.id != ^build.id
      )
      |> Repo.update_all([set: [status: :archived, updated_at: now]], @public_opts)

      case Builds.update(build, %{
             status: :deployed,
             deployed_at: now,
             build_log: build.build_log <> log_line("Artifact deployed")
           }) do
        {:ok, deployed} -> deployed
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, deployed} ->
        Builds.broadcast(deployed)
        {:ok, deployed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp notify_webhook({:ok, build} = result, opts) do
    case build.deploy_config["webhook_url"] do
      url when is_binary(url) and url != "" ->
        event = Keyword.get(opts, :event, :deploy)
        webhook = Keyword.get(opts, :webhook, &default_webhook/2)

        payload = %{
          event: event,
          build_id: build.id,
          site_id: build.site_id,
          version: build.version,
          status: build.status
        }

        case webhook.(url, payload) do
          :ok ->
            result

          {:ok, _response} ->
            result

          {:error, reason} ->
            Builds.append_log(build, "Deployment webhook failed: #{inspect(reason)}")
            result
        end

      _not_configured ->
        result
    end
  end

  defp notify_webhook(error, _opts), do: error

  defp default_webhook(url, payload) do
    case Req.post(url, json: payload, retry: false) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp remove_build_path(site, build) do
    root = Builds.build_root(site) |> Path.expand()
    path = Path.expand(build.build_path)

    if Path.dirname(path) == root do
      case File.rm_rf(path) do
        {:ok, _removed} -> :ok
        {:error, reason, failed_path} -> {:error, {:prune_failed, failed_path, reason}}
      end
    else
      {:error, {:unsafe_build_path, path}}
    end
  end

  defp log_line(message) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")
    "[#{timestamp}] #{message}\n"
  end
end
