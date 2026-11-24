defmodule BrandoIntegrationWeb.Projects.ProjectListLive do
  use BrandoAdmin.LiveView.Listing, schema: Brando.BlueprintTest.Project

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header title="Projects" subtitle="Overview" />

    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />
    """
  end
end

defmodule BrandoIntegration.LockdownController do
  use Phoenix.Controller, formats: [:html, :json]
  plug :put_layout, html: {Brando.LayoutView, :app}
end

defmodule BrandoIntegration.ProjectController do
  use Phoenix.Controller, formats: [:html, :json]
  plug :put_layout, html: {Brando.LayoutView, :app}

  def index(conn, _), do: send_resp(conn, 200, "index")
  def show(conn, _), do: send_resp(conn, 200, "show")
end

defmodule BrandoIntegrationWeb.PageController do
  use Phoenix.Controller, formats: [:html, :json]
  plug :put_layout, html: {Brando.LayoutView, :app}

  def index(conn, _), do: send_resp(conn, 200, "index")
  def show(conn, _), do: send_resp(conn, 200, "show")
end

defmodule RouterHelper do
  @moduledoc """
  Conveniences for testing routers and controllers.
  Must not be used to test endpoints as it does some
  pre-processing (like fetching params) which could
  skew endpoint tests.
  """

  import Plug.Conn,
    only: [
      fetch_query_params: 1,
      fetch_session: 1,
      put_private: 3
    ]

  alias Plug.Session

  @session Plug.Session.init(
             store: :cookie,
             key: "_app",
             encryption_salt: "yadayada",
             signing_salt: "yadayada"
           )

  defmacro __using__(_) do
    quote do
      import RouterHelper
    end
  end

  def with_session(conn) do
    conn
    |> with_secret_key_base
    |> Session.call(@session)
    |> fetch_session
  end

  defp with_secret_key_base(conn) do
    conn
    |> Map.put(:secret_key_base, String.duplicate("abcdefgh", 8))
  end

  def as_json(conn) do
    conn
    |> Plug.Conn.put_req_header("accept", "application/json")
  end

  def call(verb, path, params \\ nil) do
    Plug.Test.conn(verb, path, params)
  end

  def send_request(conn) do
    conn
    |> put_private(:phoenix_endpoint, Brando.endpoint())
    |> put_private(:plug_skip_csrf_protection, true)
    |> fetch_query_params
    |> Brando.router().call(Brando.router().init([]))
  end
end

defmodule BrandoAdmin.SyncTest.ArticleListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.SyncTest.Article

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <Content.header title="Articles" subtitle="Overview" />

    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />
    """
  end
end

# A listing behind a record read policy: each editor reads only the articles
# they made (ListingDeletePermanentlyTest)
defmodule BrandoAdmin.SyncPolicyTest.ArticleListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.SyncPolicyTest.Article

  def render(assigns), do: ~H""
end

# A page listing with a delete of its own (`overrides`), default actions on
# (ListingDeletePermanentlyTest)
defmodule BrandoAdmin.OwnDeleteTest.PageListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.Pages.Page, overrides: ~w(delete_entry)

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />
    """
  end

  def handle_event("delete_entry", _params, socket), do: {:noreply, socket}
end

defmodule BrandoAdmin.SyncTest.ArticleUserContextListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.SyncTest.Article

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_user_context"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:user_context}
    />
    """
  end
end

defmodule BrandoAdmin.SyncTest.ArticleFiltersListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.SyncTest.Article

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_filters"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:filters}
    />
    """
  end
end

defmodule BrandoAdmin.SyncTest.ArticleFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.SyncTest.Article

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="article_form"
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

defmodule BrandoAdmin.SlugScopeTest.IndependentLanguageArticleListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.SlugScopeTest.IndependentLanguageArticle

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />
    """
  end
end

# The route a new translation redirects to; not rendered in tests
defmodule BrandoAdmin.SlugScopeTest.IndependentLanguageArticleFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.SlugScopeTest.IndependentLanguageArticle

  def render(assigns), do: ~H"<div></div>"
end

defmodule BrandoAdmin.SlugScopeTest.IndependentTableArticleListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.SlugScopeTest.IndependentTableArticle

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />
    """
  end
end

defmodule BrandoAdmin.RestoreTest.ProjectListLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Listing, schema: Brando.RestoreTest.Project

  alias BrandoAdmin.Components.Content

  def render(assigns) do
    ~H"""
    <.live_component
      module={Content.List}
      id={"content_listing_#{@schema}_default"}
      schema={@schema}
      current_user={@current_user}
      uri={@uri}
      params={@params}
      listing={:default}
    />
    """
  end
end

# The route a new translation redirects to; not rendered in tests
defmodule BrandoAdmin.SlugScopeTest.IndependentTableArticleFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.SlugScopeTest.IndependentTableArticle

  def render(assigns), do: ~H"<div></div>"
end

defmodule BrandoAdmin.SyncTest.ArticleLockedFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.SyncTest.Article

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="article_form"
      name={:locked}
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

defmodule BrandoAdmin.SyncTest.ArticleLockedSlugFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.SyncTest.Article

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="article_form"
      name={:locked_slug}
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

defmodule BrandoAdmin.SyncTest.ArticleNoBlocksFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.SyncTest.Article

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <%!-- The form hooks of `BrandoAdmin.LiveView.Form` reach the Form as
          `<singular>_form`, whichever form it shows. --%>
    <.live_component
      module={Form}
      id="article_form"
      name={:no_blocks}
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

defmodule BrandoAdmin.SyncTest.ArticleNotesFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.SyncTest.Article

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="article_form"
      name={:notes}
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

defmodule BrandoAdmin.SyncTest.ArticleElsewhereFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.SyncTest.Article

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="article_form"
      name={:elsewhere}
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

defmodule BrandoAdmin.SavedElsewhereTest.ShelfFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.SavedElsewhereTest.Shelf

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="shelf_form"
      name={@live_action}
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}
    >
      <:header>Shelf</:header>
    </.live_component>
    """
  end
end

defmodule BrandoAdmin.TransformerSaveTest.AlbumFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.TransformerSaveTest.Album

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="album_form"
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}
    >
      <:header>Album</:header>
    </.live_component>
    """
  end
end

defmodule BrandoAdmin.TransformerSaveTest.ReelFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.TransformerSaveTest.Reel

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="reel_form"
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}
    >
      <:header>Reel</:header>
    </.live_component>
    """
  end
end

# Any form of the note, by the live action (RichTextDefaultFormTest)
defmodule BrandoAdmin.RichTextDefaultFormTest.NoteFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.RichTextDefaultFormTest.Note

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="note_form"
      name={@live_action}
      entry_id={@entry_id}
      current_user={@current_user}
      presences={@presences}
      schema={@schema}
    >
      <:header>Note</:header>
    </.live_component>
    """
  end
end

# Form `:media`, `:locked_media` or `:superuser_media` (LockedMediaDeliveriesTest), and
# others by the live action
defmodule BrandoAdmin.SyncTest.ArticleMediaFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.SyncTest.Article

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="article_form"
      name={@live_action}
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

defmodule BrandoAdmin.SyncTest.ArticleAuthorFormLive do
  @moduledoc false
  use BrandoAdmin.LiveView.Form, schema: Brando.SyncTest.Article

  alias BrandoAdmin.Components.Form

  def render(assigns) do
    ~H"""
    <.live_component
      module={Form}
      id="article_form"
      name={:author}
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

# An application's own screens under Configuration (`BrandoAdmin.Menu.config_item/3`):
# one declares what it needs, the other declares nothing.
defmodule BrandoIntegrationAdmin.ShopSettingsLive do
  @moduledoc false
  use Phoenix.LiveView

  def __authorization__, do: {:read, :utilities}

  def render(assigns), do: ~H"<p>Shop settings</p>"
end

defmodule BrandoIntegrationAdmin.UndeclaredSettingsLive do
  @moduledoc false
  use Phoenix.LiveView

  def render(assigns), do: ~H"<p>Undeclared settings</p>"
end

defmodule BrandoIntegrationWeb.Router do
  @moduledoc false
  use Phoenix.Router
  import Brando.Router
  import Brando.Plug.I18n
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ~w(html)
    plug :fetch_session
    plug :fetch_flash
  end

  admin_routes do
    live "/projects", BrandoIntegrationWeb.Projects.ProjectListLive
    live "/articles", BrandoAdmin.SyncTest.ArticleListLive
    live "/policy-articles", BrandoAdmin.SyncPolicyTest.ArticleListLive
    live "/own-delete-pages", BrandoAdmin.OwnDeleteTest.PageListLive
    live "/slug-scope/language-articles", BrandoAdmin.SlugScopeTest.IndependentLanguageArticleListLive

    live "/slug-scope/language-articles/update/:entry_id",
         BrandoAdmin.SlugScopeTest.IndependentLanguageArticleFormLive,
         :update

    live "/slug-scope/table-articles", BrandoAdmin.SlugScopeTest.IndependentTableArticleListLive
    live "/restore/projects", BrandoAdmin.RestoreTest.ProjectListLive
    live "/slug-scope/table-articles/update/:entry_id", BrandoAdmin.SlugScopeTest.IndependentTableArticleFormLive, :update
    live "/articles/user-context", BrandoAdmin.SyncTest.ArticleUserContextListLive
    live "/articles/filters", BrandoAdmin.SyncTest.ArticleFiltersListLive
    live "/articles/create", BrandoAdmin.SyncTest.ArticleFormLive, :create
    live "/articles/update/:entry_id", BrandoAdmin.SyncTest.ArticleFormLive, :update
    live "/articles/update/:entry_id/no-blocks", BrandoAdmin.SyncTest.ArticleNoBlocksFormLive, :update
    live "/articles/create/locked", BrandoAdmin.SyncTest.ArticleLockedFormLive, :create
    live "/articles/update/:entry_id/locked", BrandoAdmin.SyncTest.ArticleLockedFormLive, :update
    live "/articles/create/locked-slug", BrandoAdmin.SyncTest.ArticleLockedSlugFormLive, :create
    live "/articles/update/:entry_id/locked-slug", BrandoAdmin.SyncTest.ArticleLockedSlugFormLive, :update
    live "/articles/create/media", BrandoAdmin.SyncTest.ArticleMediaFormLive, :media
    live "/articles/update/:entry_id/media", BrandoAdmin.SyncTest.ArticleMediaFormLive, :media
    live "/articles/update/:entry_id/locked_media", BrandoAdmin.SyncTest.ArticleMediaFormLive, :locked_media
    live "/articles/update/:entry_id/superuser_media", BrandoAdmin.SyncTest.ArticleMediaFormLive, :superuser_media
    live "/articles/update/:entry_id/superuser_items", BrandoAdmin.SyncTest.ArticleMediaFormLive, :superuser_items
    live "/articles/update/:entry_id/partial", BrandoAdmin.SyncTest.ArticleMediaFormLive, :partial
    live "/articles/update/:entry_id/rich_quotes", BrandoAdmin.SyncTest.ArticleMediaFormLive, :rich_quotes
    live "/articles/update/:entry_id/quote_listing", BrandoAdmin.SyncTest.ArticleMediaFormLive, :quote_listing
    live "/articles/update/:entry_id/entries", BrandoAdmin.SyncTest.ArticleMediaFormLive, :entries
    live "/articles/update/:entry_id/locked_entries", BrandoAdmin.SyncTest.ArticleMediaFormLive, :locked_entries
    live "/articles/update/:entry_id/policy_entries", BrandoAdmin.SyncTest.ArticleMediaFormLive, :policy_entries
    live "/articles/update/:entry_id/item_entries", BrandoAdmin.SyncTest.ArticleMediaFormLive, :item_entries
    live "/articles/update/:entry_id/bare_item_entries", BrandoAdmin.SyncTest.ArticleMediaFormLive, :bare_item_entries

    live "/articles/update/:entry_id/transformer_item_entries",
         BrandoAdmin.SyncTest.ArticleMediaFormLive,
         :transformer_item_entries

    live "/articles/update/:entry_id/transformer_rich_items",
         BrandoAdmin.SyncTest.ArticleMediaFormLive,
         :transformer_rich_items

    live "/articles/update/:entry_id/transformer_unlisted_items",
         BrandoAdmin.SyncTest.ArticleMediaFormLive,
         :transformer_unlisted_items

    live "/articles/update/:entry_id/custom_item_entries", BrandoAdmin.SyncTest.ArticleMediaFormLive, :custom_item_entries
    live "/articles/update/:entry_id/author_entries", BrandoAdmin.SyncTest.ArticleMediaFormLive, :author_entries
    live "/articles/update/:entry_id/notes", BrandoAdmin.SyncTest.ArticleNotesFormLive, :update
    live "/articles/update/:entry_id/author", BrandoAdmin.SyncTest.ArticleAuthorFormLive, :update
    live "/articles/update/:entry_id/elsewhere", BrandoAdmin.SyncTest.ArticleElsewhereFormLive, :update
    live "/meta-articles/update/:entry_id", BrandoAdmin.MetaDrawerTest.ActionsArticleFormLive, :update
    live "/shelves/update/:entry_id", BrandoAdmin.SavedElsewhereTest.ShelfFormLive, :default
    live "/shelves/update/:entry_id/title-only", BrandoAdmin.SavedElsewhereTest.ShelfFormLive, :title_only
    live "/albums/update/:entry_id", BrandoAdmin.TransformerSaveTest.AlbumFormLive, :update
    live "/reels/create", BrandoAdmin.TransformerSaveTest.ReelFormLive, :create
    live "/reels/update/:entry_id", BrandoAdmin.TransformerSaveTest.ReelFormLive, :update
    live "/rich-notes/update/:entry_id", BrandoAdmin.RichTextDefaultFormTest.NoteFormLive, :default
    live "/rich-notes/update/:entry_id/omitted", BrandoAdmin.RichTextDefaultFormTest.NoteFormLive, :omitted
    live "/rich-notes/update/:entry_id/plain", BrandoAdmin.RichTextDefaultFormTest.NoteFormLive, :plain
    live "/config/shop", BrandoIntegrationAdmin.ShopSettingsLive
    live "/config/undeclared", BrandoIntegrationAdmin.UndeclaredSettingsLive
  end

  form_routes()
  mcp_routes()

  scope "/coming-soon" do
    get "/", BrandoIntegration.LockdownController, :index
    post "/", BrandoIntegration.LockdownController, :unlock
  end

  scope "/", assigns: %{language: "en"} do
    pipe_through :browser
    get "/projects", BrandoIntegration.ProjectController, :index
    get "/project/:uri", BrandoIntegration.ProjectController, :show
    get "/project/:uri/:id", BrandoIntegration.ProjectController, :show

    scope "/no", as: :no, assigns: %{language: "no"} do
      get "/prosjekter", BrandoIntegration.ProjectController, :index
      get "/prosjekt/:uri", BrandoIntegration.ProjectController, :show
      get "/prosjekt/:uri/:id", BrandoIntegration.ProjectController, :show
    end

    scope "/en", as: :en, assigns: %{language: "en"} do
      get "/projects", BrandoIntegration.ProjectController, :scoped_index
      get "/project/:uri", BrandoIntegration.ProjectController, :scoped_show
      get "/project/:uri/:id", BrandoIntegration.ProjectController, :scoped_show
      get "/project/:slug/:creator_slug/:property_name", BrandoIntegration.ProjectController, :show_fancy
    end

    page_routes()
  end
end
