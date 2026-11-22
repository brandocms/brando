defmodule BrandoAdmin.Components.Form.RefusedAndRepeatedSavesTest do
  @moduledoc """
  What the Form does with a save it refuses or repeats (#3773). These drive
  `handle_event/3` on a hand-built socket, as `SubmitProcessingFlagTest`
  does: the save collects its rows in a first round-trip, and what matters
  here is the changeset the second one builds.
  """

  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Changeset, only: [change: 2]
  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog, only: [with_log: 1]

  alias BrandoAdmin.Components.Form
  alias Phoenix.Component

  setup do
    user = Brando.Factory.insert(:random_user, role: :superuser)
    palette = Brando.Factory.insert(:palette, creator: user, status: :published, colors: [Brando.Factory.build(:color)])
    {:ok, user: user, palette: palette}
  end

  defp palette_socket(ctx, overrides) do
    %Phoenix.LiveView.Socket{}
    |> Component.assign(:id, "palette_form")
    |> Component.assign(:schema, Brando.Content.Palette)
    |> Component.assign(:singular, "palette")
    |> Component.assign(:context, Brando.Content)
    |> Component.assign(:entry, ctx.palette)
    |> Component.assign(:entry_id, ctx.palette.id)
    |> Component.assign(:current_user, ctx.user)
    |> Component.assign(:form_blueprint, Brando.Content.Palette.__form__(:default))
    |> Component.assign(:form, Phoenix.Component.to_form(Ecto.Changeset.change(ctx.palette)))
    |> Component.assign(:has_blocks?, false)
    |> Component.assign(:has_transformers?, false)
    |> Component.assign(:all_transformers_received?, true)
    |> Component.assign(:transformer_changesets, %{})
    |> Component.assign(:processing, true)
    |> Component.assign(:save_redirect_target, :self)
    |> Component.assign(:live_preview_active?, false)
    |> Component.assign(:fields_demanding_live_preview_reassign, [])
    |> then(fn socket ->
      Enum.reduce(overrides, socket, fn {k, v}, acc -> Component.assign(acc, k, v) end)
    end)
  end

  defp color_params(palette, name) do
    [color] = palette.colors
    %{"0" => %{"name" => name, "key" => color.key, "hex_value" => color.hex_value}}
  end

  describe "a kept field and an invalid row" do
    # Another editor's change replaced `instructions`, and the browser still
    # sends the value it showed before: an echo, for which the form keeps
    # its own value (`replaced_values`, `drop_echoes/4`, `keep_field/3`). A
    # color row in the same save has no name, which the row refuses.
    test "the save is refused, with the row's error, and the entry is left as it was", ctx do
      socket = palette_socket(ctx, replaced_values: %{instructions: ["From the old form"]})

      params = %{
        "palette" => %{
          "name" => ctx.palette.name,
          "instructions" => "From the old form",
          "colors" => color_params(ctx.palette, "")
        }
      }

      {{:noreply, socket}, _log} = with_log(fn -> Form.handle_event("save", params, socket) end)

      refute socket.assigns.processing
      changeset = socket.assigns.form.source
      refute changeset.valid?
      assert [row] = changeset |> Ecto.Changeset.get_change(:colors) |> Enum.reject(&(&1.action == :replace))
      refute row.valid?
      assert Keyword.has_key?(row.errors, :name)
      # The kept field is the form's, not the old form's
      assert Ecto.Changeset.get_field(changeset, :instructions) == ctx.palette.instructions

      saved = Brando.Repo.get!(Brando.Content.Palette, ctx.palette.id)
      assert Enum.map(saved.colors, & &1.name) == Enum.map(ctx.palette.colors, & &1.name)
    end
  end

  defp article(%{user: user}) do
    {:ok, article} =
      Brando.SyncTest.create_article(
        %{title: "Rows", slug: "rows", language: "en", status: "published", items: [%{label: "A", sequence: 0}]},
        user
      )

    %{article: Brando.Repo.preload(article, :items, force: true)}
  end

  # The alert the form pushed last
  defp alert_html(socket) do
    Enum.find_value(socket.private.live_temp[:push_events] || [], fn
      ["b:alert", %{html: html}] -> html
      _ -> nil
    end)
  end

  describe "a revision refused for a block" do
    alias Brando.SyncTest.Article

    setup :article

    # The block editor draws the blocks: their errors are the form's own,
    # listed once, with no list of fields the form does not show
    test "lists the block's error with the form's own", ctx do
      entry_block_schema = Article.__schema__(:association, :entry_blocks).related

      block =
        %Brando.Content.Block{children: []}
        |> change(%{})
        |> Ecto.Changeset.add_error(:module_id, "can't be blank", validation: :required)

      entry_block =
        entry_block_schema
        |> struct(sequence: 0, block: %Brando.Content.Block{children: []})
        |> change(%{})
        |> Ecto.Changeset.put_assoc(:block, block)

      article = Brando.Repo.preload(ctx.article, :entry_blocks)

      socket =
        ctx
        |> article_socket()
        |> Component.assign(:form_blueprint, Article.__form__(:default))
        |> Component.assign(:form, Phoenix.Component.to_form(change(article, %{})))
        |> Component.assign(:block_changesets, %{blocks: [entry_block]})
        |> Component.assign(:transformer_changesets, %{})

      {socket, log} = with_log(fn -> Form.event_tag_received(socket, :store_revision) end)

      html = alert_html(socket)
      assert length(String.split(html, ~s{class="error-keys"})) == 2
      assert html =~ "module_id"
      refute log =~ "Could not get field"
    end
  end

  describe "a revision refused for a transformer row" do
    alias Brando.SyncTest.Article

    setup :article

    defp article_socket(ctx) do
      %Phoenix.LiveView.Socket{private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}}
      |> Component.assign(:id, "article_form")
      |> Component.assign(:schema, Article)
      |> Component.assign(:singular, "article")
      |> Component.assign(:entry, ctx.article)
      |> Component.assign(:entry_id, ctx.article.id)
      |> Component.assign(:current_user, ctx.user)
      |> Component.assign(:form_blueprint, Article.__form__(:transformer_rich_items))
      |> Component.assign(:form, Phoenix.Component.to_form(Ecto.Changeset.change(ctx.article)))
      |> Component.assign(:block_changesets, %{})
      |> Component.assign(:transformer_changesets, %{items: nil})
    end

    # The rows the transformer sends the form: the stored row with `link`
    defp rows(ctx, link), do: [Ecto.Changeset.change(hd(ctx.article.items), %{link: link, sequence: 0})]

    defp revisions(article) do
      Brando.Repo.aggregate(
        from(r in Brando.Revisions.Revision, where: r.entry_type == ^to_string(Article) and r.entry_id == ^article.id),
        :count
      )
    end

    test "is stored once the row is corrected", ctx do
      before = revisions(ctx.article)

      unsafe =
        article_socket(ctx)
        |> Component.assign(:transformer_changesets, %{items: rows(ctx, ~s{<p onclick="x()">Row</p>})})

      {socket, _log} = with_log(fn -> Form.event_tag_received(unsafe, :store_revision) end)

      assert revisions(ctx.article) == before
      # What the editor sees after the refusal: the row's error in the form
      refute socket.assigns.form.source.valid?
      assert [row] = Ecto.Changeset.get_change(socket.assigns.form.source, :items)
      assert Keyword.has_key?(row.errors, :link)
      assert socket.assigns.transformer_changesets == %{items: nil}

      _socket =
        socket
        |> Component.assign(:transformer_changesets, %{items: rows(ctx, "<p>Row</p>")})
        |> Form.event_tag_received(:store_revision)

      assert revisions(ctx.article) == before + 1
    end

    # The revision was built from the rows the transformer sent: the form's
    # refused rows go with their error
    test "clears the row's error once the corrected revision is stored", ctx do
      unsafe =
        article_socket(ctx)
        |> Component.assign(:transformer_changesets, %{items: rows(ctx, ~s{<p onclick="x()">Row</p>})})

      {socket, _log} = with_log(fn -> Form.event_tag_received(unsafe, :store_revision) end)
      refute socket.assigns.form.source.valid?

      socket =
        socket
        |> Component.assign(:transformer_changesets, %{items: rows(ctx, "<p>Row</p>")})
        |> Form.event_tag_received(:store_revision)

      assert socket.assigns.form.source.valid?
      assert Ecto.Changeset.get_change(socket.assigns.form.source, :items) in [nil, []]
    end
  end

  describe "a save without blocks that stays on the form" do
    alias Brando.SyncTest.Article

    setup :article

    defp blockless_socket(ctx) do
      %Phoenix.LiveView.Socket{private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}}
      |> Component.assign(:id, "article_form")
      |> Component.assign(:schema, Article)
      |> Component.assign(:singular, "article")
      |> Component.assign(:context, Brando.SyncTest)
      |> Component.assign(:entry, ctx.article)
      |> Component.assign(:entry_id, ctx.article.id)
      |> Component.assign(:current_user, ctx.user)
      |> Component.assign(:form_blueprint, Article.__form__(:transformer_rich_items))
      |> Component.assign(:form, Phoenix.Component.to_form(Ecto.Changeset.change(ctx.article)))
      |> Component.assign(:has_blocks?, false)
      |> Component.assign(:has_transformers?, true)
      |> Component.assign(:all_transformers_received?, false)
      |> Component.assign(:transformer_changesets, %{items: nil})
      |> Component.assign(:processing, false)
      |> Component.assign(:save_redirect_target, :self)
      |> Component.assign(:live_preview_active?, false)
      |> Component.assign(:fields_demanding_live_preview_reassign, [])
    end

    defp labels(article) do
      Brando.SyncTest.ArticleItem
      |> Brando.Repo.all()
      |> Enum.filter(&(&1.article_id == article.id))
      |> Enum.map(& &1.label)
      |> Enum.sort()
    end

    # A save as the browser makes it: the first submit asks the
    # transformers for their rows (`fetch_transformer_data`), which come
    # back as `provide_transformer_data`, and a second submit writes. A form
    # that holds rows it collected before writes on the first submit.
    defp save(socket, title, rows) do
      params = %{"article" => %{"title" => title, "slug" => "rows"}}
      {:noreply, socket} = Form.handle_event("save", params, socket)

      receive do
        {:phoenix, :send_update, {_, %{event: "fetch_transformer_data"}}} ->
          socket = Component.assign(socket, transformer_changesets: %{items: rows}, all_transformers_received?: true)
          {:noreply, socket} = Form.handle_event("save", params, socket)
          socket
      after
        500 -> socket
      end
    end

    test "the next save writes the rows the transformer has then", ctx do
      # As the Transformer sends them: a stored row as a changeset, a new
      # one as a map (it keeps the row it added as new after the save)
      [stored] = ctx.article.items
      socket = save(blockless_socket(ctx), "Rows, saved", [change(stored, %{sequence: 0}), %{label: "New", sequence: 1}])
      assert labels(ctx.article) == ["A", "New"]

      _socket =
        save(socket, "Rows, saved again", [change(stored, %{sequence: 0}), %{label: "New, edited", sequence: 1}])

      assert labels(ctx.article) == ["A", "New, edited"]
    end
  end
end
