defmodule Brando.Villain.RenderInvalidationTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Blocks, as: ContentBlocks
  alias Brando.Factory
  alias Brando.Villain.RenderInvalidation

  @sources %{
    configs: [
      "{{ configs.lockdown_enabled }}",
      "{% if configs.lockdown_enabled %}locked{% endif %}",
      "<span :if={@configs.lockdown_enabled}>locked</span>",
      ~S(<.notice configs={@configs} />)
    ],
    globals: [
      "{{ globals.shop.url }}",
      "{% if globals.shop.open %}open{% endif %}",
      ~S(<a href={@globals["shop"]["url"]}>Shop</a>),
      ~S(<.shop globals={@globals} />)
    ],
    identity: [
      "{{ identity.phone }}",
      "{% if identity.phone %}{{ identity.phone }}{% endif %}",
      "<span>{@identity.phone}</span>"
    ],
    links: [
      "{{ links.instagram.url }}",
      "{% for link in links %}{{ link.url }}{% endfor %}",
      ~S(<a href={@links["instagram"].url}>Instagram</a>)
    ],
    navigation: [
      "{{ navigation.main.en.title }}",
      "{% if navigation.main %}menu{% endif %}",
      ~S(<.menu menu={@navigation["main"]} />)
    ]
  }

  test "reference patterns cover Liquid expressions and HEEx assigns without matching prose" do
    for {name, sources} <- @sources do
      [{^name, pattern}] = RenderInvalidation.patterns([name])
      regex = Regex.compile!(pattern)

      assert Enum.all?(sources, &Regex.match?(regex, &1)),
             "expected #{name} pattern to match all supported source forms"

      refute Regex.match?(regex, "<p>Our #{name} are configured elsewhere.</p>")
    end
  end

  test "Postgres module lookup sees HEEx and Liquid conditional references" do
    user = Factory.insert(:random_user)

    for {name, sources} <- @sources do
      matching_ids =
        Enum.map(sources, fn source ->
          {:ok, module} =
            Brando.Content.create_module(
              Factory.params_for(:module, %{code: source, refs: [], vars: []}),
              user
            )

          module.id
        end)

      {:ok, unrelated} =
        Brando.Content.create_module(
          Factory.params_for(:module, %{code: "<p>No references here</p>", refs: [], vars: []}),
          user
        )

      found_ids =
        name
        |> then(&RenderInvalidation.patterns([&1]))
        |> ContentBlocks.search_modules_for_regex()
        |> Enum.map(& &1["id"])

      assert Enum.all?(matching_ids, &(&1 in found_ids))
      refute unrelated.id in found_ids
    end
  end

  test "updating a global re-renders stored HTML for an HEEx module", %{conn: _conn} do
    user = Factory.insert(:random_user)

    {:ok, global_set} =
      Brando.Sites.create_global_set(
        %{
          label: "HEEx invalidation",
          key: "heex_invalidation",
          language: "en",
          vars: [%{type: "text", label: "Message", key: "message", value: "Before"}]
        },
        user
      )

    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module, %{
          type: :heex,
          code: ~S(<p>{@globals["heex_invalidation"]["message"]}</p>),
          refs: [],
          vars: []
        }),
        user
      )

    fragment_params =
      Factory.params_for(:fragment, %{
        language: :en,
        entry_blocks: [
          %{
            block: %{
              type: :module,
              source: "Elixir.Brando.Pages.Fragment.Blocks",
              module_id: module.id,
              uid: Brando.Utils.generate_uid(),
              multi: false,
              refs: [],
              vars: []
            }
          }
        ]
      })

    fragment_changeset = Ecto.Changeset.change(%Brando.Pages.Fragment{}, fragment_params)
    {:ok, fragment} = Brando.Pages.create_fragment(fragment_changeset, user)
    {:ok, fragment} = ContentBlocks.render_entry(Brando.Pages.Fragment, fragment.id)
    assert fragment.rendered_blocks == "<p>Before</p>"

    {:ok, _global_set} =
      Brando.Sites.update_global_set(
        global_set.id,
        %{
          vars: [
            %{
              type: "text",
              label: "Message",
              key: "message",
              value: "After",
              creator_id: user.id
            }
          ]
        },
        user
      )

    assert Brando.Repo.get!(Brando.Pages.Fragment, fragment.id).rendered_blocks == "<p>After</p>"
  end
end
