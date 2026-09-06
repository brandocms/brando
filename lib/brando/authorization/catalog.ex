defmodule Brando.Authorization.Catalog do
  @moduledoc """
  The code-owned catalog of actions exposed by Brando and application Blueprints.

  Permission keys are stable strings. Labels are presentation; neither labels nor
  group names confer authority. New capabilities are never implicitly added to an
  existing group's grants.
  """

  @content_scopes [:standalone, :site]
  @internal_schemas [
    Brando.Revisions.Revision,
    Brando.Content.Var,
    Brando.Sites.Preview,
    Brando.Content.Block,
    Brando.Content.Identifier
  ]
  @operation_resources [
    {:backend, "brando.admin", "Backend", "Workspace", [:access], [:standalone, :site, :installation]},
    {:profile, "brando.profile", "Own profile", "Workspace", [:read, :update], [:standalone, :site, :installation]},
    {:groups, "brando.groups", "Groups", "Access", [:read, :create, :update, :delete, :assign],
     [:standalone, :site, :installation]},
    {:sites, "brando.sites", "Sites", "Installation", [:read, :create, :update, :delete], [:installation]},
    {:environments, "brando.environments", "Environments", "Settings", [:read, :create, :update, :delete, :promote],
     [:site]},
    {:publishing, "brando.publishing", "Builds & deployments", "Settings", [:read, :build, :deploy, :schedule], [:site]},
    {:frontend_assets, "brando.frontend_assets", "Frontend assets", "Installation", [:read, :update], [:installation]},
    {:shared_library, "brando.shared_library", "Shared content library", "Installation", [:read, :update],
     [:installation]},
    {:utilities, "brando.utilities", "Utilities & caches", "Settings", [:read, :update], [:standalone, :site]}
  ]

  @doc "Lists all permissions, including application resources."
  def all do
    (operations() ++ Enum.flat_map(schemas(), &for_schema/1))
    |> validate!()
    |> Enum.sort_by(&{&1.section, &1.label, &1.action})
  end

  @doc "Rejects ambiguous keys instead of silently combining unrelated resources."
  def validate!(permissions) do
    permissions
    |> Enum.group_by(& &1.key)
    |> Enum.each(fn {key, entries} ->
      subjects = entries |> Enum.map(& &1.subject) |> Enum.uniq()

      if length(subjects) > 1,
        do:
          raise(
            ArgumentError,
            "duplicate authorization key #{inspect(key)} for #{inspect(subjects)}; declare distinct authorization keys"
          )
    end)

    Enum.uniq_by(permissions, & &1.key)
  end

  @doc "Finds a supported permission. Unknown actions/resources return nil."
  def get(action, %{__struct__: schema}), do: get(action, schema)

  def get(action, subject) when is_atom(action) and is_atom(subject) do
    permissions = if blueprint?(subject), do: for_schema(subject), else: operations()

    case Enum.find(permissions, &(&1.subject == subject and &1.action == action)) do
      nil ->
        nil

      permission ->
        conflicts =
          schemas()
          |> Enum.filter(fn schema ->
            schema != subject and schema not in @internal_schemas and resource_key(schema) == permission.resource
          end)
          |> Enum.flat_map(&for_schema/1)

        validate!([permission | operations() ++ conflicts])
        permission
    end
  end

  def get(_, _), do: nil

  @doc "Returns the catalog entry for a persisted permission key."
  def fetch(key) when is_binary(key), do: Enum.find(all(), &(&1.key == key))
  def fetch(_), do: nil

  @doc "The supported actions for one Blueprint, derived from its context API."
  def for_schema(schema) do
    if blueprint?(schema) and schema not in @internal_schemas and not is_nil(schema.__schema__(:source)) do
      options = if function_exported?(schema, :__authorization__, 0), do: schema.__authorization__(), else: []
      context = schema.__modules__().context
      naming = schema.__naming__()
      Code.ensure_loaded?(context)

      actions =
        [
          {:read, "get_#{naming.singular}", 1},
          {:create, "create_#{naming.singular}", 2},
          {:update, "update_#{naming.singular}", 3},
          {:delete, "delete_#{naming.singular}", 2},
          {:duplicate, "duplicate_#{naming.singular}", 2}
        ]
        |> Enum.filter(fn {_action, name, arity} -> exported?(context, name, arity) end)
        |> Enum.map(&elem(&1, 0))
        |> extra_actions(schema)
        |> Kernel.++(Keyword.get(options, :actions, []))
        |> Enum.uniq()

      resource = resource_key(schema)
      section = Keyword.get(options, :section, section(schema))
      scopes = if schema == Brando.Users.User, do: [:standalone, :installation], else: @content_scopes
      label = Brando.Blueprint.get_plural(schema)

      Enum.map(actions, &permission(schema, resource, label, section, &1, scopes))
    else
      []
    end
  end

  @doc "Lists registered schemas, without turning submitted strings into atoms."
  def schemas do
    [:brando, Brando.RuntimeConfig.get(:otp_app)]
    |> Enum.uniq()
    |> Enum.flat_map(fn app ->
      case :application.get_key(app, :modules) do
        {:ok, modules} -> modules
        _ -> []
      end
    end)
    |> Enum.filter(&blueprint?/1)
    |> Enum.uniq()
  end

  @doc "Resolves a schema name against registered resources only."
  def schema(name) when is_binary(name), do: Enum.find(schemas(), &(to_string(&1) == name and for_schema(&1) != []))
  def schema(schema) when is_atom(schema), do: if(schema in schemas() and for_schema(schema) != [], do: schema)
  def schema(_), do: nil

  @doc "Default grants for a fresh preset. Existing groups are not modified."
  def preset_permissions(:user, _kind), do: []
  def preset_permissions(:superuser, _kind), do: []

  def preset_permissions(preset, kind) do
    all()
    |> Enum.filter(&(kind in &1.scopes))
    |> Enum.filter(fn permission ->
      case preset do
        :admin ->
          permission.delegable

        :editor ->
          permission.section in ["Content", "Media"] or permission.subject in [:backend, :profile] or
            (permission.action == :read and
               permission.subject in [
                 Brando.Content.Module,
                 Brando.Content.Container,
                 Brando.Content.Palette,
                 Brando.Content.ModuleSet,
                 Brando.Content.TableTemplate,
                 Brando.Content.Template,
                 Brando.Sites.GlobalSet
               ])

        _ ->
          false
      end
    end)
    |> Enum.map(& &1.key)
  end

  defp operations do
    Enum.flat_map(@operation_resources, fn {subject, key, label, section, actions, scopes} ->
      Enum.map(actions, &permission(subject, key, label, section, &1, scopes))
    end)
  end

  defp permission(subject, resource, label, section, action, scopes) do
    %{
      key: "#{resource}.#{action}",
      resource: resource,
      subject: subject,
      label: label,
      section: section,
      action: action,
      scopes: scopes,
      delegable: section != "Installation" and subject != Brando.Users.User
    }
  end

  defp default_key(schema) do
    namespace = schema.__modules__().application |> Module.split() |> Enum.map_join("_", &Macro.underscore/1)
    "#{namespace}.#{schema.__schema__(:source)}"
  end

  defp resource_key(schema) do
    options = if function_exported?(schema, :__authorization__, 0), do: schema.__authorization__(), else: []
    Keyword.get(options, :key, default_key(schema))
  end

  defp section(schema) do
    case schema.__schema__(:source) do
      source when source in ["images", "files", "videos", "galleries", "media_folders"] -> "Media"
      "users" -> "Access"
      "sites_" <> _ -> "Settings"
      "navigation_" <> _ -> "Settings"
      "content_" <> _ -> "Settings"
      _ -> "Content"
    end
  end

  defp extra_actions(actions, schema) do
    fields = schema.__schema__(:fields)

    actions
    |> maybe_add(:read in actions, :export)
    |> maybe_add(:update in actions and :sequence in fields, :reorder)
    |> maybe_add(:update in actions and :deleted_at in fields, :restore)
    |> maybe_add(:update in actions and schema.has_trait(Brando.Trait.Status), :publish)
    |> maybe_add(:update in actions and :publish_at in fields, :schedule)
  end

  defp maybe_add(actions, true, action), do: actions ++ [action]
  defp maybe_add(actions, false, _action), do: actions

  defp exported?(context, name, arity) do
    Code.ensure_loaded?(context) and
      Enum.any?(context.__info__(:functions), fn {fun, count} ->
        Atom.to_string(fun) == name and count == arity
      end)
  end

  defp blueprint?(module) do
    is_atom(module) and Code.ensure_loaded?(module) and function_exported?(module, :__blueprint__, 0)
  end
end
