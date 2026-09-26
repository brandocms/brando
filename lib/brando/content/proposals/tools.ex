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
  alias Brando.Content.Proposals.BlockTree
  alias Brando.Content.Proposals.Codec
  alias Brando.Content.Proposals.EntryFields
  alias Brando.Content.Proposals.RefConfig
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
  # Blocks an outline describes in full, tried in turn until the outline fits
  # `@outline_bytes`; the rest are listed by uid and module only, so a long
  # page stays within a model's budget.
  @outline_budgets [150, 80, 40, 20, 10, 0]
  @outline_bytes 20_000
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
        "Read one entry: its fields, its own media (such as a listing image) and an outline of its blocks — root blocks and their children, nested (uid, module, active, short text, media, refs_off, settings that differ from the defaults, variable values, anchor, description). Media carries width, height and orientation. refs_off lists refs that are switched off. Children are the entries of a multi module, or the blocks of a container or slot. Use block uids for placement and block edits; every block at any depth can be edited, switched on or off, moved or deleted.",
      parameters: %{
        type: "object",
        properties: %{
          content_type: %{type: "string"},
          id: %{type: "integer"},
          block_uid: %{type: "string", description: "Read only this block and everything below it, in full."}
        },
        required: ["content_type", "id"]
      }
    },
    %{
      name: "list_modules",
      description:
        "List the modules that may be inserted at the root of a content type's block field. Multi modules (multi: true) hold entries: insert the multi block with a uid of your own, then its entries with parent set to that uid (describe_module lists them).",
      parameters: %{
        type: "object",
        properties: %{content_type: %{type: "string"}, field: %{type: "string", default: "blocks"}},
        required: ["content_type"]
      }
    },
    %{
      name: "describe_module",
      description:
        "Describe a module's contract: its slots — what each takes (text, media) and the settings it has, such as a heading's level or a picture's alt text — and its variables with their types and options. For a multi module it also describes its entry modules, which its blocks hold as children.",
      parameters: %{type: "object", properties: %{module: %{type: "string"}}, required: ["module"]}
    },
    %{
      name: "request_media",
      description:
        "Ask the editor for images or videos a request needs and that you do not have — for example photos of a typeface for an article about it. The editor sees your reason and library suggestions for query, and can pick some, browse the library, upload, or tell you to choose. Then end your turn with a short question and wait. Their picks arrive as attachments.",
      parameters: %{
        type: "object",
        properties: %{
          kind: %{type: "string", enum: ["image", "video"]},
          reason: %{type: "string", description: "One sentence the editor reads: what the media is for."},
          query: %{type: "string", description: "Words to suggest library media by (title, file name, folder)."},
          from_entry: %{
            type: "object",
            description:
              ~s(An entry whose media to suggest first, such as the project an article is about: {"content_type":T,"id":N}.)
          },
          count: %{type: "integer", description: "How many you need, if you know."}
        },
        required: ["kind", "reason"]
      }
    },
    %{
      name: "look_at_media",
      description:
        "See images or videos (a video by its thumbnail), when you choose media by what they show — which photos show the typeface, which cover suits a case. You get small pictures, in the order of ids, after this result. Look only among candidates you are choosing between; up to 24 at a time.",
      parameters: %{
        type: "object",
        properties: %{
          kind: %{type: "string", enum: ["image", "video"]},
          ids: %{type: "array", items: %{type: "integer"}, maxItems: 24}
        },
        required: ["kind", "ids"]
      }
    },
    %{
      name: "list_entry_media",
      description:
        "List the images and videos an entry uses — in its blocks, galleries and media fields — with title, width, height and orientation. Use it to choose media for related content, such as an article about a project.",
      parameters: %{
        type: "object",
        properties: %{
          content_type: %{type: "string"},
          id: %{type: "integer"},
          kind: %{type: "string", enum: ["image", "video"]}
        },
        required: ["content_type", "id"]
      }
    },
    %{
      name: "list_selection_options",
      description:
        "List the entries a datasource block that shows chosen entries can pick from (describe_module says datasource: selection or single), as identifier ids for set_block_selection.",
      parameters: %{
        type: "object",
        properties: %{
          module: %{type: "string"},
          language: %{type: "string", description: "The entry's language; the options are per language."},
          query: %{type: "string", description: "Filter by title."}
        },
        required: ["module"]
      }
    },
    %{
      name: "list_attachments",
      description: "List the media the user attached to this conversation, by alias (image1, video1, …).",
      parameters: %{type: "object", properties: %{}}
    },
    %{
      name: "search_assets",
      description: "Search the media library for images, videos or files by title or filename.",
      parameters: %{
        type: "object",
        properties: %{
          kind: %{type: "string", enum: ["image", "video", "file"]},
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
      {"op":"move_block","target":…,"block_uid":UID,"placement":"append"|{"before":UID}|{"after":UID}|{"into":UID}}
      {"op":"set_block_active","target":…,"block_uid":UID,"ref":NAME?,"active":true|false}
      {"op":"delete_block","target":…,"block_uid":UID}
      {"op":"copy_block","target":…,"block_uid":UID,"placement":"append"|{"before":UID}|{"after":UID}|{"into":UID},"uid":UID?}
      {"op":"set_block_details","target":…,"block_uid":UID,"anchor":TEXT?,"description":TEXT?}
      {"op":"set_ref_config","target":…,"block_uid":UID,"ref":NAME,"config":{}}
      {"op":"set_block_table","target":…,"block_uid":UID,"rows":[{KEY:VALUE}]}
      {"op":"set_block_selection","target":…,"block_uid":UID,"identifiers":[ID]}
      Media ("media" in insert_block, "asset" in set_block_media) is "image1", {"kind":"image"|"video"|"file","id":N}, or {"gallery":[media, …]} for a gallery ref: its full content, in order. texts and set_block_text take what describe_module lists for the slot. copy_block copies a block with everything below it ("append" puts the copy last among the original's siblings); with "to":{"content_type":T,"id":N}|{"new":R} (and "to_field") it copies a saved block to another entry or block field — to move it there, copy it and delete_block the original. set_block_table replaces a table block's rows (describe_module lists the row variables). set_block_selection sets the entries a selection datasource block shows. In any text, link to an entry with <a href="entry:CONTENT_TYPE:ID">; it becomes a link that follows the entry's address. List fields (describe_content_type: "list of …") take the whole list: ids, or entries as {"content_type":T,"id":N}. set_block_details sets the block's anchor (the id a link jumps to) and description (the editor's label); "" clears one. set_ref_config changes a slot's settings as describe_module lists them (insert_block takes "configs":{slot:{…}} too). Entry fields in create_entry and set_fields take media the same way for image, video and file fields (such as meta_image_id).
      block_uid is any block in the field, at any depth. Without "parent", insert_block adds a root block (multi modules too); with "parent" it adds a child to that block: an entry module of a multi block, or a module in a container or slot. insert_block's placement anchors are siblings under that parent. move_block keeps the block and its content: "append" moves it last among its siblings, {"before"/"after":UID} moves it next to any block — into that block's parent — and {"into":UID} to the end of a block's children; the new parent must accept the module. set_block_active switches a block off or on, or with "ref" one of its refs (for example a cover image, so a template can fall back to something else); switched-off content is kept. Values follow describe_module's "settable" for each variable. Operations apply in order, so later ones see earlier moves, deletions and inserts; give insert_block a "uid" of your own to address the new block later. Returns problems to fix; call again with the corrected operations.
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
      fields: attributes ++ references ++ assets ++ EntryFields.describe(schema),
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
    entry = schema |> Catalog.load!(args["id"], actor, :read) |> EntryFields.preload()

    roots =
      Map.new(schema.__blocks_fields__(), fn %{name: name} ->
        {name, Enum.map(Map.fetch!(entry, :"entry_#{name}"), & &1.block)}
      end)

    # One part of a long entry, in full: a block and everything below it.
    roots =
      case args["block_uid"] do
        uid when is_binary(uid) ->
          case roots |> Map.values() |> List.flatten() |> BlockTree.find_saved(uid) do
            {block, _parent, _index} -> %{part: [block]}
            nil -> Error.fail!("No block #{uid} in this entry.")
          end

        _ ->
          roots
      end

    assets = entry_assets(schema, entry)
    dimensions = dimensions(roots |> Map.values() |> List.flatten(), Map.values(assets))

    head =
      %{
        content_type: Codec.content_type(schema),
        id: entry.id,
        title: Catalog.describe(entry).title,
        status: to_string(Map.get(entry, :status)),
        live: Map.get(entry, :status) == :published,
        fields: scalar_fields(entry),
        lists:
          for(
            {name, _} <- EntryFields.lists(schema),
            current = EntryFields.current(entry, name),
            current not in [nil, ""],
            into: %{},
            do: {name, current}
          ),
        media: Map.new(assets, fn {name, {kind, id}} -> {name, media_summary(kind, id, dimensions)} end)
      }
      |> put_present(:languages, languages(entry))

    Enum.find_value(@outline_budgets, fn budget ->
      {blocks, described} =
        Enum.map_reduce(roots, 0, fn {name, blocks}, described ->
          {blocks, described} = outline(blocks, dimensions, described, budget)
          {{name, blocks}, described}
        end)

      outline = Map.put(head, :blocks, Map.new(blocks))

      outline =
        if described > budget,
          do:
            Map.put(
              outline,
              :note,
              "Only the first #{budget} blocks are described in full; the rest show uid and module. Read one part in full with entry_outline and block_uid."
            ),
          else: outline

      if budget == 0 or byte_size(Jason.encode!(outline)) <= @outline_bytes, do: outline
    end)
  end

  defp run("list_modules", args, _context) do
    schema = schema!(args["content_type"])
    field = args["field"] || "blocks"

    unless Enum.any?(schema.__blocks_fields__(), &(to_string(&1.name) == field)),
      do: Error.fail!("#{args["content_type"]} has no block field #{field}.")

    set = Proposals.module_set(schema, field)

    modules =
      (BlockSlots.modules(set) ++ multi_modules(set))
      |> Enum.sort_by(& &1.sequence)
      |> Enum.map(fn module ->
        %{
          module: "local:#{module.id}",
          name: label(module.name),
          namespace: label(module.namespace),
          help: shorten(label(module.help_text)),
          slots: Enum.map(module.refs || [], &"#{&1.name} (#{&1.data.type})")
        }
        |> then(&if(module.multi, do: Map.put(&1, :multi, true), else: &1))
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

  defp run("request_media", args, %{actor: actor}) do
    kind = media_kind!(args["kind"])

    from_entry =
      case args["from_entry"] do
        %{"content_type" => type, "id" => id} -> for {^kind, id} <- entry_media(schema!(type), id, actor), do: id
        _ -> []
      end

    suggested = Enum.take(Enum.uniq(from_entry ++ library_search(kind, args["query"], actor)), 24)

    %{
      asked: true,
      kind: kind,
      suggested: suggested,
      note:
        "The editor is asked, with #{length(suggested)} library suggestions. End your turn with a short question and wait for their reply; what they pick arrives as attachments (list_attachments)."
    }
  end

  # The pictures are not in the result: `Brando.AI.Agent.Loop` attaches them
  # from `look`, so the stored conversation holds references only.
  defp run("look_at_media", args, %{actor: actor}) do
    kind = media_kind!(args["kind"])
    ids = args["ids"] |> List.wrap() |> Enum.map(&integer/1) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.take(24)

    readable =
      Enum.filter(ids, fn id ->
        match?({:ok, _}, Error.protect(fn -> Dependencies.load!(to_string(kind), id, actor) end))
      end)

    dimensions = dimensions([], Enum.map(readable, &{kind, &1}))
    titles = titles(kind, readable)

    %{
      look: Enum.map(readable, &[to_string(kind), &1]),
      media:
        readable
        |> Enum.with_index(1)
        |> Enum.map(fn {id, n} ->
          Map.merge(%{picture: n, kind: kind, id: id, title: titles[id]}, Map.get(dimensions, {kind, id}, %{}))
        end),
      unavailable: ids -- readable,
      note: "The pictures follow, numbered in this order."
    }
  end

  defp run("list_entry_media", args, %{actor: actor}) do
    media = entry_media(schema!(args["content_type"]), args["id"], actor)
    media = if kind = args["kind"], do: Enum.filter(media, &(elem(&1, 0) == media_kind!(kind))), else: media
    dimensions = dimensions([], media)
    titles = Map.new([:image, :video], fn kind -> {kind, titles(kind, for({^kind, id} <- media, do: id))} end)

    %{
      media:
        media
        |> Enum.take(60)
        |> Enum.map(fn {kind, id} ->
          Map.merge(%{kind: kind, id: id, title: titles[kind][id]}, Map.get(dimensions, {kind, id}, %{}))
        end),
      total: length(media)
    }
  end

  defp run("list_selection_options", args, _context) do
    {origin, id} = Content.SharedLibrary.reference(args["module"])
    module = Content.fetch_module(id, origin) || Error.fail!("Unknown module #{inspect(args["module"])}.")

    unless module.datasource && module.datasource_type in [:selection, :single],
      do: Error.fail!("This module does not show chosen entries.")

    query = String.downcase(to_string(args["query"] || ""))

    options =
      module
      |> Proposals.selection_options(args["language"])
      |> Enum.filter(&String.contains?(String.downcase(option_title(&1)), query))

    %{
      total: length(options),
      options:
        options
        |> Enum.take(100)
        |> Enum.map(&selection_option/1),
      note: if(length(options) > 100, do: "Only the first 100 are listed. Narrow with query.")
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

  defp run("search_assets", %{"kind" => kind} = args, %{actor: actor}) when kind in ~w(image video file) do
    kind = String.to_existing_atom(kind)

    ids =
      if to_string(args["query"] || "") == "",
        do: kind |> to_string() |> Dependencies.options(actor, "") |> Enum.map(& &1.id),
        else: library_search(kind, args["query"], actor)

    ids = Enum.take(ids, limit(args))

    titles = titles(kind, ids)
    dimensions = if kind in [:image, :video], do: dimensions([], Enum.map(ids, &{kind, &1})), else: %{}

    %{assets: Enum.map(ids, &Map.merge(%{kind: kind, id: &1, label: titles[&1]}, Map.get(dimensions, {kind, &1}, %{})))}
  end

  defp run("search_assets", _args, _context), do: Error.fail!("kind is image, video or file.")

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
    |> then(fn review ->
      case Proposals.notes(proposal) do
        [] ->
          review

        notes ->
          Map.put(review, :unchanged, %{
            operations: notes,
            advice: "These change nothing. Drop them, or tell the editor why."
          })
      end
    end)
  end

  defp target_key(target) when is_binary(target), do: target
  defp target_key(target), do: Proposals.Proposal.key(target)

  # Every image and video an entry uses, in the order its blocks show them.
  defp entry_media(schema, id, actor) do
    entry = Catalog.load!(schema, id, actor, :read)
    blocks = schema.__blocks_fields__() |> Enum.flat_map(&Map.fetch!(entry, :"entry_#{&1.name}")) |> Enum.map(& &1.block)

    blocks
    |> Enum.flat_map(&tree_media/1)
    |> Enum.flat_map(&media_rows/1)
    |> Enum.flat_map(fn row -> for kind <- [:image, :video], id = Map.get(row, :"#{kind}_id"), do: {kind, id} end)
    |> Enum.concat(Map.values(entry_assets(schema, entry)))
    |> Enum.uniq()
  end

  # Library media for `query`, word by word: titles and file names, then the
  # media in folders named after a word. Media matching more words come first.
  defp library_search(kind, query, actor) do
    words = query |> to_string() |> String.split(~r/[\s,]+/, trim: true) |> Enum.filter(&(String.length(&1) >= 3))

    # Without words there is nothing to go by.
    if words == [] do
      []
    else
      by_name =
        Enum.flat_map(words, fn word -> kind |> to_string() |> Dependencies.options(actor, word) |> Enum.map(& &1.id) end)

      in_folders =
        Enum.flat_map(words, fn word ->
          for folder <- Enum.take(Folders.find(kind, word, actor).folders, 2),
              id <- Folders.assets(kind, folder.id, actor, subfolders: true, limit: 12).ids,
              do: id
        end)

      (by_name ++ in_folders)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {id, count} -> {-count, id} end)
      |> Enum.map(&elem(&1, 0))
    end
  end

  defp titles(:file, ids),
    do: Map.new(Brando.Repo.all(from(f in Brando.Files.File, where: f.id in ^ids)), &{&1.id, &1.title || &1.filename})

  defp titles(kind, ids) do
    schema = if kind == :video, do: Brando.Videos.Video, else: Brando.Images.Image

    Map.new(Brando.Repo.all(from(m in schema, where: m.id in ^ids, select: {m.id, m.title})), fn {id, title} ->
      {id, plain(title)}
    end)
  end

  defp plain(%{} = text), do: text["en"] || text |> Map.values() |> List.first()
  defp plain(text), do: text

  # Datasources usually list identifiers; a custom one may list its own maps.
  defp selection_option(%Brando.Content.Identifier{} = identifier) do
    %{
      identifier_id: identifier.id,
      title: identifier.title,
      content_type: inspect(identifier.schema),
      id: identifier.entry_id,
      language: identifier.language
    }
  end

  defp selection_option(option), do: %{identifier_id: option.id, title: option_title(option)}

  defp option_title(option), do: to_string(Map.get(option, :title) || Map.get(option, :label) || "")

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
            settings: RefConfig.describe(ref),
            settable:
              cond do
                text = text_slot(ref.data.type) -> text
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
            settable: settable(var.type)
          }
        end)
    }
    |> put_present(:table, table_description(module))
    |> put_present(:datasource, datasource_description(module))
  end

  # A table's rows each have the variables of the module's table template.
  defp table_description(module) do
    for var <- Proposals.table_vars(module) do
      %{key: var.key, type: to_string(var.type), label: var.label, settable: settable(var.type)}
    end
  end

  defp datasource_description(%{datasource: true, datasource_type: type}) when type in [:selection, :single],
    do: %{
      type: to_string(type),
      note: "Choose its entries with set_block_selection, from list_selection_options."
    }

  defp datasource_description(%{datasource: true, datasource_type: type}),
    do: %{type: to_string(type), note: "It lists entries by itself; nothing to choose."}

  defp datasource_description(_module), do: nil

  defp text_slot("text"), do: "text: simple HTML"
  defp text_slot("header"), do: "text: plain"
  defp text_slot("markdown"), do: "text: markdown"
  defp text_slot("html"), do: "text: safe HTML"
  defp text_slot("svg"), do: "text: one <svg> element, no scripts"
  defp text_slot("map"), do: "text: an https map embed address"
  defp text_slot(_), do: nil

  defp settable(type) when type in [:string, :text, :html], do: "a string"
  defp settable(:boolean), do: "true or false"
  defp settable(:select), do: "one of the options"
  defp settable(:color), do: "a colour such as #1a2b3c"
  defp settable(:date), do: "an ISO date, 2026-09-26"
  defp settable(:datetime), do: "an ISO datetime, 2026-09-26T12:00:00Z"
  defp settable(:image), do: ~s({"kind":"image","id":N} or {"asset":"image1"})
  defp settable(:video), do: ~s({"kind":"video","id":N} or {"asset":"video1"})
  defp settable(:link), do: ~s(a URL, or an entry {"content_type":T,"id":N})
  defp settable(:file), do: ~s({"kind":"file","id":N})
  defp settable(:gallery), do: ~s({"gallery":[media, …]}, images and videos in order)
  defp settable(_), do: "no"

  defp option(%{label: label, value: value}) when label in [nil, "", value], do: value
  defp option(%{label: label, value: value}), do: %{value: value, label: label}

  # Multi modules the field allows at its root. Their blocks start empty; the
  # entries are inserted as children.
  defp multi_modules(set) when set in [nil, "", "all"] do
    case Content.list_modules(%{preload: [:refs], order: "asc sequence"}) do
      {:ok, modules} -> Enum.filter(modules, &(&1.multi && is_nil(&1.parent_id)))
      _ -> []
    end
  end

  defp multi_modules(set) do
    case Content.get_module_set(%{matches: %{title: set}, preload: [module_set_modules: [module: :refs]]}) do
      {:ok, set} -> set.module_set_modules |> Enum.map(& &1.module) |> Enum.filter(&(&1.multi && is_nil(&1.parent_id)))
      _ -> []
    end
  end

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
  defp outline(blocks, dimensions, described, budget) do
    Enum.map_reduce(blocks, described, fn block, described ->
      {children, after_children} = outline(block.children || [], dimensions, described + 1, budget)

      summary =
        block
        |> block_summary(dimensions, described < budget)
        |> put_kind(block)
        |> then(&if(children == [], do: &1, else: Map.put(&1, :children, children)))

      {summary, after_children}
    end)
  end

  defp block_summary(block, dimensions, full?) do
    module = block.module_id && Content.fetch_module(block.module_id, block.module_origin || :local)
    summary = %{uid: block.uid, type: to_string(block.type), module_name: module && label(module.name)}
    if full?, do: Map.merge(summary, details(block, dimensions)), else: summary
  end

  defp details(block, dimensions) do
    %{
      module: block.module_id && "#{block.module_origin || :local}:#{block.module_id}",
      active: block.active,
      texts: ref_texts(block.refs),
      media: ref_media(block.refs, dimensions),
      values: var_values(block.vars, dimensions)
    }
    |> put_present(:table, table_rows(block))
    |> put_present(:selection, selection(block))
    |> put_present(:anchor, block.anchor)
    |> put_present(:description, block.description)
    |> put_present(:settings, ref_settings(block.refs || []))
    |> put_present(:refs_off, for(%{active: false, name: name} <- block.refs || [], do: name))
  end

  defp table_rows(%{table_rows: rows}) when is_list(rows),
    do: Enum.map(rows, fn row -> Map.new(row.vars || [], &{&1.key, var_value(&1, %{})}) end)

  defp table_rows(_block), do: nil

  defp selection(%{block_identifiers: [_ | _] = chosen}),
    do: Enum.map(chosen, &%{identifier_id: &1.identifier_id, title: &1.identifier && &1.identifier.title})

  defp selection(_block), do: nil

  defp ref_settings(refs),
    do: for(ref <- refs, current = RefConfig.current(ref), current != %{}, into: %{}, do: {ref.name, current})

  # Other language versions, and whether they follow this entry by sync.
  defp languages(entry) do
    case Brando.Content.Proposals.Languages.versions(entry) do
      {_role, []} ->
        nil

      {role, versions} ->
        %{
          role: role && to_string(role),
          versions: versions,
          note:
            if(role == :source,
              do:
                "Synchronized versions get this entry's structure and media when a proposal is applied, with its new text to translate; change them only for other things.",
              else: "Change another language version only when the editor asks; it is its own entry."
            )
        }
    end
  end

  defp put_present(map, _key, value) when value in [nil, "", [], %{}], do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp put_kind(summary, %{type: :slot, slot_name: name}), do: Map.put(summary, :slot, name)
  defp put_kind(summary, %{multi: true}), do: Map.put(summary, :multi, true)
  defp put_kind(summary, _block), do: summary

  defp ref_texts(refs) do
    for %{data: %{type: type, data: data}} = ref <- refs, text = ref_text(type, data), into: %{}, do: {ref.name, text}
  end

  defp ref_text(type, data) when type in ["text", "header", "markdown", "html"],
    do: shorten(HtmlSanitizeEx.strip_tags(data.text || ""))

  defp ref_text("svg", %{code: code}) when is_binary(code), do: "<svg> (#{byte_size(code)} bytes)"
  defp ref_text("map", %{embed_url: url}), do: url
  defp ref_text(_, _), do: nil

  defp ref_media(refs, dimensions) do
    for ref <- refs, summary = ref_media_summary(ref, dimensions), into: %{}, do: {ref.name, summary}
  end

  defp ref_media_summary(ref, dimensions) do
    cond do
      id = Map.get(ref, :image_id) -> media_summary(:image, id, dimensions)
      id = Map.get(ref, :video_id) -> media_summary(:video, id, dimensions)
      id = Map.get(ref, :file_id) -> %{kind: :file, id: id}
      items = gallery_items(Map.get(ref, :gallery)) -> gallery_summary(items, dimensions)
      true -> nil
    end
  end

  defp gallery_items(%{gallery_objects: [_ | _] = objects}),
    do: Enum.map(objects, &if(&1.video_id, do: {:video, &1.video_id}, else: {:image, &1.image_id}))

  defp gallery_items(_), do: nil

  defp gallery_summary(items, dimensions),
    do: %{kind: :gallery, items: Enum.map(items, fn {kind, id} -> media_summary(kind, id, dimensions) end)}

  # Width, height and orientation of the media in `blocks`, in one query per kind.
  # The entry's own image and video fields, such as a listing image.
  defp entry_assets(schema, entry) do
    for %{name: name, type: kind} <- Brando.Blueprint.Assets.__assets__(schema),
        kind in [:image, :video],
        id = Map.get(entry, :"#{name}_id"),
        into: %{},
        do: {to_string(name), {kind, id}}
  end

  defp media_summary(kind, id, dimensions), do: Map.merge(%{kind: kind, id: id}, Map.get(dimensions, {kind, id}, %{}))

  defp dimensions(blocks, extra) do
    ids =
      blocks
      |> Enum.flat_map(&tree_media/1)
      |> Enum.flat_map(&media_rows/1)
      |> Enum.flat_map(fn row -> for kind <- [:image, :video], id = Map.get(row, :"#{kind}_id"), do: {kind, id} end)
      |> Enum.concat(extra)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    for {kind, schema} <- [image: Brando.Images.Image, video: Brando.Videos.Video],
        ids = Map.get(ids, kind, []),
        ids != [],
        {id, width, height} <-
          Brando.Repo.all(from(m in schema, where: m.id in ^ids, select: {m.id, m.width, m.height})),
        into: %{},
        do: {{kind, id}, %{width: width, height: height, orientation: orientation(width, height)}}
  end

  # A gallery's objects hold media too.
  defp media_rows(row) do
    case Map.get(row, :gallery) do
      %{gallery_objects: objects} when is_list(objects) -> [row | objects]
      _ -> [row]
    end
  end

  # Refs and vars both hold media.
  defp tree_media(block),
    do: (block.refs || []) ++ (block.vars || []) ++ Enum.flat_map(block.children || [], &tree_media/1)

  defp orientation(width, height) when is_integer(width) and is_integer(height) and width > 0 and height > 0 do
    cond do
      width > height -> "landscape"
      width < height -> "portrait"
      true -> "square"
    end
  end

  defp orientation(_, _), do: nil

  defp var_values(vars, dimensions) do
    for var <- vars, into: %{} do
      {var.key, var_value(var, dimensions)}
    end
  end

  defp var_value(%{type: :boolean} = var, _), do: var.value_boolean

  # A link names the entry it points to; the editor knows a project by its title.
  defp var_value(%{type: :link, identifier: %{title: title}} = var, _) when is_binary(title),
    do: %{entry: shorten(title), content_type: Codec.content_type(var.identifier.schema), id: var.identifier.entry_id}

  defp var_value(%{type: kind} = var, dimensions) when kind in [:image, :video] do
    case Map.get(var, :"#{kind}_id") do
      nil -> nil
      id -> media_summary(kind, id, dimensions)
    end
  end

  defp var_value(%{type: :file, file_id: id}, _), do: id && %{kind: :file, id: id}

  defp var_value(%{type: :gallery} = var, dimensions) do
    case gallery_items(Map.get(var, :gallery)) do
      nil -> nil
      items -> gallery_summary(items, dimensions)
    end
  end

  defp var_value(var, _), do: shorten(var.value)

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
