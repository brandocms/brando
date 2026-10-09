# A meta field's own AI actions, on the Blueprint's hidden input for it, and
# a site prompt for the Meta drawer (MetaDrawerTest).
defmodule Brando.MetaDrawerTest.ActionsArticle do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "MetaDrawerTest",
    schema: "ActionsArticle",
    singular: "actions_article",
    plural: "actions_articles",
    gettext_module: Brando.Gettext

  trait :meta,
    ai: [meta_description: [prompt: "Write an SEO description", context: [:title]]]

  attributes do
    attribute :title, :string
  end

  forms do
    form do
      tab "Content" do
        fieldset do
          input :title, :text

          input :meta_description, :textarea,
            hidden: true,
            ai_actions: [shorten: [label: "Shorten", prompt: "Shorten it.", from: [:meta_description]]]
        end
      end
    end
  end
end
