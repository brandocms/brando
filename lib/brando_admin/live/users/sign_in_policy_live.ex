defmodule BrandoAdmin.Users.SignInPolicyLive do
  @moduledoc false
  # Who must use two-factor authentication: nobody, everyone, or the users of
  # some roles (with groups authorization, some groups). Users are shared by
  # every site, so the policy is the installation's. Superusers only.
  use BrandoAdmin, :live_view
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Users.SecurityLog
  alias Brando.Users.SecurityPolicy
  alias BrandoAdmin.Components.Workspace
  alias BrandoAdmin.Toast

  on_mount({BrandoAdmin.LiveView.Form, {:hooks_toast, __MODULE__}})

  def render(assigns) do
    ~H"""
    <div class="admin-workspace security-workspace">
      <Workspace.header
        eyebrow={gettext("Users")}
        title={gettext("Sign-in policy")}
        subtitle={gettext("Who must use two-factor authentication. Applies to every site in this installation.")}
        icon="shield"
      />

      <.form for={@form} id="sign-in-policy-form" phx-change="change" phx-submit="save">
        <section class="workspace-panel security-panel">
          <header class="workspace-panel-heading">
            <div>
              <h2>{gettext("Two-factor authentication")}</h2>
              <p>{gettext("Users it applies to set it up the next time they log in.")}</p>
            </div>
          </header>
          <fieldset class="security-choices">
            <legend class="workspace-sr-only">{gettext("Require two-factor authentication")}</legend>
            <label :for={{value, label, hint} <- @modes} class="security-choice">
              <input
                type="radio"
                name="policy[two_factor]"
                value={value}
                checked={to_string(@draft.two_factor) == value}
                data-testid={"policy-#{value}"}
              />
              <span>
                <span class="security-choice-label">{label}</span>
                <span class="security-choice-hint">{hint}</span>
              </span>
            </label>
          </fieldset>

          <fieldset :if={@draft.two_factor == :selected} class="security-choices security-choices-nested">
            <legend>{if @groups?, do: gettext("Groups"), else: gettext("Roles")}</legend>
            <input type="hidden" name={"policy[#{@selection_key}][]"} value="" />
            <label :for={{value, label} <- @options} class="security-choice compact">
              <input
                type="checkbox"
                name={"policy[#{@selection_key}][]"}
                value={value}
                checked={value in @selected}
                data-testid={"policy-option-#{value}"}
              />
              <span class="security-choice-label">{label}</span>
            </label>
          </fieldset>

          <div class="security-row security-policy-footer">
            <p class="security-policy-effect" data-testid="policy-effect">
              {effect(@draft, @affected)}
            </p>
            <div class="security-row-actions">
              <button type="submit" class="workspace-button primary" data-testid="policy-save" disabled={!@can_save?}>
                {gettext("Save policy")}
              </button>
            </div>
          </div>
          <p :if={@error} class="security-policy-error" role="alert">{@error}</p>
        </section>
      </.form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    if Brando.Users.superuser?(socket.assigns.current_user) do
      policy = SecurityPolicy.get()
      groups? = Brando.Authorization.enabled?()

      {:ok,
       socket
       |> assign(
         socket_connected: connected?(socket),
         policy: policy,
         groups?: groups?,
         selection_key: if(groups?, do: "two_factor_group_ids", else: "two_factor_roles"),
         options: options(groups?),
         modes: modes(),
         error: nil,
         meta: if(connected?(socket), do: SecurityLog.meta(connect_info(socket))),
         page_title: gettext("Sign-in policy")
       )
       |> assign_draft(policy)}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Only a superuser can change the sign-in policy."))
       |> push_navigate(to: "/admin/users")}
    end
  end

  defp connect_info(socket) do
    %{peer_data: get_connect_info(socket, :peer_data), user_agent: get_connect_info(socket, :user_agent)}
  end

  defp modes do
    [
      {"off", gettext("Not required"), gettext("Each user decides for themselves.")},
      {"everyone", gettext("Everyone"), gettext("Every user must use it.")},
      {"selected", gettext("Some users"), gettext("Users with the roles or in the groups you choose.")}
    ]
  end

  defp options(true) do
    from(g in Brando.Authorization.Group, order_by: [asc: g.scope_kind, asc: g.name], select: {g.id, g.name})
    |> Brando.Repo.all()
    |> Enum.map(fn {id, name} -> {to_string(id), name} end)
  end

  defp options(false) do
    Enum.map(SecurityPolicy.roles(), &{&1, Brando.Users.User.role_label(String.to_existing_atom(&1))})
  end

  defp assign_draft(socket, draft) do
    selected =
      if socket.assigns.groups?,
        do: Enum.map(draft.two_factor_group_ids, &to_string/1),
        else: draft.two_factor_roles

    assign(socket,
      draft: draft,
      selected: selected,
      affected: SecurityPolicy.without_two_factor_count(draft),
      can_save?: draft.two_factor != :selected or selected != [],
      form: to_form(%{}, as: "policy")
    )
  end

  def handle_event("change", %{"policy" => params}, socket) do
    changeset = SecurityPolicy.changeset(socket.assigns.draft, clean(params))
    {:noreply, socket |> assign(error: nil) |> assign_draft(Ecto.Changeset.apply_changes(changeset))}
  end

  def handle_event("save", %{"policy" => params}, socket) do
    %{current_user: user, meta: meta} = socket.assigns

    attrs =
      socket.assigns.draft
      |> Map.take([:two_factor, :two_factor_roles, :two_factor_group_ids])
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.merge(clean(params))

    case SecurityPolicy.update(attrs, user, meta: meta) do
      {:ok, policy} ->
        Toast.send_to(user, gettext("The sign-in policy was saved."))
        {:noreply, socket |> assign(policy: policy, error: nil) |> assign_draft(policy)}

      {:error, :enroll_first} ->
        {:noreply,
         assign(socket,
           error: gettext("The policy applies to you. Set up two-factor authentication on your Security page first.")
         )}

      {:error, _reason} ->
        {:noreply, assign(socket, error: gettext("The policy could not be saved."))}
    end
  end

  # The hidden empty value lets every box be unticked; a choice the form
  # does not show keeps what was chosen before.
  defp clean(params) do
    Enum.reduce(["two_factor_roles", "two_factor_group_ids"], params, fn key, params ->
      case params do
        %{^key => values} when is_list(values) -> Map.put(params, key, Enum.reject(values, &(&1 == "")))
        _ -> params
      end
    end)
  end

  defp effect(%{two_factor: :off}, _count), do: gettext("Nobody is required to use two-factor authentication.")

  defp effect(_draft, 0), do: gettext("Everyone this applies to already uses two-factor authentication.")

  defp effect(_draft, count) do
    ngettext(
      "One user this applies to has not set it up. They set it up at their next login, and their current sessions end when you save.",
      "%{count} users this applies to have not set it up. They set it up at their next login, and their current sessions end when you save.",
      count
    )
  end
end
