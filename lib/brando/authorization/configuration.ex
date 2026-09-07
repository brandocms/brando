defmodule Brando.Authorization.Configuration do
  @moduledoc """
  Superuser-only migration tools and portable, versioned group configuration.

  Exports describe one scope using stable group/permission keys, never database
  IDs or memberships. Imports merge by key into the server-selected scope, replace
  the listed groups' grants, and leave all other groups and memberships alone.
  The protected Superuser is excluded. Applying requires a fresh preview revision.
  """
  import Ecto.Query, only: [from: 2]
  alias Brando.Authorization.{Administration, AuditEvent, Catalog, Grant, Group, Groups, Migration, Scope}
  alias Brando.Repo
  alias Ecto.Changeset

  @format "brando.authorization"
  @max_bytes 1_000_000
  @max_groups 500

  def max_bytes, do: @max_bytes
  def allowed?(%Scope{} = scope), do: Administration.superuser?(scope)

  def report(scope) do
    with :ok <- authorize(scope), do: {:ok, Migration.report()}
  end

  def backfill(scope) do
    transact(fn ->
      authorize!(scope)

      case Migration.run() do
        {:ok, report} ->
          Repo.insert!(%AuditEvent{
            actor_id: scope.user_id,
            action: "migration.backfilled",
            after: %{users: report.users}
          })

          report

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def export(scope) do
    with :ok <- authorize(scope) do
      document = %{
        "format" => @format,
        "version" => 1,
        "scope" => Atom.to_string(scope.kind),
        "groups" => Enum.map(groups(scope), &serialize/1)
      }

      {:ok, Jason.encode!(document, pretty: true)}
    end
  end

  def preview(scope, json) do
    with :ok <- authorize(scope),
         {:ok, entries} <- decode(scope, json) do
      plan(scope, entries)
    end
  end

  def apply(scope, json, expected_revision) do
    transact(fn ->
      authorize!(scope)
      entries = unwrap!(decode(scope, json))
      preview = unwrap!(plan(scope, entries))
      if preview.revision != expected_revision, do: Repo.rollback(:stale)
      Enum.each(preview.changes, &apply_group(scope, &1))
      %{created: preview.created, updated: preview.updated, unchanged: preview.unchanged}
    end)
  end

  defp plan(scope, entries) do
    existing = groups(scope)
    by_key = Map.new(existing, &{&1.key, &1})

    if Enum.any?(entries, fn entry ->
         current = by_key[entry["key"]]
         current && serialize(current)["preset"] != entry["preset"]
       end) do
      invalid("A group key already exists with a different preset. Export a fresh configuration before importing.")
    else
      changes = Enum.map(entries, &diff(by_key[&1["key"]], &1))

      {:ok,
       %{
         revision: revision(existing),
         changes: changes,
         created: Enum.count(changes, &(&1.action == :create)),
         updated: Enum.count(changes, &(&1.action == :update)),
         unchanged: Enum.count(changes, &(&1.action == :unchanged)),
         members:
           changes
           |> Enum.filter(&(&1.action == :update))
           |> Enum.map(& &1.members)
           |> List.flatten()
           |> Enum.uniq()
           |> length()
       }}
    end
  end

  defp diff(current, entry) do
    before = if current, do: serialize(current)
    old_keys = if before, do: before["permissions"], else: []

    %{
      current: current,
      entry: entry,
      before: before,
      action:
        cond do
          is_nil(current) -> :create
          before == entry -> :unchanged
          true -> :update
        end,
      added: entry["permissions"] -- old_keys,
      removed: old_keys -- entry["permissions"],
      members: if(current, do: Enum.map(current.memberships, & &1.user_id), else: [])
    }
  end

  defp apply_group(_scope, %{action: :unchanged}), do: :ok

  defp apply_group(scope, change) do
    entry = change.entry

    group =
      change.current ||
        %Group{
          key: entry["key"],
          scope_kind: scope.kind,
          site_id: scope.site_id,
          preset: preset(entry["preset"])
        }

    changeset = Group.changeset(group, Map.take(entry, ["name", "description"]))
    changeset = if group.id, do: Changeset.optimistic_lock(changeset, :lock_version), else: changeset
    saved = unwrap!(if group.id, do: Repo.update(changeset), else: Repo.insert(changeset))
    Repo.delete_all(from(p in Grant, where: p.group_id == ^saved.id))
    Repo.insert_all(Grant, Enum.map(entry["permissions"], &%{group_id: saved.id, permission_key: &1}))

    Repo.insert!(%AuditEvent{
      actor_id: scope.user_id,
      action: "group.imported",
      group_id: saved.id,
      site_id: scope.site_id,
      before: change.before,
      after: entry
    })
  end

  defp decode(scope, json) when is_binary(json) and byte_size(json) <= @max_bytes do
    case Jason.decode(json) do
      {:ok, %{"format" => @format, "version" => 1, "scope" => kind, "groups" => entries} = document}
      when is_list(entries) and length(entries) <= @max_groups ->
        cond do
          Map.keys(document) -- ["format", "version", "scope", "groups"] != [] ->
            invalid("The file contains unsupported configuration fields.")

          kind != Atom.to_string(scope.kind) ->
            invalid("This file belongs to a different scope type. Export and import within the same scope type.")

          true ->
            validate_entries(scope, entries)
        end

      {:error, _} ->
        invalid("This file is not valid JSON. Choose a Brando group configuration export.")

      _ ->
        invalid("Expected a version 1 Brando authorization export with at most 500 groups.")
    end
  end

  defp decode(_, _), do: invalid("Choose a JSON configuration file smaller than 1 MB.")

  defp validate_entries(scope, entries) do
    catalog = Catalog.all() |> Enum.filter(&(scope.kind in &1.scopes)) |> MapSet.new(& &1.key)

    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, validated} ->
      case validate_entry(entry, catalog) do
        {:ok, entry} ->
          if Enum.any?(validated, &(&1["key"] == entry["key"])),
            do: {:halt, invalid("The file contains duplicate group key: #{entry["key"]}.")},
            else: {:cont, {:ok, [entry | validated]}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.sort_by(entries, & &1["key"])}
      error -> error
    end
  end

  defp validate_entry(%{"key" => key, "name" => name, "permissions" => permissions} = entry, catalog)
       when is_binary(key) and is_binary(name) and is_list(permissions) do
    cond do
      Map.keys(entry) -- ["key", "name", "description", "preset", "permissions"] != [] ->
        invalid("Group #{name} contains unsupported fields. Memberships and database IDs cannot be imported.")

      key == "superuser" or entry["preset"] == "superuser" ->
        invalid("The protected Superuser group cannot be imported.")

      not Regex.match?(~r/\A[a-z0-9][a-z0-9_-]{0,99}\z/, key) ->
        invalid("Group #{name} has an invalid stable key.")

      not valid_preset?(key, entry["preset"]) ->
        invalid("Group #{name} has an invalid preset or reserved key.")

      not Enum.all?(permissions, &(is_binary(&1) and MapSet.member?(catalog, &1))) ->
        invalid("Group #{name} contains unknown permissions or permissions unavailable in this scope.")

      true ->
        case %Group{} |> Group.changeset(Map.take(entry, ["name", "description"])) |> Changeset.apply_action(:insert) do
          {:ok, group} ->
            {:ok,
             %{
               "key" => key,
               "name" => group.name,
               "description" => group.description,
               "preset" => entry["preset"],
               "permissions" => Enum.sort(Enum.uniq(permissions))
             }}

          {:error, _} ->
            invalid("Group #{name} needs a name of 1–100 characters and a description of at most 500 characters.")
        end
    end
  end

  defp validate_entry(_, _), do: invalid("Every group needs a key, name and list of permission keys.")
  defp valid_preset?(key, nil), do: key not in ["user", "editor", "admin", "superuser"]
  defp valid_preset?(key, preset), do: preset in ["user", "editor", "admin"] and key == preset
  defp preset("user"), do: :user
  defp preset("editor"), do: :editor
  defp preset("admin"), do: :admin
  defp preset(nil), do: nil

  defp groups(scope) do
    query =
      from(g in Group,
        where: g.scope_kind == ^scope.kind and (is_nil(g.preset) or g.preset != :superuser),
        order_by: [asc: g.key],
        preload: [:grants, :memberships]
      )

    query =
      if scope.site_id,
        do: from(g in query, where: g.site_id == ^scope.site_id),
        else: from(g in query, where: is_nil(g.site_id))

    Repo.all(query)
  end

  defp serialize(group),
    do: %{
      "key" => group.key,
      "name" => group.name,
      "description" => group.description,
      "preset" => if(group.preset, do: Atom.to_string(group.preset)),
      "permissions" => group.grants |> Enum.map(& &1.permission_key) |> Enum.sort()
    }

  defp revision(groups) do
    groups
    |> Enum.map(&{serialize(&1), &1.lock_version, Enum.sort(Enum.map(&1.memberships, fn m -> m.user_id end))})
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end

  defp authorize(scope), do: if(allowed?(scope), do: :ok, else: {:error, :forbidden})
  defp authorize!(scope), do: unwrap!(authorize(scope))
  defp unwrap!(:ok), do: :ok
  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, reason}), do: Repo.rollback(reason)
  defp invalid(message), do: {:error, {:invalid_config, message}}

  defp transact(fun) do
    case Repo.transaction(fn ->
           Groups.lock!()
           fun.()
         end) do
      {:ok, _} = result ->
        Phoenix.PubSub.broadcast(Brando.pubsub(), "brando:authorization", {:authorization_changed, :all})
        result

      error ->
        error
    end
  end
end
