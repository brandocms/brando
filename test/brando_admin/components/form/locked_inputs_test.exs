defmodule BrandoAdmin.Components.Form.LockedInputsTest do
  # An input declared `readonly:` or `disabled:` renders locked: a lock by
  # its label, text controls `readonly`, other controls inert. Each control
  # keeps posting its value, so a subform row doesn't lose it. A top-level
  # input renders locked exactly when a save ignores it (`LockedFields`).
  # The browser side, one input of each type, is
  # `e2e/playwright/tests/projects/locked-inputs.spec.js`.
  use ExUnit.Case, async: true

  import Phoenix.Component, only: [to_form: 2]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Blueprint.Forms.Input, as: BlueprintInput
  alias BrandoAdmin.Components.Form.Fieldset.Field
  alias BrandoAdmin.Components.Form.Primitives

  @superuser %{id: 1, role: :superuser}
  @editor %{id: 2, role: :editor}

  defmodule TestEntry do
    use Ecto.Schema

    embedded_schema do
      field :title, :string
      field :slug, :string
      field :notes, :string
      field :amount, :integer
      field :featured, :boolean
      field :starts_on, :date
      field :label, :map
    end
  end

  defp form do
    %TestEntry{
      title: "Opening night",
      slug: "opening-night",
      notes: "Doors at seven",
      amount: 120,
      featured: true,
      starts_on: ~D[2026-11-14],
      label: %{"en" => "Opening", "no" => "Åpning"}
    }
    |> Ecto.Changeset.change()
    |> to_form(as: :entry)
  end

  defp render_top_level(name, type, opts, user) do
    render_component(&Field.render/1, %{
      input: %BlueprintInput{name: name, type: type, opts: opts},
      form: form(),
      parent_uploads: %{},
      current_user: user,
      relations: [],
      form_cid: nil
    })
  end

  # A subform's input: no `LockedFields` behind it, only its options
  defp render_nested(name, type, opts, user) do
    render_component(&Primitives.input/1, %{
      field: form()[name],
      label: nil,
      instructions: nil,
      placeholder: nil,
      opts: opts,
      type: type,
      current_user: user
    })
  end

  defp locked?(html), do: html =~ ~s(data-locked="true") and html =~ ~s(class="field-lock")
  defp inert?(html), do: html =~ ~r/class="field-base"[^>]*\binert\b/

  describe "text inputs" do
    for {type, name} <- [text: :title, textarea: :notes, number: :amount, email: :title, phone: :title] do
      test "a locked #{type} input is read only and still posts its value" do
        for opts <- [[readonly: true], [disabled: true]] do
          html = render_top_level(unquote(name), unquote(type), opts, @superuser)

          assert locked?(html)
          assert html =~ ~r/<(input|textarea)[^>]*name="entry\[#{unquote(name)}\]"[^>]*\breadonly\b/
          refute html =~ ~r/<(input|textarea)[^>]*name="entry\[#{unquote(name)}\]"[^>]*\bdisabled\b/
          refute inert?(html)
        end
      end
    end

    test "a translated input is read only in every language, and its tabs still switch" do
      html = render_top_level(:label, :i18n_text, [disabled: true], @superuser)

      assert locked?(html)
      assert html =~ ~r/name="entry\[label\]\[en\]"[^>]*\breadonly\b/
      assert html =~ ~r/name="entry\[label\]\[no\]"[^>]*\breadonly\b/
      refute html =~ ~r/name="entry\[label\]\[en\]"[^>]*\bdisabled\b/
      refute inert?(html)
    end

    test "an unlocked input renders as before" do
      html = render_top_level(:title, :text, [], @editor)

      refute locked?(html)
      refute html =~ ~r/name="entry\[title\]"[^>]*\breadonly\b/
    end
  end

  describe "other controls" do
    test "a locked toggle or date is inert and keeps its value" do
      html = render_top_level(:featured, :toggle, [readonly: true], @superuser)

      assert locked?(html)
      assert inert?(html)
      # Its label would pass a click on to the inert checkbox
      assert html |> Floki.parse_fragment!() |> Floki.find("label.control-label") |> Floki.attribute("for") == []
      assert html =~ ~r/type="checkbox"[^>]*name="entry\[featured\]"[^>]*checked/
      refute html =~ ~r/type="checkbox"[^>]*\bdisabled\b/

      html = render_top_level(:starts_on, :date, [disabled: true], @superuser)

      assert locked?(html)
      assert inert?(html)
      assert html =~ ~s(value="2026-11-14")
    end
  end

  describe "a link" do
    # `Input.Link` draws its field through the var's own chrome
    test "a locked link's field is marked and inert" do
      var =
        %Brando.Content.Var{type: :link, key: "link", link_type: :url, value: "https://example.com"}
        |> Ecto.Changeset.change()
        |> to_form(as: :link)

      render = fn locked ->
        render_component(&BrandoAdmin.Components.Form.Input.RenderVar.render_value_inputs/1, %{
          type: :link,
          var: var,
          label: "Link",
          instructions: nil,
          identifier: nil,
          identifier_id: nil,
          target: nil,
          on_change: fn _ -> :ok end,
          locked: locked
        })
      end

      assert locked?(render.(true))
      assert inert?(render.(true))
      refute locked?(render.(false))
    end
  end

  describe "`:unless_superuser`" do
    test "locks the field for anyone but a superuser" do
      for {render, input} <- [{&render_top_level/4, :text}, {&render_nested/4, :text}, {&render_nested/4, :toggle}] do
        name = if input == :toggle, do: :featured, else: :title

        refute locked?(render.(name, input, [readonly: :unless_superuser], @superuser))
        assert locked?(render.(name, input, [readonly: :unless_superuser], @editor))
        refute locked?(render.(name, input, [disabled: :unless_superuser], @superuser))
        assert locked?(render.(name, input, [disabled: :unless_superuser], @editor))
      end
    end

    test "is locked without a user" do
      assert locked?(render_nested(:title, :text, [readonly: :unless_superuser], nil))
    end

    # The Meta drawer renders its inputs itself, from the Blueprint's options
    test "is locked where a caller passes it unresolved" do
      html =
        render_component(&BrandoAdmin.Components.Form.Input.text/1,
          field: form()[:title],
          opts: [readonly: :unless_superuser]
        )

      assert locked?(html)

      html =
        render_component(&BrandoAdmin.Components.Form.Input.text/1,
          field: form()[:title],
          opts: Primitives.lock_opts([readonly: :unless_superuser], @superuser)
        )

      refute locked?(html)
    end
  end

  describe "a slug" do
    # The browser's Slug hook fills a slug in, so `readonly: true` doesn't
    # lock it on save (`LockedFields`), and it renders editable.
    test "declared `readonly: true` renders editable" do
      html = render_top_level(:slug, :slug, [source: :title, readonly: true], @superuser)

      refute locked?(html)
      refute html =~ ~r/name="entry\[slug\]"[^>]*\breadonly\b/
    end

    # Locked, it is read only, which the Slug hook reads as "don't follow
    # the source".
    test "declared `:unless_superuser` is read only for anyone else" do
      html = render_top_level(:slug, :slug, [source: :title, readonly: :unless_superuser], @editor)

      assert locked?(html)
      assert html =~ ~r/name="entry\[slug\]"[^>]*\breadonly\b/

      refute locked?(render_top_level(:slug, :slug, [source: :title, readonly: :unless_superuser], @superuser))
    end
  end
end
