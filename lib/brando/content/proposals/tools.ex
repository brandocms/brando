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
  import Ecto.Query, only: [from: 2]

  alias Brando.Content
  alias Brando.Content.BlockSlots
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Transfer.{Catalog, Dependencies, Error}
  alias Brando.Media.Folders

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
  # `Brando.Media.Folders.max_page/0`; a literal keeps this module free of a
  # compile-time dependency on it.
  @max_folder_page 100
  @text_limit 160
  # Blocks an outline describes in full; the rest are listed by uid and module
  # only, so a long page stays within a model's budget.
  @outline_budget 150
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
        "Read one entry: its fields and an outline of its blocks — root blocks and their children, nested (uid, module, short text, media with width, height and orientation, variable values). Children are the entries of a multi module, or the blocks of a container or slot. Use block uids for placement and block edits; every block at any depth can be edited, moved or deleted.",
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
        "Describe a module's contract: its text slots (text: safe HTML, header: plain text), media slots with the media they accept, and variables with their types and options. For a multi module it also describes its entry modules, which its blocks hold as children.",
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
      name: "find_media_folders",
      description:
        "Find media library folders by name or path. Returns each folder's id, full path and how many images or videos it holds, with and without its subfolders. Several results mean the name is ambiguous: ask the user which folder.",
      parameters: %{
        type: "object",
        properties: %{kind: %{type: "string", enum: ["image", "video"]}, name: %{type: "string"}},
        required: ["kind", "name"]
      }
    },
    %{
      name: "attach_folder",
      description:
        "Attach the images or videos in one folder to this conversation, as aliases (image1, image2, …) in a fixed order: images by file name, videos in upload order. Already attached media keeps its alias. Returns the total and one page; when next_offset is set, call again with it to attach the rest. Subfolders are only included with subfolders: true.",
      parameters: %{
        type: "object",
        properties: %{
          kind: %{type: "string", enum: ["image", "video"]},
          folder_id: %{type: "integer"},
          subfolders: %{type: "boolean", default: false},
          offset: %{type: "integer", default: 0},
          limit: %{type: "integer", maximum: @max_folder_page}
        },
        required: ["kind", "folder_id"]
      }
    },
    %{
      name: "prepare_proposal",
      description: """
      Validate a complete set of changes and store it for the user to review. Nothing is saved until the user approves it in the admin. Calling this again replaces the proposal under review with a new version. Operations:
      {"op":"create_entry","content_type":T,"ref":R,"fields":{}}
      {"op":"set_fields","target":{"content_type":T,"id":N},"fields":{}}
      {"op":"insert_block","target":{"content_type":T,"id":N}|{"new":R},"field":"blocks","module":"local:N","parent":UID?,"placement":"append"|{"before":UID}|{"after":UID},"values":{},"texts":{},"media":{"slot":"image1"},"uid":UID?}
      {"op":"set_block_text","target":…,"block_uid":UID,"ref":NAME,"text":TEXT}
      {"op":"set_block_media","target":…,"block_uid":UID,"ref":NAME,"asset":"image1"|{"kind":"image","id":N}}
      {"op":"set_block_values","target":…,"block_uid":UID,"values":{}}
      {"op":"move_block","target":…,"block_uid":UID,"placement":"append"|{"before":UID}|{"after":UID}}
      {"op":"delete_block","target":…,"block_uid":UID}
      block_uid is any block in the field, at any depth. Without "parent", insert_block adds a root block; with "parent" it adds a child to that block: an entry module of a multi block, or a module in a container or slot. Placement and move_block anchors are siblings: blocks with the same parent. move_block reorders among siblings ("append" moves last). Operations apply in order, so later ones see earlier moves, deletions and inserts; give insert_block a "uid" of your own to address the new block later. Returns problems to fix; call again with the corrected operations.
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

    roots =
      Map.new(schema.__blocks_fields__(), fn %{name: name} ->
        {name, Enum.map(Map.fetch!(entry, :"entry_#{name}"), & &1.block)}
      end)

    dimensions = dimensions(roots |> Map.values() |> List.flatten())

    {blocks, described} =
      Enum.map_reduce(roots, 0, fn {name, blocks}, described ->
        {blocks, described} = outline(blocks, dimensions, described)
        {{name, blocks}, described}
      end)

    outline = %{
      content_type: Codec.content_type(schema),
      id: entry.id,
      title: Catalog.describe(entry).title,
      status: to_string(Map.get(entry, :status)),
      live: Map.get(entry, :status) == :published,
      fields: scalar_fields(entry),
      blocks: Map.new(blocks)
    }

    if described > @outline_budget,
      do:
        Map.put(
          outline,
          :note,
          "Only the first #{@outline_budget} blocks are described in full; the rest show uid and module. Ask the editor which part to look at."
        ),
      else: outline
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
    description = describe_module(module, origin)

    cond do
      module.multi ->
        Map.merge(description, %{
          entries: module |> entry_modules(origin) |> Enum.map(&describe_module(&1, origin)),
          note:
            "Blocks of this module hold their entries as children (see entry_outline). Change an entry with its own block_uid; add one with insert_block and parent set to the multi block's uid."
        })

      module.parent_id ->
        Map.put(description, :entry_of, "#{origin}:#{module.parent_id}")

      true ->
        description
    end
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

  defp run("find_media_folders", args, %{actor: actor}),
    do: Folders.find(media_kind!(args["kind"]), args["name"], actor)

  defp run("attach_folder", _args, %{conversation_id: nil}),
    do: Error.fail!("Media can only be attached in a conversation.")

  defp run("attach_folder", args, %{actor: actor, conversation_id: conversation_id}) do
    kind = media_kind!(args["kind"])
    offset = max(integer(args["offset"]) || 0, 0)

    page =
      Folders.assets(kind, integer(args["folder_id"]), actor,
        subfolders: args["subfolders"] == true,
        offset: offset,
        limit: integer(args["limit"])
      )

    {:ok, %{attached: attached, unavailable: unavailable}} =
      case Brando.AI.Agent.attach_many(conversation_id, Enum.map(page.ids, &{kind, &1}), actor) do
        {:ok, _} = ok -> ok
        {:error, message} -> Error.fail!(message)
      end

    next = offset + length(page.ids)

    %{
      folder: page.folder,
      subfolders: args["subfolders"] == true,
      total: page.total,
      offset: offset,
      attached: Enum.map(attached, &Map.take(&1, [:alias, :id, :label, :new])),
      unavailable: Enum.map(unavailable, &Map.take(&1, [:id, :reason])),
      next_offset: if(next < page.total, do: next),
      remaining: max(page.total - next, 0)
    }
    |> Map.put(:note, folder_note(page.total, next))
  end

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

  defp describe_module(module, origin) do
    %{
      module: "#{origin}:#{module.id}",
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
            options: if(var.type == :select, do: Enum.map(var.options || [], &option/1)),
            settable: var.type in [:string, :text, :html, :boolean, :select]
          }
        end)
    }
  end

  defp option(%{label: label, value: value}) when label in [nil, "", value], do: value
  defp option(%{label: label, value: value}), do: %{value: value, label: label}

  # The modules a multi module takes as entries.
  defp entry_modules(module, :local) do
    case Content.list_modules(%{filter: %{parent_id: module.id}, preload: [:vars, :refs], order: "asc sequence"}) do
      {:ok, modules} -> modules
      _ -> []
    end
  end

  defp entry_modules(_module, _origin), do: []

  # Outline `blocks` and their children, depth first. `described` counts the
  # blocks outlined in full, against `@outline_budget`.
  defp outline(blocks, dimensions, described) do
    Enum.map_reduce(blocks, described, fn block, described ->
      {children, after_children} = outline(block.children || [], dimensions, described + 1)

      summary =
        block
        |> block_summary(dimensions, described < @outline_budget)
        |> put_kind(block)
        |> then(&if(children == [], do: &1, else: Map.put(&1, :children, children)))

      {summary, after_children}
    end)
  end

  defp block_summary(block, dimensions, full?) do
    module = block.module_id && Content.fetch_module(block.module_id, block.module_origin || :local)
    summary = %{uid: block.uid, type: to_string(block.type), module_name: module && label(module.name)}

    if full?,
      do:
        Map.merge(summary, %{
          module: block.module_id && "#{block.module_origin || :local}:#{block.module_id}",
          active: block.active,
          texts: ref_texts(block.refs),
          media: ref_media(block.refs, dimensions),
          values: var_values(block.vars)
        }),
      else: summary
  end

  defp put_kind(summary, %{type: :slot, slot_name: name}), do: Map.put(summary, :slot, name)
  defp put_kind(summary, %{multi: true}), do: Map.put(summary, :multi, true)
  defp put_kind(summary, _block), do: summary

  defp ref_texts(refs) do
    for %{data: %{type: type, data: data}} = ref <- refs, type in ["text", "header"], into: %{} do
      {ref.name, shorten(HtmlSanitizeEx.strip_tags(data.text || ""))}
    end
  end

  defp ref_media(refs, dimensions) do
    for ref <- refs, kind <- [:image, :video], id = Map.get(ref, :"#{kind}_id"), into: %{} do
      {ref.name, Map.merge(%{kind: kind, id: id}, Map.get(dimensions, {kind, id}, %{}))}
    end
  end

  # Width, height and orientation of the media in `blocks`, in one query per kind.
  defp dimensions(blocks) do
    ids =
      blocks
      |> Enum.flat_map(&tree_refs/1)
      |> Enum.flat_map(fn ref -> for kind <- [:image, :video], id = Map.get(ref, :"#{kind}_id"), do: {kind, id} end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    for {kind, schema} <- [image: Brando.Images.Image, video: Brando.Videos.Video],
        ids = Map.get(ids, kind, []),
        ids != [],
        {id, width, height} <-
          Brando.Repo.all(from(m in schema, where: m.id in ^ids, select: {m.id, m.width, m.height})),
        into: %{},
        do: {{kind, id}, %{width: width, height: height, orientation: orientation(width, height)}}
  end

  defp tree_refs(block), do: (block.refs || []) ++ Enum.flat_map(block.children || [], &tree_refs/1)

  defp orientation(width, height) when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    cond do
      width > height -> "landscape"
      width < height -> "portrait"
      true -> "square"
    end
  end

  defp orientation(_, _), do: nil

  defp var_values(vars) do
    for var <- vars, var.type in [:string, :text, :boolean, :select, :link], into: %{} do
      {var.key, var_value(var)}
    end
  end

  defp var_value(%{type: :boolean} = var), do: var.value_boolean

  # A link names the entry it points to; the editor knows a project by its title.
  defp var_value(%{type: :link, identifier: %{title: title}}) when is_binary(title), do: shorten(title)
  defp var_value(var), do: shorten(var.value)

  defp schema!(name) do
    case Codec.schema(name) do
      {:ok, schema} ->
        if schema in Catalog.schemas(), do: schema, else: Error.fail!("#{name} has no block fields.")

      :error ->
        Error.fail!("Unknown content type #{inspect(name)}. Use list_content_types.")
    end
  end

  defp media_kind!("image"), do: :image
  defp media_kind!("video"), do: :video
  defp media_kind!(_), do: Error.fail!("kind is image or video.")

  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp integer(_), do: nil

  defp folder_note(0, _next), do: "The folder is empty."
  defp folder_note(total, next) when next >= total, do: "All #{total} are attached."

  defp folder_note(total, next),
    do: "#{next} of #{total} are attached so far. Call attach_folder again with next_offset to attach the rest."

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
