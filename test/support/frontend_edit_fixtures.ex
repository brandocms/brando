defmodule Brando.FrontendEditFixtures do
  @moduledoc false
  # Pages and fragments with real block trees for the frontend edit tests,
  # rendered the way a save renders them.

  alias Brando.Content.Block
  alias Brando.Factory
  alias Brando.Repo

  def text_module(user, name \\ "Text") do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => name},
          namespace: %{"en" => "Content"},
          help_text: %{},
          code: ~s(<div class="text">{% ref refs.body %}</div>),
          refs: [%{name: "body", uid: Brando.Utils.generate_uid(), data: %{type: "text", data: %{text: "Default"}}}]
        ),
        user
      )

    module
  end

  @doc "A text block: `parent` is a block to nest it in, or `nil` for a root."
  def text_block(module, user, source, text, parent \\ nil) do
    %Block{}
    |> Block.recursive_block_changeset(
      %{
        "uid" => Brando.Utils.generate_uid(),
        "type" => "module",
        "module_id" => module.id,
        "creator_id" => user.id,
        "source" => to_string(source),
        "parent_id" => parent && parent.id,
        "refs" => [
          %{
            "uid" => Brando.Utils.generate_uid(),
            "name" => "body",
            "data" => %{"type" => "text", "data" => %{"text" => text}}
          }
        ]
      },
      user
    )
    |> Repo.insert!()
  end

  def container_block(user, source) do
    %Block{}
    |> Block.recursive_block_changeset(
      %{
        "uid" => Brando.Utils.generate_uid(),
        "type" => "container",
        "creator_id" => user.id,
        "source" => to_string(source)
      },
      user
    )
    |> Repo.insert!()
  end

  def fragment_block(fragment, user, source) do
    %Block{}
    |> Block.recursive_block_changeset(
      %{
        "uid" => Brando.Utils.generate_uid(),
        "type" => "fragment",
        "fragment_id" => fragment.id,
        "creator_id" => user.id,
        "source" => to_string(source)
      },
      user
    )
    |> Repo.insert!()
  end

  def attach(join_schema, entry, blocks) do
    blocks
    |> Enum.with_index()
    |> Enum.each(fn {block, sequence} ->
      join_schema |> struct(%{entry_id: entry.id, block_id: block.id, sequence: sequence}) |> Repo.insert!()
    end)
  end

  @doc """
  A page with a text block, and a container holding another, rendered and
  stored. Returns the page and the blocks by role.
  """
  def page_with_blocks(user, opts \\ []) do
    module = Keyword.get_lazy(opts, :module, fn -> text_module(user) end)
    source = Brando.Pages.Page.Blocks

    page =
      Factory.insert(:page,
        creator: user,
        title: Keyword.get(opts, :title, "About us"),
        uri: Brando.Utils.random_string(8)
      )

    intro = text_block(module, user, source, "Hello from the intro")
    container = container_block(user, source)
    child = text_block(module, user, source, "Inside the section", container)
    roots = [intro, container] ++ List.wrap(opts[:extra_roots])

    attach(source, page, roots)
    {:ok, page} = Brando.Content.Blocks.render_entry(Brando.Pages.Page, page.id)

    %{page: page, module: module, intro: intro, container: container, child: child}
  end

  @doc "A published fragment with one text block, rendered and stored."
  def fragment_with_block(user, module, text \\ "Shared footer text") do
    fragment = Factory.insert(:fragment, creator: user, key: Brando.Utils.random_string(8), title: "Footer")
    block = text_block(module, user, Brando.Pages.Fragment.Blocks, text)
    attach(Brando.Pages.Fragment.Blocks, fragment, [block])
    {:ok, fragment} = Brando.Content.Blocks.render_entry(Brando.Pages.Fragment, fragment.id)
    %{fragment: fragment, block: block}
  end

  @doc "The HTML without frontend edit markers or the whitespace they bring."
  def strip_markers(html) do
    html
    |> String.replace(~r/<!-- \[[+-]:[BFC]<[^>]+>\] -->/, "")
    |> String.replace(~r/\s+/, "")
  end
end
