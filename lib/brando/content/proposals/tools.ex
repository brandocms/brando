defmodule Brando.Content.Proposals.Tools do
  @moduledoc """
  The tools a content agent uses: read the actor's content, then prepare a
  proposal for review.

  Every tool runs with the authenticated actor in `Context`; nothing a model
  sends can choose the user, site or environment. The tools read, except
  `prepare_proposal`, which stores a proposal version for the user to review.
  No tool approves or applies — that takes the user's click in the admin.

  The same registry serves the admin's embedded agent and BrandoMCP's
  in-process content tools. Results are compact maps, bounded in size, so a
  model does not pay for whole entries.
  """
  alias Brando.Content
  alias Brando.Content.BlockSlots
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Transfer.{Catalog, Dependencies, Error}

  defmodule Context do
    @moduledoc """
    The authenticated side of a tool call.

    `attachments` maps aliases such as `"image1"` to
    `%{kind: :image | :video, id: id, label: label}`. `proposal_id` is the
    conversation's proposal under review; `prepare_proposal` refines it.
    """
    @type t :: %__MODULE__{}
    defstruct [:actor, :conversation_id, :proposal_id, attachments: %{}]
  end

  @max_results 20
  @text_limit 160
  @system_fields ~w(id status publish_at deleted_at marked_as_deleted creator_id updated_by_id inserted_at updated_at
                    sequence edited_at rendered_blocks rendered_blocks_at)

  @definitions [
    %{
      name: "list_content_types",
      description:
        "List the content types the user can edit that have block fields, with their block fields and whether a page preview exists.",
      parameters: %{type: "object", properties: %{}}
    },
    %{
      name: "describe_content_type",
      description:
        "Describe a content type's editable fields (name, type, required) and block fields. New entries are always created as drafts.",
      parameters: %{
        type: "object",
        properties: %{content_type: %{type: "string"}},
        required: ["content_type"]
      }
    },
    %{
      name: "search_entries",
      description: "Search entries the user can edit by title. Returns ids to use as proposal targets.",
      parameters: %{
        type: "object",
        properties: %{
          query: %{type: "string"},
          content_type: %{type: "string", description: "Limit to one content type."},
          limit: %{type: "integer", maximum: @max_results}
        },
        required: ["query"]
      }
    },
    %{
      name: "entry_outline",
      description:
        "Read one entry: its fields and an outline of its root blocks (uid, module, short text, media, values). Use block uids for placement and block edits.",
      parameters: %{
        type: "object",
        properties: %{content_type: %{type: "string"}, id: %{type: "integer"}},
        required: ["content_type", "id"]
      }
    },
    %{
      name: "list_modules",
      description: "List the modules that may be inserted into a content type's block field.",
      parameters: %{
        type: "object",
        properties: %{content_type: %{type: "string"}, field: %{type: "string", default: "blocks"}},
        required: ["content_type"]
      }
    },
    %{
      name: "describe_module",
      description:
        "Describe a module's contract: its text slots (text: safe HTML, header: plain text), media slots with the media they accept, and variables with their types and options.",
      parameters: %{type: "object", properties: %{module: %{type: "string"}}, required: ["module"]}
    },
    %{
      name: "list_attachments",
      description: "List the media the user attached to this conversation, by alias (image1, video1, …).",
      parameters: %{type: "object", properties: %{}}
    },
    %{
      name: "search_assets",
      description: "Search the media library for images or videos by title or filename.",
      parameters: %{
        type: "object",
        properties: %{
          kind: %{type: "string", enum: ["image", "video"]},
          query: %{type: "string"},
          limit: %{type: "integer", maximum: @max_results}
        },
        required: ["kind"]
      }
    },
    %{
      name: "prepare_proposal",
      description: """
      Validate a complete set of changes and store it for the user to review. Nothing is saved until the user approves it in the admin. Calling this again replaces the proposal under review with a new version. Operations:
      {"op":"create_entry","content_type":T,"ref":R,"fields":{}}
      {"op":"set_fields","target":{"content_type":T,"id":N},"fields":{}}
      {"op":"insert_block","target":{"content_type":T,"id":N}|{"new":R},"field":"blocks","module":"local:N","placement":"append"|{"before":UID}|{"after":UID},"values":{},"texts":{},"media":{"slot":"image1"}}
      {"op":"set_block_text","target":…,"block_uid":UID,"ref":NAME,"text":TEXT}
      {"op":"set_block_media","target":…,"block_uid":UID,"ref":NAME,"asset":"image1"|{"kind":"image","id":N}}
      {"op":"set_block_values","target":…,"block_uid":UID,"values":{}}
      Returns problems to fix; call again with the corrected operations.
      """,
      parameters: %{
        type: "object",
        properties: %{
          summary: %{type: "string", description: "One sentence describing the change for the reviewer."},
          operations: %{type: "array", items: %{type: "object"}}
        },
        required: ["summary", "operations"]
      }
    }
  ]

  @names Enum.map(@definitions, & &1.name)

  @doc "Tool definitions: name, description and JSON-schema parameters."
  @spec definitions() :: [map()]
  def definitions, do: @definitions

  @doc "Call tool `name` with decoded JSON `args`."
  @spec call(String.t(), map(), Context.t()) :: {:ok, map()} | {:error, String.t()}
  def call(name, args, %Context{actor: actor} = context) when name in @names and not is_nil(actor) do
    Error.protect(fn -> run(name, args || %{}, context) end)
  end

  def call(name, _args, %Context{actor: nil}) when name in @names,
    do: {:error, "Content tools need an authenticated user."}

  def call(name, _args, _context), do: {:error, "Unknown tool #{inspect(name)}."}

  defp run("list_content_types", _args, %{actor: actor}) do
    types =
      for schema <- Catalog.schemas(), Brando.Authorization.Boundary.authorize(actor, :update, schema) == :ok do
        %{
          content_type: Codec.content_type(schema),
          label: Brando.Blueprint.get_singular(schema),
          block_fields: block_fields(schema),
          page_preview: Brando.LivePreview.has_live_preview_target(schema)
        }
      end

    %{content_types: types}
  end

  defp run("describe_content_type", args, _context) do
    schema = schema!(args["content_type"])

    attributes =
      for %{name: name, type: type, opts: opts} <- Brando.Blueprint.Attributes.__attributes__(schema),
          to_string(name) not in @system_fields do
        %{name: to_string(name), type: inspect_type(type), required: !!(opts || %{})[:required]}
      end

    references =
      for %{name: name, type: :belongs_to} = relation <- Brando.Blueprint.Relations.__relations__(schema),
          name not in [:creator, :updated_by] do
        %{name: "#{name}_id", type: "id", required: !!(relation.opts || %{})[:required]}
      end

    assets =
      for %{name: name, type: type} <- Brando.Blueprint.Assets.__assets__(schema), type in [:image, :video] do
        %{name: "#{name}_id", type: "#{type} id", required: false}
      end

    %{
      content_type: Codec.content_type(schema),
      label: Brando.Blueprint.get_singular(schema),
      fields: attributes ++ references ++ assets,
      block_fields: block_fields(schema),
      publication: "New entries are created as drafts. Existing entries keep their status."
    }
  end

  defp run("search_entries", args, %{actor: actor}) do
    schemas = if type = args["content_type"], do: [to_string(schema!(type))]

    results =
      actor
      |> Catalog.search(to_string(args["query"] || ""), action: :update, schemas: schemas)
      |> Enum.take(limit(args))
      |> Enum.map(fn entry ->
        %{
          content_type: entry.schema |> Codec.schema() |> elem(1) |> Codec.content_type(),
          id: entry.id,
          title: entry.title,
          status: entry.status,
          language: entry.language,
          url: entry.url
        }
      end)

    %{entries: results}
  end

  defp run("entry_outline", args, %{actor: actor}) do
    schema = schema!(args["content_type"])
    entry = Catalog.load!(schema, args["id"], actor, :read)

    %{
      content_type: Codec.content_type(schema),
      id: entry.id,
      title: Catalog.describe(entry).title,
      status: to_string(Map.get(entry, :status)),
      live: Map.get(entry, :status) == :published,
      fields: scalar_fields(entry),
      blocks:
        Map.new(schema.__blocks_fields__(), fn %{name: name} ->
          {name, Enum.map(Map.fetch!(entry, :"entry_#{name}"), &outline(&1.block))}
        end)
    }
  end

  defp run("list_modules", args, _context) do
    schema = schema!(args["content_type"])
    field = args["field"] || "blocks"

    unless Enum.any?(schema.__blocks_fields__(), &(to_string(&1.name) == field)),
      do: Error.fail!("#{args["content_type"]} has no block field #{field}.")

    modules =
      schema
      |> Proposals.module_set(field)
      |> BlockSlots.modules()
      |> Enum.map(fn module ->
        %{
          module: "local:#{module.id}",
          name: label(module.name),
          namespace: label(module.namespace),
          help: shorten(label(module.help_text)),
          slots: Enum.map(module.refs || [], &"#{&1.name} (#{&1.data.type})")
        }
      end)

    %{modules: modules}
  end

  defp run("describe_module", args, _context) do
    {origin, id} = Content.SharedLibrary.reference(args["module"])
    module = Content.fetch_module(id, origin) || Error.fail!("Unknown module #{inspect(args["module"])}.")

    %{
      module: "#{origin}:#{id}",
      name: label(module.name),
      help: label(module.help_text),
      insertable: BlockSlots.suitable_module?(module),
      slots:
        Enum.map(module.refs || [], fn ref ->
          %{
            name: ref.name,
            kind: ref.data.type,
            description: ref.description,
            settable:
              cond do
                ref.data.type in ["text", "header"] -> "text"
                Proposals.accepts(ref) != [] -> Enum.map_join(Proposals.accepts(ref), " or ", &to_string/1)
                true -> "no"
              end
          }
        end),
      variables:
        Enum.map(module.vars || [], fn var ->
          %{
            key: var.key,
            type: to_string(var.type),
            label: var.label,
            instructions: var.instructions,
            options: if(var.type == :select, do: Enum.map(var.options || [], & &1.value)),
            settable: var.type in [:string, :text, :html, :boolean, :select]
          }
        end)
    }
  end

  defp run("list_attachments", _args, %{attachments: attachments}) do
    %{
      attachments:
        attachments
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {alias, attachment} ->
          %{alias: alias, kind: to_string(attachment.kind), id: attachment.id, label: attachment[:label]}
        end)
    }
  end

  defp run("search_assets", %{"kind" => kind} = args, %{actor: actor}) when kind in ~w(image video) do
    assets =
      kind
      |> Dependencies.options(actor, to_string(args["query"] || ""))
      |> Enum.take(limit(args))
      |> Enum.map(&%{kind: kind, id: &1.id, label: &1.label})

    %{assets: assets}
  end

  defp run("search_assets", _args, _context), do: Error.fail!("kind is image or video.")

  defp run("prepare_proposal", args, context) do
    aliases = Map.new(context.attachments, fn {alias, a} -> {alias, {a.kind, a.id}} end)

    with {:ok, operations} <- Codec.decode_all(List.wrap(args["operations"]), aliases),
         {:ok, proposal} <-
           Proposals.propose(operations, context.actor,
             conversation_id: context.conversation_id,
             supersedes: refinable(context),
             summary: args["summary"]
           ) do
      review(proposal)
    else
      {:error, message} -> Error.fail!(message)
    end
  end

  # Refine the conversation's proposal while it is under review; after it is
  # applied or cancelled, a new proposal starts at version 1.
  defp refinable(%{proposal_id: nil}), do: nil

  defp refinable(%{proposal_id: id, actor: actor}) do
    case Proposals.get(id, actor) do
      {:ok, %{status: status}} when status in ~w(pending approved) -> id
      _ -> nil
    end
  end

  @doc "A compact review of a stored proposal, as `prepare_proposal` returns it."
  @spec review(Proposals.Proposal.t()) :: map()
  def review(proposal) do
    %{
      proposal_id: proposal.id,
      version: proposal.version,
      applicable: proposal.problems == [],
      problems:
        Enum.map(proposal.problems, fn problem ->
          %{operation: problem[:operation], code: problem.code, message: problem.message}
          |> Map.merge(if(problem[:target], do: %{target: target_key(problem.target)}, else: %{}))
        end),
      effects: Map.update!(proposal.effects, :live, fn live -> Enum.map(live, &target_key/1) end),
      note: "The user reviews and approves this in the admin. Nothing is saved yet."
    }
  end

  defp target_key(target) when is_binary(target), do: target
  defp target_key(target), do: Proposals.Proposal.key(target)

  defp block_fields(schema) do
    Enum.map(schema.__blocks_fields__(), fn %{name: name} ->
      %{field: to_string(name), module_set: Proposals.module_set(schema, to_string(name)) || "all"}
    end)
  end

  defp scalar_fields(entry) do
    for {name, value} <- Map.from_struct(entry),
        is_binary(value) or is_number(value) or is_boolean(value),
        to_string(name) not in @system_fields,
        into: %{},
        do: {name, shorten(value)}
  end

  defp outline(block) do
    module = block.module_id && Content.fetch_module(block.module_id, block.module_origin || :local)

    %{
      uid: block.uid,
      type: to_string(block.type),
      module: block.module_id && "#{block.module_origin || :local}:#{block.module_id}",
      module_name: module && label(module.name),
      active: block.active,
      texts: ref_texts(block.refs),
      media: ref_media(block.refs),
      values: var_values(block.vars),
      children: length(block.children || [])
    }
  end

  defp ref_texts(refs) do
    for %{data: %{type: type, data: data}} = ref <- refs, type in ["text", "header"], into: %{} do
      {ref.name, shorten(HtmlSanitizeEx.strip_tags(data.text || ""))}
    end
  end

  defp ref_media(refs) do
    for ref <- refs, kind <- [:image, :video], id = Map.get(ref, :"#{kind}_id"), into: %{} do
      {ref.name, %{kind: kind, id: id}}
    end
  end

  defp var_values(vars) do
    for var <- vars, var.type in [:string, :text, :boolean, :select], into: %{} do
      {var.key, if(var.type == :boolean, do: var.value_boolean, else: shorten(var.value))}
    end
  end

  defp schema!(name) do
    case Codec.schema(name) do
      {:ok, schema} ->
        if schema in Catalog.schemas(), do: schema, else: Error.fail!("#{name} has no block fields.")

      :error ->
        Error.fail!("Unknown content type #{inspect(name)}. Use list_content_types.")
    end
  end

  defp limit(args), do: min(max(args["limit"] || 10, 1), @max_results)

  defp label(%{} = map), do: map["en"] || map |> Map.values() |> List.first()
  defp label(value), do: value

  defp shorten(nil), do: nil

  defp shorten(value) when is_binary(value) and byte_size(value) > @text_limit,
    do: String.slice(value, 0, @text_limit) <> "…"

  defp shorten(value), do: value

  defp inspect_type(type) when is_atom(type), do: to_string(type)
  defp inspect_type(type), do: inspect(type)
end
