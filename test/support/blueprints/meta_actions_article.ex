# A Blueprint with `trait :meta` on the `pages` table, for the Meta drawer's
# AI actions (MetaDrawerTest, FieldActionsLiveTest): a site prompt for the
# meta description in `trait :meta, ai:`, and the meta description as an
# input with its own actions, a `:hidden` input in the default form and in a
# tab in `form :visible`, which also has rich text with `write_with_ai:`.
defmodule Brando.MetaDrawerTest.ActionsArticle do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "MetaDrawerTest",
    schema: "ActionsArticle",
    singular: "actions_article",
    plural: "actions_articles",
    gettext_module: Brando.Gettext

  table "pages"
  # Pages' table, not their permissions
  authorization(key: "brando.meta_drawer_test.actions_article")

  trait :creator
  trait :timestamped

  trait :meta,
    ai: [meta_description: [prompt: "Write an SEO description", context: [:title]]]

  attributes do
    attribute :title, :string
    attribute :language, :string
    attribute :css_classes, :text
  end

  forms do
    form do
      tab "Content" do
        fieldset do
          input :title, :text

          input :meta_description, :hidden,
            ai_actions: [shorten: [label: "Shorten", prompt: "Shorten it.", from: [:meta_description]]]
        end
      end
    end

    form :visible do
      tab "Content" do
        fieldset do
          input :title, :text

          input :meta_description, :textarea,
            ai_actions: [shorten: [label: "Shorten", prompt: "Shorten it.", from: [:meta_description]]]

          input :css_classes, :rich_text,
            write_with_ai: [prompt: "Keep the house style.", from: [:title], model: "openai:gpt-4o"]
        end
      end
    end
  end
end

defmodule Brando.MetaDrawerTest do
  @moduledoc false
  use BrandoAdmin, :context
  use Brando.Query

  import Ecto.Query

  alias Brando.MetaDrawerTest.ActionsArticle

  query :single, ActionsArticle, do: fn query -> from(q in query) end

  matches ActionsArticle do
    fn
      {:id, id}, query -> from t in query, where: t.id == ^id
    end
  end

  query :list, ActionsArticle, do: fn query -> from(q in query) end

  mutation :update, ActionsArticle
end

defmodule BrandoAdmin.MetaDrawerTest.ActionsArticleFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.MetaDrawerTest.ActionsArticle

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="actions_article_form"
      name={:visible}
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}
    >
      <:header>Article</:header>
    </.live_component>
    """
  end
end
