defmodule BrandoAdmin.AI.AssistantLive do
  @moduledoc """
  The content assistant workspace: a conversation beside the proposal it
  prepares.

  The model only reads content and prepares proposals (see `Brando.AI.Agent`).
  This view shows the proposal under review — built from the stored, frozen
  operations — and is the only place a proposal is approved and applied: one
  explicit click approves exactly the version on screen and applies it.
  """
  use BrandoAdmin, :live_view
  use BrandoAdmin.Toast
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.AI.Agent
  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.Review
  alias Brando.Repo
  alias BrandoAdmin.Components.ImagePicker
  alias BrandoAdmin.Components.VideoPicker
  alias Phoenix.LiveView.JS

  def __authorization__, do: {:use, :assistant}

  def mount(_params, %{"user_token" => token}, socket) do
    socket = BrandoAdmin.Hooks.assign_current_user(socket, token)
    Gettext.put_locale(Brando.Gettext, to_string(socket.assigns.current_user.language))
    deliver_topic = "form:" <> Ecto.UUID.generate()
    if connected?(socket), do: Phoenix.PubSub.subscribe(Brando.pubsub(), deliver_topic)

    {:ok,
     socket
     |> assign(
       socket_connected: connected?(socket),
       deliver_topic: deliver_topic,
       available?: Agent.available?(),
       video_uploads?: Brando.default_video_upload_strategy() == :local,
       scope_label: scope_label(socket),
       conversation: nil,
       target: nil,
       guidance: [],
       configurable?: Agent.Guidance.configurable?(socket.assigns.current_user),
       conversations: [],
       messages: [],
       turns: [],
       cost: nil,
       shared: nil,
       publish: MapSet.new(),
       review_link: nil,
       share_choice: nil,
       share_url: nil,
       run: nil,
       progress: nil,
       proposal: nil,
       review: [],
       media: %{},
       receipt: nil,
       error: nil,
       draft: "",
       show_history: false,
       applying: false,
       preview: nil,
       preview_keys: []
     )}
  end

  # A proposal a colleague shared for review: read-only, with page previews.
  def handle_params(%{"token" => token}, _uri, socket) do
    user = socket.assigns.current_user

    with {:ok, {id, version, keys}} <- Proposals.verify_share_token(token),
         {:ok, proposal} <- Proposals.get_shared(id, version, user) do
      owner = Brando.Repo.get(Brando.Users.User, proposal.actor_id)

      {:noreply,
       socket
       |> assign(
         # A link made for some entries shows, and previews, only those.
         shared: %{by: owner && owner.name, token: token, keys: keys},
         proposal: proposal,
         review: proposal |> Review.entries() |> Enum.filter(&(is_nil(keys) or &1.key in keys)),
         receipt: nil,
         error: nil,
         preview: nil
       )
       |> assign_media()}
    else
      _ ->
        {:noreply,
         socket
         |> put_toast(:error, gettext("This review link has expired or the proposal is no longer available."))
         |> push_navigate(to: "/admin/assistant")}
    end
  end

  def handle_params(%{"conversation_id" => id}, _uri, socket) do
    user = socket.assigns.current_user

    case Agent.get_conversation(id, user) do
      {:ok, conversation} ->
        if (connected?(socket) and socket.assigns.conversation) && socket.assigns.conversation.id != id,
          do: Phoenix.PubSub.unsubscribe(Brando.pubsub(), topic(socket.assigns.conversation.id))

        if connected?(socket), do: Agent.subscribe(conversation.id)

        {:noreply,
         socket
         |> assign(conversation: conversation, run: Agent.latest_run(id, user), progress: nil, error: nil, receipt: nil)
         |> assign_conversations()
         |> assign_messages()
         |> assign_proposal()
         |> assign_guidance()}

      {:error, message} ->
        {:noreply, socket |> put_toast(:error, message) |> push_patch(to: "/admin/assistant")}
    end
  end

  # `?content_type=…&id=…&field=…` comes from the block editor's Build with
  # AI action: the conversation started here works on that entry.
  def handle_params(params, _uri, socket) do
    {target, socket} =
      case params do
        %{"content_type" => _, "id" => _} ->
          case Agent.target(params, socket.assigns.current_user) do
            {:ok, target} -> {target, socket}
            {:error, message} -> {nil, put_toast(socket, :error, message)}
          end

        _ ->
          {nil, socket}
      end

    {:noreply,
     socket
     |> assign(
       conversation: nil,
       messages: [],
       turns: [],
       cost: nil,
       run: nil,
       proposal: nil,
       review: [],
       receipt: nil,
       error: nil
     )
     |> assign(:target, target)
     |> assign_conversations()
     |> assign_guidance()}
  end

  ## Render

  def render(%{shared: %{}} = assigns) do
    ~H"""
    <div class="assistant-workspace is-shared" id="assistant">
      <header class="assistant-header">
        <div class="assistant-heading">
          <span class="assistant-mark" aria-hidden="true"><.icon name="hero-eye" /></span>
          <div>
            <h1>{gettext("Proposal for review")}</h1>
            <p>
              {gettext("Shared by %{name}. You can look at the changes and the pages; only %{name} can apply them.",
                name: @shared.by || gettext("a colleague")
              )}
            </p>
          </div>
        </div>
      </header>
      <section class="assistant-review is-shared" aria-label={gettext("Proposal")}>
        <.review
          proposal={@proposal}
          review={@review}
          media={@media}
          aliases={%{}}
          receipt={nil}
          run={nil}
          error={@error}
          applying={false}
          preview={@preview}
          shared
          share_url={@share_url}
        />
      </section>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="assistant-workspace" id="assistant">
      <header class="assistant-header">
        <div class="assistant-heading">
          <span class="assistant-mark" aria-hidden="true"><.icon name="hero-sparkles" /></span>
          <div>
            <h1>{gettext("Assistant")}</h1>
            <p>{gettext("Create and edit content across entries. Nothing changes until you apply it.")}</p>
          </div>
        </div>
        <div class="assistant-header-actions">
          <span class="assistant-scope">
            <.icon name="hero-globe-alt" />{@scope_label}<span aria-hidden="true">·</span>{language_label(
              @conversation || (@target && @target["language"])
            )}
          </span>
          <div class="assistant-history">
            <button
              type="button"
              class="assistant-quiet-button"
              phx-click="toggle_history"
              aria-expanded={to_string(@show_history)}
              aria-controls="assistant-history-list"
            >
              <.icon name="hero-clock" />{gettext("Recent conversations")}
            </button>
            <ul :if={@show_history} id="assistant-history-list" class="assistant-history-list">
              <li :if={@conversations == []} class="assistant-history-empty">{gettext("No conversations yet")}</li>
              <li :for={conversation <- @conversations}>
                <.link
                  patch={"/admin/assistant/#{conversation.id}"}
                  aria-current={@conversation && @conversation.id == conversation.id && "page"}
                >
                  <span>{conversation.title || gettext("Untitled")}</span>
                  <time>{Calendar.strftime(conversation.updated_at, "%d.%m %H:%M")}</time>
                </.link>
              </li>
            </ul>
          </div>
          <.link patch="/admin/assistant" class="assistant-button">
            <.icon name="hero-plus" />{gettext("New conversation")}
          </.link>
        </div>
      </header>

      <details :if={@guidance != [] or @configurable?} class="assistant-guidance" id="assistant-guidance">
        <summary>
          <.icon name="hero-book-open" />
          <span :if={@guidance != []}>{gettext("Site guidance in use")}</span>
          <span :if={@guidance == []}>{gettext("No site guidance")}</span>
        </summary>
        <div class="assistant-guidance-body">
          <p>
            {gettext(
              "The assistant follows this guidance for the site. Your own requests take precedence, and every proposal is still reviewed."
            )}
          </p>
          <div :for={part <- @guidance} class="assistant-guidance-part">
            <h3>
              {if part.source == :admin, do: gettext("From the administrators"), else: gettext("From the site's code")}
            </h3>
            <pre>{part.text}</pre>
          </div>
          <.link :if={@configurable?} navigate="/admin/config/assistant" class="assistant-link-button">
            {gettext("Edit guidance")}
          </.link>
        </div>
      </details>

      <div :if={!@available?} class="assistant-notice" role="status">
        {gettext(
          "No AI model is configured for this site. Add a model and key to the Brando.AI configuration to use the assistant."
        )}
      </div>

      <div class="assistant-body">
        <section class="assistant-chat" aria-label={gettext("Conversation")}>
          <div class="assistant-chat-title">
            <h2>{(@conversation && @conversation.title) || gettext("New conversation")}</h2>
            <span :if={@conversation}>{Calendar.strftime(@conversation.inserted_at, "%d.%m.%Y %H:%M")}</span>
          </div>

          <.destination target={(@conversation && @conversation.target) || @target} />

          <div class="assistant-messages" id="assistant-messages" tabindex="0" aria-live="polite">
            <div class="assistant-messages-inner">
              <p :if={@messages == []} class="assistant-intro">
                {gettext(
                  "Describe the changes you want: which entries, which media and where it goes. Attach media first and refer to it as image1, video1 and so on."
                )}
              </p>
              <.message
                :for={item <- @turns}
                item={item}
                media={@media}
                aliases={aliases(@conversation)}
                available?={@available? and !running?(@run)}
              />
              <div :if={@progress} class="assistant-progress" role="status">
                <span class="assistant-spinner" aria-hidden="true"></span>
                <span>{@progress}</span>
                <button type="button" class="assistant-link-button" phx-click="cancel_run">{gettext("Stop")}</button>
              </div>
            </div>
          </div>

          <.attachments conversation={@conversation} media={@media} used={used_aliases(@proposal)} />

          <form id="assistant-composer" class="assistant-composer" phx-submit="send" phx-change="draft">
            <label for="assistant-input" class="visually-hidden">{gettext("Message")}</label>
            <textarea
              id="assistant-input"
              name="message"
              rows="3"
              phx-hook="Brando.AssistantComposer"
              placeholder={
                if @proposal,
                  do: gettext("Ask for an adjustment…"),
                  else: gettext("Describe the content changes…")
              }
              disabled={!@available?}
            >{@draft}</textarea>
            <div class="assistant-composer-actions">
              <div
                id="assistant-upload"
                phx-hook="Brando.UploadTrigger"
                data-kind="ai_conversation"
                data-component-id="assistant"
                data-asset-type="image"
                data-allowed-types={if @video_uploads?, do: "image,video", else: "image"}
                data-deliver-topic={@deliver_topic}
                data-config-target="default"
                data-click-mode="trigger"
                class="assistant-upload"
              >
                <button
                  type="button"
                  class="assistant-tool upload-trigger"
                  disabled={!@available?}
                  title={gettext("Upload images or videos")}
                >
                  <.icon name="hero-arrow-up-tray" /><span class="visually-hidden">{gettext("Upload")}</span>
                </button>
                <input
                  type="file"
                  class="file-input"
                  multiple
                  accept={if @video_uploads?, do: "image/*,video/*", else: "image/*"}
                  aria-label={gettext("Upload media")}
                />
              </div>
              <button
                type="button"
                class="assistant-tool"
                phx-click={JS.push("browse_library", value: %{kind: "image"}) |> toggle_drawer("#image-picker")}
                disabled={!@available?}
                title={gettext("Attach images from the media library")}
              >
                <.icon name="hero-photo" /><span class="visually-hidden">{gettext("Images")}</span>
              </button>
              <button
                type="button"
                class="assistant-tool"
                phx-click={JS.push("browse_library", value: %{kind: "video"}) |> toggle_drawer("#video-picker")}
                disabled={!@available?}
                title={gettext("Attach videos from the media library")}
              >
                <.icon name="hero-film" /><span class="visually-hidden">{gettext("Videos")}</span>
              </button>
              <span :if={attached_count(@conversation) > 0} class="assistant-attached-count">
                {ngettext("%{count} attached", "%{count} attached", attached_count(@conversation))}
              </span>
              <button
                type="submit"
                class="assistant-send"
                disabled={!@available? or running?(@run)}
                aria-label={gettext("Send")}
              >
                <.icon name="hero-arrow-up" />
              </button>
            </div>
          </form>
          <p class="assistant-footnote">
            {gettext("Changes are only applied after your confirmation.")}
            <span :if={@cost && @cost > 0} class="assistant-cost" title={gettext("Estimated from the model's token prices")}>
              {gettext("Estimated cost so far: %{cost}", cost: format_cost(@cost))}
            </span>
          </p>
        </section>

        <section class="assistant-review" aria-label={gettext("Proposal")}>
          <.review
            proposal={@proposal}
            review={@review}
            media={@media}
            aliases={aliases(@conversation)}
            receipt={@receipt}
            run={@run}
            error={@error}
            applying={@applying}
            preview={@preview}
            publish={@publish}
            review_link={@review_link}
            share_choice={@share_choice}
            share_url={@share_url}
          />
        </section>
      </div>

      <.live_component module={ImagePicker} id="image-picker" />
      <.live_component module={VideoPicker} id="video-picker" current_user={@current_user} />
    </div>
    """
  end

  attr :item, :map, required: true
  attr :media, :map, default: %{}
  attr :aliases, :map, default: %{}
  attr :available?, :boolean, default: false

  defp message(%{item: %{role: "request"}} = assigns) do
    ~H"""
    <section class={["assistant-request", @item.open? && "is-open"]} aria-label={gettext("The assistant asks for media")}>
      <header>
        <.icon name={if @item.kind == "video", do: "hero-film", else: "hero-photo"} />
        <span>
          {if @item.kind == "video",
            do: gettext("The assistant asks for videos"),
            else: gettext("The assistant asks for images")}
        </span>
      </header>
      <p :if={@item.reason} class="assistant-request-reason">{@item.reason}</p>
      <div :if={@item.open? and @item.suggested != []} class="assistant-request-suggestions">
        <button
          :for={id <- @item.suggested}
          type="button"
          class={["assistant-request-item", Map.has_key?(@aliases, {to_kind(@item.kind), id}) && "is-picked"]}
          phx-click={"select_#{@item.kind}"}
          phx-value-id={id}
          aria-pressed={to_string(Map.has_key?(@aliases, {to_kind(@item.kind), id}))}
          title={media_label(%{kind: @item.kind, id: id}, @aliases, @media)}
          disabled={!@available?}
        >
          <.thumb media={@media} kind={@item.kind} id={id} />
          <span :if={Map.has_key?(@aliases, {to_kind(@item.kind), id})} class="assistant-request-alias">
            {@aliases[{to_kind(@item.kind), id}]["alias"]}
          </span>
        </button>
      </div>
      <button
        :if={@item.open?}
        type="button"
        class="assistant-apply assistant-request-use"
        phx-click="send"
        phx-value-message={gettext("I have attached the media. Use it.")}
        disabled={!@available? or attached(@aliases, @item.kind) == 0}
      >
        {if attached(@aliases, @item.kind) == 0,
          do: gettext("Pick some above, or choose another way"),
          else: ngettext("Use the %{count} I attached", "Use the %{count} I attached", attached(@aliases, @item.kind))}
        <.icon :if={attached(@aliases, @item.kind) > 0} name="hero-arrow-right" />
      </button>
      <div :if={@item.open?} class="assistant-request-other">
        <span>{gettext("Or")}</span>
        <button
          type="button"
          phx-click={JS.push("browse_library", value: %{kind: @item.kind}) |> toggle_drawer("##{@item.kind}-picker")}
          disabled={!@available?}
        >
          <.icon name="hero-rectangle-stack" />{gettext("Browse the library")}
        </button>
        <button
          type="button"
          phx-click={JS.dispatch("click", to: "#assistant-upload .upload-trigger")}
          disabled={!@available?}
        >
          <.icon name="hero-arrow-up-tray" />{gettext("Upload")}
        </button>
        <button
          type="button"
          phx-click="send"
          phx-value-message={gettext("Choose suitable ones from the library yourself.")}
          disabled={!@available?}
        >
          <.icon name="hero-sparkles" />{gettext("Let the assistant choose")}
        </button>
      </div>
    </section>
    """
  end

  defp message(%{item: %{role: "user"}} = assigns) do
    ~H"""
    <div class="assistant-message is-user">
      <span class="assistant-author">{gettext("You")}</span>
      <div class="assistant-bubble">{@item.content}</div>
    </div>
    """
  end

  defp message(%{item: %{role: "steps"}} = assigns) do
    ~H"""
    <ul class="assistant-steps">
      <li :for={step <- @item.steps}><.icon name="hero-check" />{step}</li>
    </ul>
    """
  end

  defp message(assigns) do
    ~H"""
    <div class="assistant-message is-assistant">
      <span class="assistant-author"><.icon name="hero-sparkles" />{gettext("Assistant")}</span>
      <div class="assistant-text">{markdown(@item.content)}</div>
    </div>
    """
  end

  attr :target, :map, default: nil

  # The entry the conversation was opened for from the block editor.
  defp destination(%{target: nil} = assigns), do: ~H""

  defp destination(assigns) do
    assigns =
      assign(assigns,
        type:
          case Proposals.Codec.schema(assigns.target["content_type"]) do
            {:ok, schema} -> Brando.Blueprint.get_singular(schema)
            :error -> assigns.target["content_type"]
          end,
        url:
          case Proposals.Codec.schema(assigns.target["content_type"]) do
            {:ok, schema} -> admin_url(schema, assigns.target["id"])
            :error -> nil
          end
      )

    ~H"""
    <section class="assistant-destination" id="assistant-destination" aria-label={gettext("Selected entry")}>
      <span class="assistant-destination-label">{gettext("Working on")}</span>
      <dl class="assistant-destination-meta">
        <div class="is-entry">
          <dt>{gettext("Entry")}</dt>
          <dd class="assistant-destination-title">
            <.link :if={@url} navigate={@url}>{@target["title"]}</.link>
            <span :if={!@url}>{@target["title"]}</span>
          </dd>
        </div>
        <div>
          <dt>{gettext("Type")}</dt>
          <dd>{@type}</dd>
        </div>
        <div>
          <dt>{gettext("Block field")}</dt>
          <dd>{field_label(@target["field"])}</dd>
        </div>
        <div :if={@target["language"]}>
          <dt>{gettext("Language")}</dt>
          <dd>{language_label(@target["language"])}</dd>
        </div>
      </dl>
      <p class="assistant-destination-note">
        {gettext(
          "The assistant reads the saved entry. Unsaved changes in the editor are not included; save them first if the assistant should build on them."
        )}
      </p>
    </section>
    """
  end

  attr :conversation, :any, required: true
  attr :media, :map, required: true
  attr :used, :any, default: nil

  defp attachments(assigns) do
    items = (assigns.conversation && assigns.conversation.attachments) || []
    used = assigns.used && Enum.count(items, &used?(assigns.used, &1))
    assigns = assign(assigns, items: items, used_count: used)

    ~H"""
    <div :if={@items != []} class="assistant-attachments">
      <div class="assistant-attachments-header">
        <span>{gettext("Attached to this conversation")}</span>
        <span>{ngettext("%{count} item", "%{count} items", length(@items))}</span>
      </div>
      <ul class="assistant-attachment-grid">
        <li
          :for={item <- @items}
          class={[
            "assistant-attachment",
            !item["id"] && "is-pending",
            @used && used?(@used, item) && "is-used"
          ]}
        >
          <.thumb media={@media} kind={item["kind"]} id={item["id"]} label={item["label"]} />
          <span :if={@used && used?(@used, item)} class="assistant-used" title={gettext("Used in the proposal")}>
            <.icon name="hero-check" />
          </span>
          <span class="assistant-alias">{item["alias"]}</span>
          <span :if={!item["id"]} class="assistant-attachment-status">{gettext("Uploading…")}</span>
          <button
            type="button"
            class="assistant-remove"
            phx-click="detach"
            phx-value-alias={item["alias"]}
            aria-label={gettext("Remove %{alias}", alias: item["alias"])}
          >
            <.icon name="hero-x-mark" />
          </button>
        </li>
      </ul>
      <p :if={@used} class="assistant-attachments-note">
        {gettext("%{used} used in the proposal · %{free} not used", used: @used_count, free: length(@items) - @used_count)}
      </p>
    </div>
    """
  end

  attr :media, :map, required: true
  attr :kind, :any, required: true
  attr :id, :any, required: true
  attr :label, :string, default: nil

  defp thumb(assigns) do
    assigns = assign(assigns, :asset, Map.get(assigns.media, {to_kind(assigns.kind), assigns.id}))

    ~H"""
    <span class={["assistant-thumb", "is-#{@kind}"]}>
      <img :if={@asset && @asset.url} src={@asset.url} alt={@label || ""} loading="lazy" />
      <.icon :if={!(@asset && @asset.url)} name={thumb_icon(@kind)} />
      <span :if={to_string(@kind) == "video"} class="assistant-play" aria-hidden="true"><.icon name="hero-play" /></span>
    </span>
    """
  end

  attr :proposal, :any, required: true
  attr :review, :list, required: true
  attr :media, :map, required: true
  attr :aliases, :map, default: %{}
  attr :receipt, :any, required: true
  attr :run, :any, default: nil
  attr :error, :any, required: true
  attr :applying, :boolean, required: true
  attr :preview, :any, default: nil
  attr :shared, :boolean, default: false
  attr :publish, :any, default: MapSet.new()
  attr :review_link, :string, default: nil
  attr :share_choice, :list, default: nil
  attr :share_url, :string, default: nil

  defp review(%{proposal: nil} = assigns) do
    ~H"""
    <div class="assistant-empty">
      <span class="assistant-empty-mark" aria-hidden="true"><.icon name="hero-document-magnifying-glass" /></span>
      <h2>{gettext("No proposal yet")}</h2>
      <p>
        {gettext(
          "Describe the changes in the conversation. The assistant prepares them here for review, entry by entry, and nothing is saved until you apply them."
        )}
      </p>
      <div class="assistant-suggestions">
        <span>{gettext("For example")}</span>
        <button
          :for={
            text <- [
              gettext("Put image1 on the Index page, after the introduction"),
              gettext("Create a case called Sommerro with image1 as its cover"),
              gettext("Rewrite the introduction on the About page to be shorter")
            ]
          }
          type="button"
          phx-click="suggest"
          phx-value-text={text}
        >
          {text}
        </button>
      </div>
    </div>
    """
  end

  defp review(assigns) do
    assigns =
      assign(assigns,
        live: length(assigns.proposal.effects[:live] || []),
        entry_changes: (assigns.proposal.effects[:creates] || 0) + (assigns.proposal.effects[:updates] || 0),
        problems?: assigns.proposal.problems != [],
        general_problems: Enum.filter(assigns.proposal.problems, &(is_nil(&1[:operation]) and is_nil(&1[:target]))),
        entry_problems: for(entry <- assigns.review, problem <- entry.problems, do: {entry, problem}),
        # A change can be left out while the proposal is under review, and
        # while something else would remain.
        can_leave_out?:
          !assigns.shared and is_nil(assigns.receipt) and assigns.proposal.status in ~w(pending approved) and
            length(assigns.proposal.operations) > 1 and !running?(assigns.run),
        under_review?: is_nil(assigns.receipt) and assigns.proposal.status in ~w(pending approved)
      )

    ~H"""
    <div class={["assistant-proposal", @preview && "is-previewing"]} id={"proposal-#{@proposal.id}"}>
      <div class="assistant-proposal-head">
        <span class="assistant-eyebrow">
          {gettext("Proposal · version %{version}", version: @proposal.version)}
          <span :if={is_nil(@receipt) and @proposal.status in ~w(pending approved)}> · {gettext("not applied")}</span>
        </span>
        <h2 :if={!@preview}>{proposal_title(@proposal, @receipt)}</h2>
        <p :if={@proposal.summary && !@preview} class="assistant-summary">{@proposal.summary}</p>
        <p :if={!@preview} class="assistant-counts">
          <span :for={{count, label} <- counts(@proposal.effects)}><strong>{count}</strong> {label}</span>
        </p>
        <div :if={!@shared and !@preview and @under_review?} class="assistant-share">
          <button :if={!@review_link and !@share_choice} type="button" class="assistant-button" phx-click="share_review">
            <.icon name="hero-user-plus" />{gettext("Share for review")}
          </button>
          <form :if={@share_choice} class="assistant-share-choice" phx-submit="share_review">
            <fieldset>
              <legend>{gettext("Which entries should the link show?")}</legend>
              <label :for={entry <- @review} class="assistant-check">
                <input type="checkbox" name="keys[]" value={entry.key} checked={entry.key in @share_choice} />
                <span>{entry.title}</span>
                <small>{entry.content_type}</small>
              </label>
            </fieldset>
            <div>
              <button type="submit" class="assistant-button">
                <.icon name="hero-link" />{gettext("Create link")}
              </button>
              <button type="button" class="assistant-quiet-button" phx-click="cancel_share">{gettext("Cancel")}</button>
            </div>
          </form>
          <div :if={@review_link} class="assistant-share-link">
            <label for="assistant-review-link">{gettext("Colleagues with access to the admin can review it for a day:")}</label>
            <input id="assistant-review-link" type="text" readonly value={@review_link} />
          </div>
        </div>
      </div>

      <div :if={@error} class="assistant-feedback is-error" role="alert">{@error}</div>

      <div :if={@problems? and !@receipt} class="assistant-feedback is-warning" role="status">
        <p>{gettext("This proposal cannot be applied yet. Ask the assistant to adjust it.")}</p>
        <ul class="assistant-feedback-problems">
          <li :for={{entry, problem} <- @entry_problems}>
            <a href={"#card-#{entry.key}"}>{entry.title}</a> {problem.message}
          </li>
          <li :for={problem <- @general_problems}>{problem.message}</li>
        </ul>
      </div>

      <div :if={@receipt} class="assistant-feedback is-success" role="status">
        <p>{gettext("The changes are saved. Pages are re-rendered in the background.")}</p>
        <ul class="assistant-receipt">
          <li :for={item <- @review}>
            <.link :if={item[:saved_url]} navigate={item.saved_url}>{item.title}</.link>
            <span :if={!item[:saved_url]}>{item.title}</span>
            <span class="assistant-badge">{receipt_badge(item, @receipt)}</span>
          </li>
        </ul>
        <button
          :if={@proposal.status == "applied"}
          type="button"
          class="assistant-button assistant-undo"
          phx-click="undo"
          data-confirm={gettext("Undo the proposal? Each entry goes back to how it was before, and new entries are deleted.")}
        >
          <.icon name="hero-arrow-uturn-left" />{gettext("Undo")}
        </button>
        <p :if={@proposal.status == "undone"}>{gettext("Undone: the entries are back to how they were.")}</p>
      </div>

      <.page_preview
        :if={@preview}
        preview={@preview}
        review={@review}
        media={@media}
        aliases={@aliases}
        share_url={@share_url}
      />

      <div :if={!@preview} class="assistant-section-head">
        <h3>{gettext("Changes by entry")}</h3>
      </div>
      <div :if={!@preview} class="assistant-cards">
        <article
          :for={entry <- @review}
          class={["assistant-card", entry.problems != [] && "has-problems"]}
          id={"card-#{entry.key}"}
        >
          <div :if={entry.media != [] and adds_content?(entry)} class="assistant-card-cover">
            <.thumb media={@media} kind={elem(hd(entry.media), 0)} id={elem(hd(entry.media), 1)} />
            <span class="assistant-cover-label">{media_label(media_map(hd(entry.media)), @aliases, @media)}</span>
          </div>
          <div class="assistant-card-body">
            <header>
              <span class="assistant-card-type">{entry.content_type}</span>
              <span class={["assistant-badge", "is-#{entry.action}"]}>
                {if entry.action == :create, do: gettext("Create"), else: gettext("Update")}
              </span>
            </header>
            <h4>
              <.link :if={entry.admin_url} navigate={entry.admin_url}>{entry.title}</.link>
              <span :if={!entry.admin_url}>{entry.title}</span>
            </h4>
            <p :if={entry.url} class="assistant-card-url">{entry.url}</p>
            <button
              :if={entry.preview? and is_nil(@receipt)}
              type="button"
              class="assistant-button assistant-card-preview"
              phx-click="preview"
              phx-value-key={entry.key}
            >
              <.icon name="hero-eye" />{gettext("Preview page")}
            </button>

            <div :if={entry.placeholders != []} class="assistant-placeholders">
              <strong>
                <.icon name="hero-pencil-square" />
                {ngettext(
                  "%{count} place needs your input",
                  "%{count} places need your input",
                  length(entry.placeholders)
                )}
              </strong>
              <p>
                {gettext("The assistant marked what it could not know with [[ ]]. Fill it in on the entry before publishing.")}
              </p>
              <ul>
                <li :for={placeholder <- entry.placeholders}>
                  <span>{placeholder.where}</span>
                  <mark>{placeholder.text}</mark>
                </li>
              </ul>
            </div>

            <ul class="assistant-changes">
              <li :for={change <- entry.changes} class={change[:operations] && @can_leave_out? && "can-leave-out"}>
                <.change change={change} aliases={@aliases} media={@media} applied={!is_nil(@receipt)} />
                <button
                  :if={change[:operations] && @can_leave_out?}
                  type="button"
                  class="assistant-leave-out"
                  phx-click="leave_out"
                  phx-value-operations={Enum.join(change.operations, ",")}
                  phx-value-subject={change_subject(change)}
                  title={gettext("Leave this change out of the proposal")}
                >
                  <.icon name="hero-x-mark" /><span>{gettext("Leave out")}</span>
                </button>
              </li>
            </ul>

            <ul :if={entry.problems != []} class="assistant-problems">
              <li :for={problem <- entry.problems}><.icon name="hero-exclamation-triangle" />{problem.message}</li>
            </ul>

            <div :if={(entry[:languages] || []) != []} class="assistant-languages">
              <span>{gettext("Other languages")}</span>
              <ul>
                <li :for={version <- entry.languages} class={"is-#{version.state}"}>
                  <strong>{language_label(version.language)}</strong>
                  <span>{language_state(version.state)}</span>
                </li>
              </ul>
            </div>

            <label :if={!@shared and @under_review? and publishable?(entry)} class="assistant-check assistant-publish">
              <input
                type="checkbox"
                phx-click="toggle_publish"
                phx-value-key={entry.key}
                disabled={entry.placeholders != []}
                checked={MapSet.member?(@publish, entry.key) and entry.placeholders == []}
              />
              {gettext("Publish when applied")}
            </label>
          </div>

          <footer>
            <span :if={entry.live?} class="assistant-live"><.icon name="hero-globe-alt" />{gettext("Live page")}</span>
            <span :if={entry.action == :create} class="assistant-draft"><.icon name="hero-lock-closed" />{gettext("New draft")}</span>
            <span :if={entry.action == :update and !entry.live?} class="assistant-draft">{gettext("Not published")}</span>
          </footer>
        </article>
      </div>

      <div :if={!@shared and @under_review?} class="assistant-apply-bar">
        <div class="assistant-apply-summary">
          <strong>{entry_summary(@proposal.effects)}</strong>
          <span>{block_summary(@proposal.effects)}</span>
        </div>
        <div class="assistant-apply-actions">
          <button type="button" class="assistant-button assistant-discard" phx-click="cancel_proposal">
            {gettext("Discard")}
          </button>
          <button type="button" class="assistant-button" phx-click={JS.focus(to: "#assistant-input")}>
            {gettext("Adjust")}
          </button>
          <button
            type="button"
            class="assistant-apply"
            phx-click="apply"
            phx-value-id={@proposal.id}
            phx-value-version={@proposal.version}
            disabled={@problems? or @applying}
            phx-disable-with={gettext("Applying…")}
          >
            {apply_label(@entry_changes, @live)}<.icon name="hero-arrow-right" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :preview, :map, required: true
  attr :review, :list, required: true
  attr :media, :map, required: true
  attr :aliases, :map, default: %{}
  attr :share_url, :string, default: nil

  defp page_preview(assigns) do
    assigns = assign(assigns, :entry, Enum.find(assigns.review, &(&1.key == assigns.preview.key)))

    ~H"""
    <section class="assistant-preview" aria-labelledby="assistant-preview-title">
      <div class="assistant-preview-head">
        <button type="button" class="assistant-link-button assistant-back" phx-click="close_preview">
          <.icon name="hero-arrow-left" />{gettext("All changes")}
        </button>
        <h3 id="assistant-preview-title">{gettext("Page preview")}</h3>
        <p>{gettext("The proposed content in the site's own templates. Nothing is saved.")}</p>
      </div>

      <nav class="assistant-preview-tabs" aria-label={gettext("Entries in this proposal")}>
        <button
          :for={entry <- @review}
          type="button"
          phx-click="preview"
          phx-value-key={entry.key}
          aria-current={entry.key == @preview.key && "true"}
        >
          <.thumb :if={entry.media != []} media={@media} kind={elem(hd(entry.media), 0)} id={elem(hd(entry.media), 1)} />
          <span>
            <strong>{entry.title}</strong>
            <small>{tab_summary(entry)}</small>
          </span>
        </button>
      </nav>

      <div class="assistant-preview-controls">
        <div class="assistant-segmented" role="group" aria-label={gettext("Version")}>
          <button
            :for={{value, label} <- [{"before", gettext("Before")}, {"proposed", gettext("Proposed")}]}
            type="button"
            phx-click="preview_version"
            phx-value-version={value}
            aria-pressed={to_string(@preview.version == value)}
          >
            {label}
          </button>
        </div>
        <div
          :if={@entry && length(@entry.preview_targets) > 1}
          class="assistant-segmented"
          role="group"
          aria-label={gettext("View")}
        >
          <button
            :for={{name, label} <- @entry.preview_targets}
            type="button"
            phx-click="preview_target"
            phx-value-target={name}
            aria-pressed={to_string((@preview.target || default_target(@entry)) == name)}
          >
            {label}
          </button>
        </div>
        <div class="assistant-preview-options">
          <div class="assistant-segmented" role="group" aria-label={gettext("Viewport")}>
            <button
              :for={
                {value, label, icon} <- [
                  {"desktop", gettext("Desktop"), "hero-computer-desktop"},
                  {"mobile", gettext("Mobile"), "hero-device-phone-mobile"}
                ]
              }
              type="button"
              phx-click="preview_viewport"
              phx-value-viewport={value}
              aria-pressed={to_string(@preview.viewport == value)}
            >
              <.icon name={icon} />{label}
            </button>
          </div>
          <label class="assistant-check">
            <input
              type="checkbox"
              phx-click="toggle_highlight"
              checked={@preview.show}
              disabled={@preview.version == "before"}
            />
            {gettext("Show changes")}
          </label>
        </div>
      </div>

      <div class={["assistant-frame", "is-#{@preview.viewport}"]}>
        <div class="assistant-frame-bar">
          <span class="assistant-frame-dots" aria-hidden="true"><i></i><i></i><i></i></span>
          <span class="assistant-frame-url">
            <.icon name="hero-lock-closed" />{frame_url(@entry)}
          </span>
          <span class={["assistant-frame-version", @preview.version == "proposed" && "is-proposed"]}>
            {if @preview.version == "before", do: gettext("Saved version"), else: gettext("Proposed")}
          </span>
          <a
            :if={match?({:ok, _}, @preview.frame)}
            class="assistant-frame-action"
            href={"/__livepreview?key=#{elem(@preview.frame, 1)}&mode=standalone"}
            target="_blank"
            rel="noopener"
          >
            <.icon name="hero-arrow-top-right-on-square" />{gettext("Open in a new tab")}
          </a>
          <button
            :if={@preview.version == "proposed" and match?({:ok, _}, @preview.frame)}
            type="button"
            class="assistant-frame-action"
            phx-click="share_page"
          >
            <.icon name="hero-link" />{gettext("Share a link")}
          </button>
        </div>
        <div :if={@share_url} class="assistant-share-link">
          <label for="assistant-page-link">
            {ngettext(
              "Anyone with this link can see the proposed page for %{count} day:",
              "Anyone with this link can see the proposed page for %{count} days:",
              @share_url.days
            )}
          </label>
          <input id="assistant-page-link" type="text" readonly value={@share_url.url} />
          <a href={@share_url.url} target="_blank" rel="noopener">{gettext("Open")}</a>
        </div>
        <.frame preview={@preview} entry={@entry} />
      </div>

      <ul :if={@entry} class="assistant-preview-summary">
        <li :for={change <- @entry.changes}>
          <.icon name="hero-check" />
          <div><.change change={change} aliases={@aliases} /></div>
        </li>
      </ul>
    </section>
    """
  end

  attr :preview, :map, required: true
  attr :entry, :any, required: true

  defp frame(%{preview: %{frame: {:ok, key}}} = assigns) do
    assigns =
      assign(assigns,
        key: key,
        highlight: if(assigns.preview.version == "proposed" and assigns.entry, do: assigns.entry.highlight, else: [])
      )

    ~H"""
    <div class="assistant-frame-viewport">
      <iframe
        id={"assistant-preview-frame-#{@key}"}
        src={"/__livepreview?key=#{@key}"}
        title={gettext("Page preview of %{title}", title: @entry && @entry.title)}
        phx-hook="Brando.ProposalPreview"
        data-highlight={Jason.encode!(@highlight)}
        data-show={to_string(@preview.show)}
        data-viewport={@preview.viewport}
      ></iframe>
    </div>
    """
  end

  defp frame(%{preview: %{frame: :not_created}} = assigns) do
    ~H"""
    <div class="assistant-frame-state">
      <.icon name="hero-document-plus" />
      <p>{gettext("This page has not been created yet. Switch to Proposed to see it.")}</p>
    </div>
    """
  end

  defp frame(%{preview: %{frame: :no_preview_target}} = assigns) do
    ~H"""
    <div class="assistant-frame-state">
      <.icon name="hero-eye-slash" />
      <p>{gettext("Page preview is not configured for this content type. Review the changes in the entry card.")}</p>
    </div>
    """
  end

  defp frame(%{preview: %{frame: {:error, message}}} = assigns) do
    assigns = assign(assigns, :message, message)

    ~H"""
    <div class="assistant-frame-state is-error" role="alert">
      <.icon name="hero-exclamation-triangle" />
      <p>{gettext("The page could not be rendered: %{message}", message: @message)}</p>
      <button type="button" class="assistant-button" phx-click="preview" phx-value-key={@preview.key}>
        {gettext("Try again")}
      </button>
    </div>
    """
  end

  attr :change, :map, required: true
  attr :aliases, :map, default: %{}
  attr :media, :map, default: %{}
  # After apply the entry already holds the new block, so the outline's
  # neighbour would be the block itself; the placement text stays true.
  attr :applied, :boolean, default: false

  defp change(%{change: %{type: :create}} = assigns) do
    ~H"""
    <span class="assistant-change-title">{gettext("Create the entry as a draft")}</span>
    <dl class="assistant-fields">
      <div :for={field <- @change.fields}>
        <dt>{field.name}</dt>
        <dd>
          <span :if={field.media} class="assistant-inline-media">
            <.thumb media={@media} kind={field.media.kind} id={field.media.id} />{media_label(field.media, @aliases, @media)}
          </span>
          <span :if={!field.media}>{to_string(field.value)}</span>
        </dd>
      </div>
    </dl>
    """
  end

  defp change(%{change: %{type: :fields}} = assigns) do
    ~H"""
    <span class="assistant-change-title">{gettext("Change fields")}</span>
    <dl class="assistant-fields">
      <div :for={field <- @change.fields}>
        <dt>{field.name}</dt>
        <dd>
          <del :if={field.before not in [nil, ""]}>{to_string(field.before)}</del>
          <ins :if={!field.media}>{to_string(field.value)}</ins>
          <span :if={field.media} class="assistant-inline-media">
            <.thumb media={@media} kind={field.media.kind} id={field.media.id} />{media_label(field.media, @aliases, @media)}
          </span>
        </dd>
      </div>
    </dl>
    """
  end

  defp change(%{change: %{type: :insert_block}} = assigns) do
    ~H"""
    <span class="assistant-change-title">{gettext("Add a %{module} block", module: @change.module || gettext("module"))}</span>
    <div :if={!@applied and @change.placement} class="assistant-outline" aria-label={@change.placement.text}>
      <span :if={@change.placement.position == :before} class="is-new">+ {@change.module}</span>
      <span :if={@change.placement.position == :before} class="assistant-outline-arrow" aria-hidden="true">→</span>
      <span :if={@change.placement.anchor} class="is-anchor" title={@change.placement.anchor.excerpt}>
        {@change.placement.anchor.module}
      </span>
      <span :if={is_nil(@change.placement.anchor)} class="is-anchor is-empty">{gettext("Empty field")}</span>
      <span :if={@change.placement.position != :before} class="assistant-outline-arrow" aria-hidden="true">→</span>
      <span :if={@change.placement.position != :before} class="is-new">+ {@change.module}</span>
    </div>
    <p :if={@change.placement} class="assistant-placement">{@change.placement.text}</p>
    <dl
      :if={@change.texts != [] or @change.values != [] or @change.media != [] or @change.settings != []}
      class="assistant-fields"
    >
      <div :for={media <- @change.media}>
        <dt>{humanize(media.ref)}</dt>
        <dd class="assistant-inline-media">
          <.thumb media={@media} kind={media.kind} id={media.id} />{media_label(media, @aliases, @media)}
        </dd>
      </div>
      <div :for={text <- @change.texts}>
        <dt>{humanize(text.ref)}</dt><dd>{text.text}</dd>
      </div>
      <div :for={value <- @change.values}>
        <dt>{value.label || humanize(value.name)}</dt>
        <dd>
          <span :if={value.media} class="assistant-inline-media">
            <.thumb media={@media} kind={value.media.kind} id={value.media.id} />
          </span>
          <span :if={value.value not in [nil, ""]}>{to_string(value.value)}</span>
        </dd>
      </div>
      <div :for={setting <- @change.settings}>
        <dt>{humanize(setting.ref)} · {Brando.Content.Transfer.Labels.field(setting.name)}</dt>
        <dd>{to_string(setting.value)}</dd>
      </div>
    </dl>
    """
  end

  defp change(%{change: %{type: :block_media}} = assigns) do
    ~H"""
    <span class="assistant-change-title">{gettext("Replace media in %{block}", block: @change.block)}</span>
    <dl class="assistant-fields">
      <div :if={@change[:replaces] not in [nil, []]} class="is-before">
        <dt>{gettext("Now")}</dt>
        <dd>
          <del :for={media <- @change.replaces} class="assistant-inline-media">
            <.thumb media={@media} kind={media.kind} id={media.id} />{media_label(media, @aliases, @media)}
          </del>
        </dd>
      </div>
      <div>
        <dt>{if @change[:replaces] not in [nil, []], do: gettext("Proposed"), else: humanize(@change.ref)}</dt>
        <dd>
          <span :for={media <- @change.media} class="assistant-inline-media">
            <.thumb media={@media} kind={media.kind} id={media.id} />{media_label(media, @aliases, @media)}
          </span>
        </dd>
      </div>
    </dl>
    """
  end

  defp change(%{change: %{type: :block_text}} = assigns) do
    ~H"""
    <span class="assistant-change-title">{gettext("Rewrite text in %{block}", block: @change.block)}</span>
    <dl class="assistant-fields">
      <div>
        <dt>{humanize(@change.ref)}</dt>
        <dd><del :if={@change.before not in [nil, ""]}>{@change.before}</del> <ins>{@change.text}</ins></dd>
      </div>
    </dl>
    """
  end

  defp change(%{change: %{type: :block_values}} = assigns) do
    ~H"""
    <span class="assistant-change-title">{gettext("Change settings of %{block}", block: @change.block)}</span>
    <dl class="assistant-fields">
      <div :for={media <- @change.context}>
        <dt>{humanize(media.ref)}</dt>
        <dd class="assistant-inline-media"><.thumb media={@media} kind={media.kind} id={media.id} /></dd>
      </div>
      <div :for={value <- @change.values}>
        <dt>{value.label || humanize(value.name)}</dt>
        <dd>
          <del :if={value.before not in [nil, ""] and value.before != value.value}>{to_string(value.before)}</del>
          <span :if={value.media} class="assistant-inline-media">
            <.thumb media={@media} kind={value.media.kind} id={value.media.id} />
          </span>
          <ins :if={value.value not in [nil, ""]}>{to_string(value.value)}</ins>
        </dd>
      </div>
    </dl>
    """
  end

  defp change(%{change: %{type: :order}} = assigns) do
    ~H"""
    <span class="assistant-change-title">
      {if @change.parent,
        do: gettext("New order in %{block}", block: @change.parent),
        else: gettext("New order of the blocks")}
    </span>
    <ol class="assistant-order">
      <li :for={item <- @change.items} class={[item.moved? && "is-moved", item.new? && "is-new"]}>
        <span :if={item.media != []} class="assistant-inline-media">
          <.thumb media={@media} kind={hd(item.media).kind} id={hd(item.media).id} />
        </span>
        <span class="assistant-order-name">
          <strong>{item.name}</strong> <span :if={item.excerpt}>{item.excerpt}</span>
        </span>
        <span :for={value <- item.values} class={["assistant-order-value", value.changed? && "is-changed"]}>
          {value.label}: {to_string(value.value)}
        </span>
        <span :if={item.copy?} class="assistant-order-mark">{gettext("Copy")}</span>
        <span :if={item.new? and !item.copy?} class="assistant-order-mark">{gettext("New")}</span>
        <span :if={item.moved? and !item.new?} class="assistant-order-mark">{gettext("Moved")}</span>
      </li>
    </ol>
    """
  end

  defp change(%{change: %{type: type}} = assigns) when type in [:ref_config, :block_details] do
    ~H"""
    <span class="assistant-change-title">
      {if @change.type == :ref_config,
        do: gettext("Change %{ref} settings in %{block}", ref: humanize(@change.ref), block: @change.block),
        else: gettext("Change the details of %{block}", block: @change.block)}
    </span>
    <dl class="assistant-fields">
      <div :for={media <- @change[:context] || []}>
        <dt>{humanize(media.ref)}</dt>
        <dd class="assistant-inline-media"><.thumb media={@media} kind={media.kind} id={media.id} /></dd>
      </div>
      <div :for={setting <- @change.settings}>
        <dt>{humanize(setting.name)}</dt>
        <dd>
          <del :if={setting.before not in [nil, ""] and to_string(setting.before) != to_string(setting.value)}>
            {to_string(setting.before)}
          </del>
          <ins>{if setting.value == "", do: gettext("(cleared)"), else: to_string(setting.value)}</ins>
        </dd>
      </div>
    </dl>
    """
  end

  defp change(%{change: %{type: :block_table}} = assigns) do
    ~H"""
    <span class="assistant-change-title">{gettext("Replace the table in %{block}", block: @change.block)}</span>
    <p :if={@change.before} class="assistant-placement">
      {ngettext("It has %{count} row now.", "It has %{count} rows now.", @change.before)}
    </p>
    <ol class="assistant-order">
      <li :for={row <- @change.rows}><span class="assistant-order-name">{row}</span></li>
    </ol>
    """
  end

  defp change(%{change: %{type: :block_selection}} = assigns) do
    ~H"""
    <span class="assistant-change-title">{gettext("Choose the entries shown in %{block}", block: @change.block)}</span>
    <dl class="assistant-fields">
      <div :if={@change.before not in [nil, []]}>
        <dt>{gettext("Now")}</dt>
        <dd><del>{Enum.join(@change.before, ", ")}</del></dd>
      </div>
      <div>
        <dt>{gettext("Proposed")}</dt>
        <dd><ins>{Enum.join(@change.entries, ", ")}</ins></dd>
      </div>
    </dl>
    """
  end

  defp change(%{change: %{type: :copy_out}} = assigns) do
    ~H"""
    <span class="assistant-change-title">
      {gettext("Copy %{block} to %{entry}", block: @change.block, entry: @change.destination)}
    </span>
    <p class="assistant-placement">{gettext("The original stays here.")}</p>
    """
  end

  defp change(%{change: %{type: :block_active}} = assigns) do
    ~H"""
    <span class={["assistant-change-title", !@change.active && "is-removal"]}>
      {cond do
        @change.ref && @change.active ->
          gettext("Turn on %{ref} in %{block}", ref: humanize(@change.ref), block: @change.block)

        @change.ref ->
          gettext("Turn off %{ref} in %{block}", ref: humanize(@change.ref), block: @change.block)

        @change.active ->
          gettext("Turn on %{block}", block: @change.block)

        true ->
          gettext("Turn off %{block}", block: @change.block)
      end}
    </span>
    <p class="assistant-placement">
      {if @change.active,
        do: gettext("It is shown on the page again."),
        else: gettext("It is kept, but not shown on the page.")}
    </p>
    <dl :if={@change.context != []} class="assistant-fields">
      <div :for={media <- @change.context}>
        <dt>{humanize(media.ref)}</dt>
        <dd class="assistant-inline-media"><.thumb media={@media} kind={media.kind} id={media.id} /></dd>
      </div>
    </dl>
    """
  end

  defp change(%{change: %{type: :delete_block}} = assigns) do
    ~H"""
    <span class="assistant-change-title is-removal">{gettext("Remove %{block}", block: @change.block)}</span>
    <p :if={@change.children > 0} class="assistant-placement">
      {ngettext("Its %{count} nested block is removed too.", "Its %{count} nested blocks are removed too.", @change.children)}
    </p>
    <dl :if={@change.context != []} class="assistant-fields">
      <div :for={media <- @change.context}>
        <dt>{humanize(media.ref)}</dt>
        <dd class="assistant-inline-media"><.thumb media={@media} kind={media.kind} id={media.id} /></dd>
      </div>
    </dl>
    """
  end

  ## Events

  def handle_event("draft", %{"message" => text}, socket), do: {:noreply, assign(socket, :draft, text)}

  def handle_event("suggest", %{"text" => text}, socket),
    do: {:noreply, socket |> assign(:draft, text) |> push_event("b:assistant:fill", %{text: text})}

  def handle_event("send", %{"message" => text}, socket) do
    user = socket.assigns.current_user

    with {:ok, conversation} <- ensure_conversation(socket),
         {:ok, run} <-
           Agent.send_message(conversation.id, text, user, sandbox: self()) do
      socket =
        if socket.assigns.conversation,
          do: socket,
          else: push_patch(socket, to: "/admin/assistant/#{conversation.id}")

      {:noreply,
       socket
       |> assign(conversation: reload(conversation, user), run: run, draft: "", progress: gettext("Thinking"))
       |> assign_messages()
       |> push_event("b:assistant:clear", %{})}
    else
      {:error, message} -> {:noreply, put_toast(socket, :error, message)}
    end
  end

  def handle_event("cancel_run", _, socket) do
    if conversation = socket.assigns.conversation,
      do: Agent.cancel(conversation.id, socket.assigns.current_user)

    {:noreply, assign(socket, :progress, nil)}
  end

  def handle_event("toggle_history", _, socket),
    do: {:noreply, socket |> update(:show_history, &(!&1)) |> assign_conversations()}

  def handle_event("apply", %{"id" => id, "version" => version}, socket) do
    user = socket.assigns.current_user
    version = String.to_integer(version)
    socket = assign(socket, applying: true, error: nil)

    # The click is the approval: it approves exactly the version on screen,
    # then applies that version.
    with {:ok, _} <- Proposals.approve(id, version, user),
         {:ok, receipt} <-
           Proposals.apply(id, version, user, publish: publishing(socket.assigns)) do
      {:noreply,
       socket
       |> assign(applying: false, receipt: receipt)
       |> discard_previews()
       |> assign(:preview, nil)
       |> assign_proposal()
       |> put_toast(:info, gettext("Changes applied"))}
    else
      {:error, message} -> {:noreply, socket |> assign(applying: false, error: message) |> assign_proposal()}
    end
  end

  def handle_event("leave_out", %{"operations" => indices, "subject" => subject}, socket) do
    %{proposal: proposal, conversation: conversation, current_user: user} = socket.assigns
    indices = indices |> String.split(",", trim: true) |> Enum.map(&String.to_integer/1)

    case Proposals.leave_out(proposal.id, proposal.version, indices, user) do
      {:ok, refined} ->
        conversation |> Ecto.Changeset.change(proposal_id: refined.id) |> Brando.Repo.update!()
        Agent.note(conversation.id, gettext("Left out of the proposal: %{change}", change: subject), user)

        {:noreply,
         socket
         |> assign(:conversation, reload(conversation, user))
         |> discard_previews()
         |> assign(:preview, nil)
         |> assign_proposal()
         |> assign_messages()}

      {:error, message} ->
        {:noreply, put_toast(socket, :error, message)}
    end
  end

  def handle_event("toggle_publish", %{"key" => key}, socket) do
    publish = socket.assigns.publish
    publish = if MapSet.member?(publish, key), do: MapSet.delete(publish, key), else: MapSet.put(publish, key)
    {:noreply, assign(socket, :publish, publish)}
  end

  def handle_event("undo", _, socket) do
    %{proposal: proposal, current_user: user} = socket.assigns

    case Proposals.undo(proposal.id, user) do
      {:ok, _receipt} ->
        {:noreply, socket |> assign_proposal() |> put_toast(:info, gettext("The proposal is undone"))}

      {:error, message} ->
        {:noreply, assign(socket, :error, message)}
    end
  end

  # With several entries, the editor first chooses which ones the link shows.
  def handle_event("share_review", %{"keys" => keys}, socket) when is_list(keys) and keys != [] do
    all = Enum.map(socket.assigns.review, & &1.key)
    keys = Enum.filter(all, &(&1 in keys))
    token = Proposals.share_token(socket.assigns.proposal, if(keys == all, do: nil, else: keys))

    {:noreply,
     assign(socket, share_choice: nil, review_link: Brando.endpoint().url() <> "/admin/assistant/shared/" <> token)}
  end

  def handle_event("share_review", %{"keys" => _}, socket), do: {:noreply, socket}

  def handle_event("share_review", _, socket) do
    case socket.assigns.review do
      [_, _ | _] = review -> {:noreply, assign(socket, :share_choice, Enum.map(review, & &1.key))}
      _ -> handle_event("share_review", %{"keys" => Enum.map(socket.assigns.review, & &1.key)}, socket)
    end
  end

  def handle_event("cancel_share", _, socket), do: {:noreply, assign(socket, :share_choice, nil)}

  def handle_event("share_page", _, socket) do
    %{proposal: proposal, preview: preview, current_user: user} = socket.assigns
    {target, _} = Enum.find(proposal.targets, fn {target, _} -> Proposals.Proposal.key(target) == preview.key end)

    case Proposals.Preview.share(proposal, target, user, preview_target: preview.target, shared: !!socket.assigns.shared) do
      {:ok, url, days} ->
        {:noreply, assign(socket, :share_url, %{url: url, days: days})}

      {:error, :forbidden} ->
        {:noreply, put_toast(socket, :error, gettext("You do not have permission to share pages."))}

      {:error, reason} ->
        {:noreply, put_toast(socket, :error, to_string(reason))}
    end
  end

  def handle_event("cancel_proposal", _, socket) do
    if proposal = socket.assigns.proposal,
      do: Proposals.cancel(proposal.id, socket.assigns.current_user)

    {:noreply, assign_proposal(socket)}
  end

  def handle_event("preview", %{"key" => key}, socket) do
    preview = socket.assigns.preview || %{version: "proposed", viewport: "desktop", show: true, target: nil}
    # A named view belongs to one content type; another entry starts on its default.
    preview = if preview[:key] == key, do: preview, else: %{preview | target: nil}
    socket = if socket.assigns.preview, do: socket, else: push_event(socket, "b:assistant:review_top", %{})
    {:noreply, render_preview(socket, Map.put(preview, :key, key))}
  end

  def handle_event("preview_version", %{"version" => version}, socket) when version in ~w(before proposed),
    do: {:noreply, render_preview(socket, %{socket.assigns.preview | version: version})}

  def handle_event("preview_target", %{"target" => target}, socket),
    do: {:noreply, render_preview(socket, %{socket.assigns.preview | target: target})}

  def handle_event("preview_viewport", %{"viewport" => viewport}, socket) when viewport in ~w(desktop mobile),
    do: {:noreply, update(socket, :preview, &%{&1 | viewport: viewport})}

  def handle_event("toggle_highlight", _, socket), do: {:noreply, update(socket, :preview, &%{&1 | show: !&1.show})}
  def handle_event("close_preview", _, socket), do: {:noreply, socket |> discard_previews() |> assign(:preview, nil)}

  # The pickers browse the whole library; choosing an item attaches it, and
  # choosing it again detaches it.
  def handle_event("browse_library", %{"kind" => kind}, socket) when kind in ~w(image video) do
    ids = attached_ids(socket.assigns.conversation, kind)

    case kind do
      "image" ->
        send_update(ImagePicker,
          id: "image-picker",
          config_target: :all,
          event_target: nil,
          multi: true,
          selected_images: ids
        )

      "video" ->
        send_update(VideoPicker,
          id: "video-picker",
          config_target: :all,
          event_target: nil,
          multi: true,
          selected_videos: ids
        )
    end

    {:noreply, socket}
  end

  def handle_event("select_image", %{"id" => id}, socket), do: toggle_attachment(socket, "image", id)
  def handle_event("select_video", %{"id" => id}, socket), do: toggle_attachment(socket, "video", id)

  def handle_event("detach", %{"alias" => alias}, socket) do
    if conversation = socket.assigns.conversation,
      do: Agent.detach(conversation.id, alias, socket.assigns.current_user)

    {:noreply, refresh_conversation(socket)}
  end

  ## Agent and upload events

  def handle_info({:agent, _id, {:progress, text}}, socket), do: {:noreply, assign(socket, :progress, text)}
  def handle_info({:agent, _id, {:message, _}}, socket), do: {:noreply, assign_messages(socket)}

  def handle_info({:agent, _id, {:proposal, _}}, socket) do
    socket = socket |> refresh_conversation() |> assign_proposal()
    {:noreply, if(preview = socket.assigns.preview, do: render_preview(socket, preview), else: socket)}
  end

  def handle_info({:agent, _id, {:attachments, _}}, socket), do: {:noreply, refresh_conversation(socket)}

  def handle_info({:agent, _id, {:run, run}}, socket) do
    socket = assign(socket, :run, run)
    {:noreply, if(running?(run), do: socket, else: assign(socket, :progress, nil))}
  end

  def handle_info({:assets_reserved, %{"kind" => "ai_conversation"}, uploads}, socket) do
    with {:ok, conversation} <- ensure_conversation(socket),
         {:ok, _} <- Agent.reserve(conversation.id, uploads, socket.assigns.current_user) do
      socket =
        if socket.assigns.conversation,
          do: socket,
          else: push_patch(socket, to: "/admin/assistant/#{conversation.id}")

      {:noreply, socket |> assign(:conversation, conversation) |> refresh_conversation()}
    else
      {:error, message} -> {:noreply, put_toast(socket, :error, message)}
    end
  end

  def handle_info({:asset_ready, %{"kind" => "ai_conversation", "upload_ref" => ref}, asset}, socket) do
    if conversation = socket.assigns.conversation do
      case Agent.fulfil(conversation.id, ref, asset, socket.assigns.current_user) do
        {:ok, _} -> {:noreply, refresh_conversation(socket)}
        {:error, message} -> {:noreply, put_toast(socket, :error, message)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  ## Page preview

  # Renders the chosen entry of the proposal on screen through the site's own
  # preview target. Only the latest frame's cache key is kept.
  defp render_preview(%{assigns: %{proposal: nil}} = socket, _preview), do: assign(socket, :preview, nil)

  defp render_preview(%{assigns: %{shared: %{keys: [_ | _] = keys}}} = socket, preview) do
    if preview.key in keys, do: preview!(socket, preview), else: assign(socket, :preview, nil)
  end

  defp render_preview(socket, preview), do: preview!(socket, preview)

  defp preview!(socket, preview) do
    socket = discard_previews(socket)

    case Enum.find(socket.assigns.proposal.targets, fn {target, _} -> Proposals.Proposal.key(target) == preview.key end) do
      nil ->
        assign(socket, :preview, nil)

      {target, _} ->
        version = String.to_existing_atom(preview.version)

        frame =
          case Proposals.Preview.render(socket.assigns.proposal, target, socket.assigns.current_user,
                 version: version,
                 preview_target: preview.target,
                 shared: !!socket.assigns.shared
               ) do
            {:ok, %{key: key}} -> {:ok, key}
            {:error, reason} when reason in [:not_created, :no_preview_target] -> reason
            {:error, message} -> {:error, to_string(message)}
          end

        keys =
          case frame do
            {:ok, key} -> [key]
            _ -> []
          end

        assign(socket, preview: Map.put(preview, :frame, frame), preview_keys: keys)
    end
  end

  defp discard_previews(socket) do
    Proposals.Preview.discard(socket.assigns.preview_keys)
    assign(socket, :preview_keys, [])
  end

  def terminate(_reason, socket) do
    Proposals.Preview.discard(socket.assigns[:preview_keys] || [])
    :ok
  end

  # A card leads with media only when it places new content: a new entry or
  # new blocks. For other changes the media belong to one change among many.
  defp adds_content?(entry), do: Enum.all?(entry.changes, &(&1.type in [:create, :insert_block, :fields]))

  # What a change is about, for the note left in the conversation.
  defp change_subject(%{type: :fields}), do: gettext("the entry's fields")
  defp change_subject(%{block: block}) when is_binary(block), do: block
  defp change_subject(%{module: module}) when is_binary(module), do: gettext("a new %{module} block", module: module)
  defp change_subject(_change), do: gettext("a change")

  # Media titles may be translated: the admin's language, English, or any.
  defp plain(%{} = text),
    do: text[Gettext.get_locale(Brando.Gettext)] || text["en"] || text |> Map.values() |> List.first()

  defp plain(text), do: text

  defp receipt_badge(item, receipt) do
    cond do
      item.key in (receipt.mappings["published"] || []) -> gettext("Published")
      item.action == :create -> gettext("Created as draft")
      true -> gettext("Updated")
    end
  end

  # New entries and drafts can be published as the proposal is applied.
  defp publishable?(entry), do: entry.action == :create or entry.status == "draft"

  # Entries still holding placeholders stay drafts, whatever was ticked.
  defp publishing(%{publish: publish, review: review}) do
    unfinished = for %{placeholders: [_ | _], key: key} <- review || [], do: key
    publish |> MapSet.to_list() |> Enum.reject(&(&1 in unfinished))
  end

  defp language_state(:changed), do: gettext("changed in this proposal too")
  defp language_state(:follows), do: gettext("follows when applied, with text to translate")
  defp language_state(:unchanged), do: gettext("not changed")

  defp thumb_icon(kind) do
    case to_string(kind) do
      "video" -> "hero-film"
      "file" -> "hero-document"
      _ -> "hero-photo"
    end
  end

  defp frame_url(nil), do: nil
  defp frame_url(%{url: "/" <> _ = path}), do: String.replace(Brando.endpoint().url(), ~r{^https?://}, "") <> path
  defp frame_url(%{url: url}) when is_binary(url), do: String.replace(url, ~r{^https?://}, "")
  defp frame_url(%{title: title}), do: gettext("%{title} (no address yet)", title: title)

  defp default_target(%{preview_targets: targets}) do
    if Enum.any?(targets, &(elem(&1, 0) == "default")), do: "default", else: targets |> List.first({nil, nil}) |> elem(0)
  end

  defp tab_summary(%{action: :create}), do: gettext("New entry")

  defp tab_summary(entry) do
    blocks = Enum.count(entry.changes, &(&1.type == :insert_block))

    if blocks > 0,
      do: ngettext("%{count} block added", "%{count} blocks added", blocks),
      else: ngettext("%{count} change", "%{count} changes", length(entry.changes))
  end

  ## Data

  defp ensure_conversation(%{assigns: %{conversation: %{} = conversation}}), do: {:ok, conversation}

  defp ensure_conversation(socket) do
    user = socket.assigns.current_user

    opts =
      if target = socket.assigns.target,
        do: [target: Map.take(target, ~w(content_type id field))],
        else: [language: socket.assigns[:content_language]]

    with {:ok, conversation} <- Agent.start_conversation(user, opts) do
      if connected?(socket), do: Agent.subscribe(conversation.id)
      {:ok, conversation}
    end
  end

  defp reload(conversation, user) do
    case Agent.get_conversation(conversation.id, user) do
      {:ok, conversation} -> conversation
      _ -> conversation
    end
  end

  defp refresh_conversation(%{assigns: %{conversation: nil}} = socket), do: socket

  defp refresh_conversation(socket) do
    socket
    |> assign(:conversation, reload(socket.assigns.conversation, socket.assigns.current_user))
    |> assign_media()
  end

  # The guidance the assistant follows here: for the conversation, or for the
  # entry a new conversation will be opened for.
  defp assign_guidance(socket) do
    conversation =
      socket.assigns.conversation ||
        %Agent.Conversation{scope: Brando.Content.Transfer.scope(), target: socket.assigns.target}

    assign(socket, :guidance, Agent.Guidance.for_conversation(conversation))
  end

  defp assign_conversations(socket),
    do: assign(socket, :conversations, Agent.list_conversations(socket.assigns.current_user))

  defp assign_messages(%{assigns: %{conversation: nil}} = socket),
    do: assign(socket, messages: [], turns: [], cost: nil)

  # The turns are built once per update: step labels read the stored tool
  # results. The cost follows each model call, which each new message marks.
  defp assign_messages(socket) do
    %{conversation: conversation, current_user: user} = socket.assigns
    messages = Agent.messages(conversation.id, user)
    cost = if Agent.config()[:show_cost], do: Agent.cost(conversation.id, user)
    socket |> assign(messages: messages, turns: turns(messages), cost: cost) |> assign_media()
  end

  defp assign_proposal(%{assigns: %{conversation: %{proposal_id: id}}} = socket) when is_binary(id) do
    user = socket.assigns.current_user

    case Proposals.get(id, user) do
      {:ok, proposal} ->
        receipt = if proposal.status == "applied", do: Proposals.receipt(proposal.id, user)
        review = proposal |> Review.entries() |> with_saved_urls(receipt)

        socket
        |> assign(proposal: proposal, review: review, receipt: receipt)
        |> assign_media()

      {:error, message} ->
        assign(socket, proposal: nil, review: [], error: message)
    end
  end

  defp assign_proposal(socket), do: socket |> assign(proposal: nil, review: []) |> assign_media()

  # After apply, link each card to the entry it produced, including new ones.
  defp with_saved_urls(review, nil), do: review

  defp with_saved_urls(review, receipt) do
    Enum.map(review, fn entry ->
      case receipt.after[entry.key] do
        %{"schema" => schema, "id" => id} ->
          url =
            case Brando.Content.Proposals.Codec.schema(schema) do
              {:ok, module} -> admin_url(module, id)
              :error -> nil
            end

          Map.put(entry, :saved_url, url)

        _ ->
          entry
      end
    end)
  end

  defp admin_url(schema, id) do
    schema.__admin_route__(:update, [id])
  rescue
    _ -> nil
  end

  # Thumbnails for attachments and for media placed by the proposal, loaded
  # in one query per kind.
  defp assign_media(socket) do
    attachments = (socket.assigns.conversation && socket.assigns.conversation.attachments) || []

    suggested =
      for %{role: "request", kind: kind, suggested: ids} <- socket.assigns[:turns] || [],
          id <- ids,
          do: {to_kind(kind), id}

    refs =
      Enum.flat_map(attachments, &if(&1["id"], do: [{to_kind(&1["kind"]), &1["id"]}], else: [])) ++
        Review.media(socket.assigns.review) ++ suggested

    assign(socket, :media, load_media(Enum.uniq(refs)))
  end

  defp load_media(refs) do
    image_ids = for {:image, id} <- refs, do: id
    video_ids = for {:video, id} <- refs, do: id
    file_ids = for {:file, id} <- refs, do: id

    images =
      if image_ids == [],
        do: [],
        else: Repo.all(from(i in Brando.Images.Image, where: i.id in ^image_ids))

    videos =
      if video_ids == [],
        do: [],
        else: Repo.all(from(v in Brando.Videos.Video, where: v.id in ^video_ids, preload: [:thumbnail]))

    files =
      if file_ids == [],
        do: [],
        else: Repo.all(from(f in Brando.Files.File, where: f.id in ^file_ids))

    Map.new(
      Enum.map(images, &{{:image, &1.id}, %{url: image_url(&1), label: plain(&1.title)}}) ++
        Enum.map(videos, &{{:video, &1.id}, %{url: video_url(&1), label: plain(&1.title)}}) ++
        Enum.map(files, &{{:file, &1.id}, %{url: nil, label: plain(&1.title) || &1.filename}})
    )
  end

  defp attach(socket, kind, id) do
    user = socket.assigns.current_user

    with {:ok, conversation} <- ensure_conversation(socket),
         {:ok, _alias} <- Agent.attach(conversation.id, {String.to_existing_atom(kind), id}, user) do
      socket =
        if socket.assigns.conversation,
          do: socket,
          else: push_patch(socket, to: "/admin/assistant/#{conversation.id}")

      socket |> assign(:conversation, reload(conversation, user)) |> assign_media()
    else
      {:error, message} -> put_toast(socket, :error, message)
    end
  end

  defp toggle_attachment(socket, kind, id) do
    id = if is_integer(id), do: id, else: String.to_integer(id)
    conversation = socket.assigns.conversation

    socket =
      case conversation && Enum.find(conversation.attachments, &(&1["kind"] == kind and &1["id"] == id)) do
        %{"alias" => alias} ->
          Agent.detach(conversation.id, alias, socket.assigns.current_user)
          refresh_conversation(socket)

        _ ->
          attach(socket, kind, id)
      end

    ids = attached_ids(socket.assigns.conversation, kind)

    case kind do
      "image" -> send_update(ImagePicker, id: "image-picker", selected_images: ids)
      "video" -> send_update(VideoPicker, id: "video-picker", selected_videos: ids)
    end

    {:noreply, socket}
  end

  defp attached_ids(nil, _kind), do: []

  defp attached_ids(conversation, kind),
    do: for(%{"kind" => ^kind, "id" => id} <- conversation.attachments || [], do: id)

  # The model's reply is Markdown. It is not trusted like an editor's text, so
  # raw HTML is left out.
  defp markdown(nil), do: ""
  defp markdown(text), do: text |> Brando.Markdown.to_html!(breaks: true, safe: true) |> Phoenix.HTML.raw()

  # A fresh upload has no sizes until processing finishes; show the original.
  defp image_url(image) do
    size = if Map.has_key?(image.sizes || %{}, "thumb"), do: :thumb, else: :original
    Brando.Utils.img_url(image, size, prefix: Brando.Utils.media_url())
  rescue
    _ -> nil
  end

  defp video_url(%{thumbnail: %Brando.Images.Image{} = thumbnail}), do: image_url(thumbnail)
  defp video_url(_), do: nil

  ## Helpers

  # Tool calls and their results collapse into one list of steps between the
  # user's message and the assistant's answer.
  # Results that make a step's label specific: what was read, which version.
  @labelled_results ~w(entry_outline prepare_proposal attach_folder request_media look_at_media)

  defp turns(messages) do
    results =
      for %{role: "tool", tool_name: name, tool_call_id: id, content: content} <- messages,
          name in @labelled_results,
          {:ok, %{} = result} <- [Jason.decode(content || "")],
          into: %{},
          do: {id, result}

    messages
    |> Enum.reduce([], fn
      %{role: "tool"}, acc ->
        acc

      %{role: "assistant", tool_calls: [_ | _] = calls} = message, acc ->
        {requests, calls} = Enum.split_with(calls, &(&1["name"] == "request_media"))
        steps = Enum.map(calls, &step_label(&1, results[&1["id"]] || %{}))
        acc = if message.content not in [nil, ""], do: [%{role: "assistant", content: message.content} | acc], else: acc

        acc =
          case {steps, acc} do
            {[], acc} -> acc
            {steps, [%{role: "steps", steps: previous} | rest]} -> [%{role: "steps", steps: previous ++ steps} | rest]
            {steps, acc} -> [%{role: "steps", steps: steps} | acc]
          end

        Enum.reduce(requests, acc, &[media_request(&1, results[&1["id"]] || %{}) | &2])

      message, acc ->
        [%{role: message.role, content: message.content} | acc]
    end)
    |> Enum.reverse()
    |> mark_open_request()
  end

  # The assistant's request for media, with the library suggestions it was
  # made with.
  defp media_request(%{"arguments" => arguments}, result) do
    args =
      case Jason.decode(arguments || "{}") do
        {:ok, %{} = args} -> args
        _ -> %{}
      end

    %{
      role: "request",
      kind: if(args["kind"] == "video", do: "video", else: "image"),
      reason: args["reason"],
      count: args["count"],
      suggested: result["suggested"] || [],
      open?: false
    }
  end

  # Only the latest request, with no message from the editor after it, can be
  # answered from its card.
  defp mark_open_request(turns) do
    case turns |> Enum.with_index() |> Enum.filter(&(elem(&1, 0).role in ["request", "user"])) |> List.last() do
      {%{role: "request"} = request, index} -> List.replace_at(turns, index, %{request | open?: true})
      _ -> turns
    end
  end

  defp step_label(%{"name" => name, "arguments" => arguments}, result) do
    args =
      case Jason.decode(arguments || "{}") do
        {:ok, %{} = args} -> args
        _ -> %{}
      end

    label = step_text(name, args, result)
    if result["error"], do: gettext("%{step} (did not work)", step: label), else: label
  end

  defp step_text("search_entries", args, _), do: gettext("Searched for “%{query}”", query: args["query"])

  defp step_text("entry_outline", _args, %{"title" => title}) when is_binary(title),
    do: gettext("Read “%{title}”", title: title)

  defp step_text("entry_outline", _args, _), do: gettext("Read an entry")
  defp step_text("list_content_types", _, _), do: gettext("Looked at the content types")

  defp step_text("describe_content_type", args, _),
    do: gettext("Checked the fields of %{type}", type: content_type_label(args["content_type"]))

  defp step_text("list_modules", args, _),
    do: gettext("Looked at the modules for %{type}", type: content_type_label(args["content_type"]))

  defp step_text("describe_module", args, _) do
    case module_name(args["module"]) do
      nil -> gettext("Checked a module's slots")
      name -> gettext("Checked the module “%{module}”", module: name)
    end
  end

  defp step_text("list_attachments", _, _), do: gettext("Matched the attached media")
  defp step_text("list_selection_options", _, _), do: gettext("Looked at the entries a block can show")
  defp step_text("list_entry_media", _, _), do: gettext("Looked at an entry's media")

  defp step_text("look_at_media", _, %{"media" => media}) when is_list(media),
    do: ngettext("Looked at %{count} picture", "Looked at %{count} pictures", length(media))

  defp step_text("look_at_media", _, _), do: gettext("Looked at pictures")

  defp step_text("search_assets", %{"query" => query}, _) when query not in [nil, ""],
    do: gettext("Searched the media library for “%{query}”", query: query)

  defp step_text("search_assets", _, _), do: gettext("Searched the media library")

  defp step_text("find_media_folders", %{"name" => name}, _) when is_binary(name),
    do: gettext("Looked for the folder “%{name}”", name: name)

  defp step_text("find_media_folders", _, _), do: gettext("Looked for the folder")

  defp step_text("attach_folder", _, %{"folder" => %{"path" => path}, "attached" => attached}) when is_list(attached),
    do:
      ngettext("Attached %{count} item from %{folder}", "Attached %{count} items from %{folder}", length(attached),
        folder: path
      )

  defp step_text("attach_folder", _, _), do: gettext("Attached the folder's media")

  defp step_text("prepare_proposal", _, %{"version" => version, "applicable" => false}),
    do: gettext("Prepared version %{version}, with problems to fix", version: version)

  defp step_text("prepare_proposal", _, %{"version" => version}),
    do: gettext("Prepared version %{version} of the proposal", version: version)

  defp step_text("prepare_proposal", _, _), do: gettext("Prepared the proposal")
  defp step_text(_, _, _), do: gettext("Looked at the site's content")

  defp content_type_label(name) do
    case Brando.Content.Proposals.Codec.schema(name) do
      {:ok, schema} -> Brando.Blueprint.get_singular(schema)
      :error -> name
    end
  end

  defp module_name(reference) do
    {origin, id} = Brando.Content.SharedLibrary.reference(reference)

    case Brando.Content.fetch_module(id, origin) do
      %{name: %{} = name} ->
        name[Gettext.get_locale(Brando.Gettext)] || name["en"] || name |> Map.values() |> List.first()

      %{name: name} ->
        name

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  # USD with cents; tiny amounts are not rounded to nothing.
  defp format_cost(cost) when cost < 0.01, do: "< $0.01"
  defp format_cost(cost), do: "$" <> :erlang.float_to_binary(cost, decimals: 2)

  defp language_label(code) when is_binary(code) do
    case Enum.find(Brando.config(:languages) || [], &(to_string(&1[:value]) == code)) do
      nil -> String.upcase(code)
      language -> Brando.Content.Transfer.Labels.language(code, language[:text])
    end
  end

  defp language_label(conversation),
    do: language_label(to_string((conversation && conversation.language) || Brando.config(:default_language)))

  defp put_toast(socket, level, message) do
    BrandoAdmin.Toast.send_to(socket.assigns.current_user, message, %{
      level: if(level == :error, do: :error, else: :success),
      type: :notification
    })

    socket
  end

  defp running?(%{status: "running"}), do: true
  defp running?(_), do: false

  defp proposal_title(%{status: "undone"}, _receipt), do: gettext("Undone")
  defp proposal_title(_proposal, receipt) when not is_nil(receipt), do: gettext("Applied")

  defp proposal_title(proposal, _receipt) do
    cond do
      proposal.status == "cancelled" -> gettext("Discarded")
      proposal.status == "superseded" -> gettext("Replaced by a newer version")
      proposal.problems != [] -> gettext("Needs changes")
      true -> gettext("Ready for your review")
    end
  end

  defp counts(effects) do
    [
      {effects[:creates] || 0, ngettext("new entry", "new entries", effects[:creates] || 0)},
      {effects[:updates] || 0, ngettext("updated entry", "updated entries", effects[:updates] || 0)},
      {effects[:inserted_blocks] || 0, ngettext("new block", "new blocks", effects[:inserted_blocks] || 0)},
      {effects[:updated_blocks] || 0, ngettext("changed block", "changed blocks", effects[:updated_blocks] || 0)},
      {effects[:moved_blocks] || 0, ngettext("moved block", "moved blocks", effects[:moved_blocks] || 0)},
      {effects[:deletions] || 0, ngettext("deletion", "deletions", effects[:deletions] || 0)}
    ]
    # Deletions are always shown: "0 deletions" is a fact worth stating.
    |> Enum.with_index()
    |> Enum.filter(fn {{count, _}, index} -> count > 0 or index == 5 end)
    |> Enum.map(&elem(&1, 0))
  end

  defp entry_summary(effects) do
    [
      (effects[:creates] || 0) > 0 && ngettext("%{count} new entry", "%{count} new entries", effects[:creates]),
      (effects[:updates] || 0) > 0 && ngettext("%{count} updated entry", "%{count} updated entries", effects[:updates])
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  defp block_summary(effects) do
    [
      (effects[:inserted_blocks] || 0) > 0 &&
        ngettext("%{count} new block", "%{count} new blocks", effects[:inserted_blocks]),
      (effects[:updated_blocks] || 0) > 0 &&
        ngettext("%{count} changed block", "%{count} changed blocks", effects[:updated_blocks]),
      (effects[:moved_blocks] || 0) > 0 &&
        ngettext("%{count} moved block", "%{count} moved blocks", effects[:moved_blocks]),
      if((effects[:deletions] || 0) > 0,
        do: ngettext("%{count} deletion", "%{count} deletions", effects[:deletions]),
        else: gettext("no deletions")
      )
    ]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  # The media a proposal places, as `{kind, id}`.
  defp used_aliases(nil), do: nil

  defp used_aliases(proposal) do
    fields =
      for %Proposals.CreateEntry{fields: fields} <- proposal.operations,
          {name, id} <- fields,
          is_integer(id) and String.ends_with?(name, "image_id"),
          do: {:image, id}

    placed =
      for op <- proposal.operations,
          asset <- Map.values(Map.get(op, :media) || %{}) ++ List.wrap(Map.get(op, :asset)),
          do: asset

    MapSet.new(fields ++ placed)
  end

  defp used?(used, item), do: item["id"] && MapSet.member?(used, {to_kind(item["kind"]), item["id"]})

  defp attached_count(nil), do: 0
  defp attached_count(conversation), do: length(conversation.attachments)

  defp media_map({kind, id}), do: %{kind: kind, id: id}

  # The block editor labels the usual field "Blocks"; others by their name.
  defp field_label("blocks"), do: gettext("Blocks")
  defp field_label(field), do: humanize(field)

  defp humanize(name), do: name |> to_string() |> String.replace("_", " ") |> String.capitalize()

  defp apply_label(changes, 0), do: ngettext("Apply %{count} entry change", "Apply %{count} entry changes", changes)

  defp apply_label(changes, live) do
    ngettext("Apply %{count} entry change", "Apply %{count} entry changes", changes) <>
      " · " <> ngettext("affects %{count} live page", "affects %{count} live pages", live)
  end

  # Media the user attached is named by its alias and file; other library
  # media by kind and id.
  # An attachment by its alias, other media by its title.
  defp media_label(%{kind: kind, id: id}, aliases, loaded) do
    case {aliases[{to_kind(kind), id}], loaded[{to_kind(kind), id}]} do
      {%{"alias" => alias, "label" => label}, _} -> Enum.join(Enum.reject([alias, label], &(&1 in [nil, ""])), " · ")
      {_, %{label: label}} when label not in [nil, ""] -> label
      _ -> "#{kind} ##{id}"
    end
  end

  defp aliases(nil), do: %{}

  defp aliases(conversation) do
    for %{"id" => id} = attachment <- conversation.attachments, id, into: %{} do
      {{to_kind(attachment["kind"]), id}, attachment}
    end
  end

  defp to_kind(kind) when kind in [:image, "image"], do: :image
  defp to_kind(kind) when kind in [:video, "video"], do: :video
  defp to_kind(_), do: nil

  defp attached(aliases, kind), do: Enum.count(aliases, fn {{k, _}, _} -> k == to_kind(kind) end)

  defp topic(conversation_id), do: Brando.Tenant.Topic.scoped("brando:ai_agent:#{conversation_id}")

  defp scope_label(socket) do
    site = socket.assigns[:current_site]
    environment = socket.assigns[:current_environment]

    [site && (site.name || site.key), environment && (Map.get(environment, :name) || Map.get(environment, :key))]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" / ")
    |> case do
      "" -> Brando.config(:app_name) || gettext("Current site")
      label -> label
    end
  end
end
