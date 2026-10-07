defmodule Brando.JSONLDTest.Person do
  @moduledoc false
  # A People blueprint with its own Person mapping and a profile page.
  use Brando.Blueprint,
    application: "Brando",
    domain: "JSONLDTest",
    schema: "Person",
    singular: "person",
    plural: "people",
    gettext_module: Brando.Gettext

  alias Brando.JSONLD

  identifier ~H"{@entry.name}"
  absolute_url ~H"/people/{@entry.slug}"

  trait Brando.Trait.Timestamped

  attributes do
    attribute :name, :string, required: true
    attribute :slug, :slug, required: true
    attribute :job_title, :string
    attribute :email, :string
    attribute :same_as, Brando.Type.StringList, default: []
  end

  assets do
    asset :portrait, :image, cfg: [upload_path: "images/people"]
  end

  json_ld_schema JSONLD.Schema.Person do
    field :name, :string, & &1.name
    field :jobTitle, :string, & &1.job_title
    field :sameAs, :string, & &1.same_as
    field :image, :image, & &1.portrait
    field :url, :current_url
  end
end

defmodule Brando.JSONLDTest.Contributor do
  @moduledoc false
  # A People-style blueprint without a JSON-LD mapping or a page of its own.
  use Brando.Blueprint,
    application: "Brando",
    domain: "JSONLDTest",
    schema: "Contributor",
    singular: "contributor",
    plural: "contributors",
    gettext_module: Brando.Gettext

  identifier ~H"{@entry.name}"
  absolute_url false

  attributes do
    attribute :name, :string, required: true
    attribute :job_title, :string
    attribute :email, :string
  end

  assets do
    asset :avatar, :image, cfg: [upload_path: "images/contributors"]
  end
end

defmodule Brando.JSONLDTest.Post do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "JSONLDTest",
    schema: "Post",
    singular: "post",
    plural: "posts",
    gettext_module: Brando.Gettext

  alias Brando.JSONLD

  identifier ~H"{@entry.title}"
  absolute_url ~H"/posts/{@entry.slug}"

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
  end

  relations do
    relation :writer, :belongs_to, module: Brando.JSONLDTest.Person
    relation :blocks, :has_many, module: :blocks
  end

  assets do
    asset :cover_video, :video, cfg: [upload_path: "videos/posts"]
  end

  json_ld_schema JSONLD.Schema.Article do
    field :author, :person, &[&1.creator, &1.writer]
    field :headline, :string, & &1.title
    field :publisher, :identity
    field :url, :current_url
  end
end

defmodule Brando.JSONLDTest.QuietPost do
  @moduledoc false
  # Opts out of the automatic VideoObjects, and maps no author.
  use Brando.Blueprint,
    application: "Brando",
    domain: "JSONLDTest",
    schema: "QuietPost",
    singular: "quiet_post",
    plural: "quiet_posts",
    gettext_module: Brando.Gettext

  alias Brando.JSONLD

  identifier ~H"{@entry.title}"
  absolute_url false

  trait Brando.Trait.Creator

  attributes do
    attribute :title, :string, required: true
  end

  assets do
    asset :cover_video, :video, cfg: [upload_path: "videos/posts"]
  end

  json_ld_schema JSONLD.Schema.Article do
    videos(false)
    field :headline, :string, & &1.title
  end
end
