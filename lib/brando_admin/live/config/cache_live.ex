defmodule BrandoAdmin.Sites.CacheLive do
  use Surface.LiveView, layout: {BrandoAdmin.LayoutView, "live.html"}
  use BrandoAdmin.Presence
  use Phoenix.HTML

  import Brando.Gettext
  import Phoenix.LiveView.Helpers

  alias BrandoAdmin.Components.Content

  def mount(_, %{"user_token" => token}, socket) do
    if connected?(socket) do
      {:ok,
       socket
       |> Surface.init()
       |> assign(:socket_connected, true)
       |> assign_caches()
       |> assign_current_user(token)
       |> set_admin_locale()}
    else
      {:ok,
       socket
       |> Surface.init()
       |> assign(:socket_connected, false)}
    end
  end

  def render(%{socket_connected: false} = assigns) do
    ~F"""
    """
  end

  def render(assigns) do
    ~F"""
    <Content.Header
      title={gettext("Cache")}
      subtitle={gettext("Inspect and clear caches")} />

    <div class="cache-live">
      <p class="help">
        A cache is like a snapshot of your data that is accessed in memory to deliver content faster without rebuilding it from scratch every time. If you have changed some content and it is not reflected on the website, you can attempt to empty these caches in order to produce fresh data.
      </p>
      <table>
        {#for {category, entries} <- @caches}
          <h1>{category}</h1>
          <tr>
            <th>Type</th>
            <th>Module</th>
            <th>Cache key</th>
            <th>Entry ID</th>
          </tr>
          {#for entry <- entries}
            <tr>
              {#case entry}
                {#match {:list, module, key}}
                  <td>
                    <div class="badge">
                      List
                    </div>
                  </td>
                  <td>
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M2 5l7-3 6 3 6.303-2.701a.5.5 0 0 1 .697.46V19l-7 3-6-3-6.303 2.701a.5.5 0 0 1-.697-.46V5zm14 14.395l4-1.714V5.033l-4 1.714v12.648zm-2-.131V6.736l-4-2v12.528l4 2zm-6-2.011V4.605L4 6.319v12.648l4-1.714z"/></svg>
                    {module}
                  </td>
                  <td>
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M10.758 11.828l7.849-7.849 1.414 1.414-1.414 1.415 2.474 2.474-1.414 1.415-2.475-2.475-1.414 1.414 2.121 2.121-1.414 1.415-2.121-2.122-2.192 2.192a5.002 5.002 0 0 1-7.708 6.294 5 5 0 0 1 6.294-7.708zm-.637 6.293A3 3 0 1 0 5.88 13.88a3 3 0 0 0 4.242 4.242z"/></svg>
                    {key}
                  </td>
                  <td>N/A</td>

                {#match {:single, module, key, entry_id}}
                  <td>
                    <div class="badge">
                      Single
                    </div>
                  </td>
                  <td>
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M2 5l7-3 6 3 6.303-2.701a.5.5 0 0 1 .697.46V19l-7 3-6-3-6.303 2.701a.5.5 0 0 1-.697-.46V5zm14 14.395l4-1.714V5.033l-4 1.714v12.648zm-2-.131V6.736l-4-2v12.528l4 2zm-6-2.011V4.605L4 6.319v12.648l4-1.714z"/></svg>
                    {module}
                  </td>
                  <td>
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M10.758 11.828l7.849-7.849 1.414 1.414-1.414 1.415 2.474 2.474-1.414 1.415-2.475-2.475-1.414 1.414 2.121 2.121-1.414 1.415-2.121-2.122-2.192 2.192a5.002 5.002 0 0 1-7.708 6.294 5 5 0 0 1 6.294-7.708zm-.637 6.293A3 3 0 1 0 5.88 13.88a3 3 0 0 0 4.242 4.242z"/></svg>
                    {key}
                  </td>
                  <td>
                    #{entry_id}
                  </td>
              {/case}
            </tr>
          {/for}
        {/for}
      </table>

      <button type="button" class="primary" :on-click="empty_caches">
        Empty all caches
      </button>
    </div>
    """
  end

  def handle_params(params, url, socket) do
    uri = URI.parse(url)

    {:noreply,
     socket
     |> assign(:params, params)
     |> assign(:uri, uri)}
  end

  def handle_event("empty_caches", _, socket) do
    Cachex.clear(:query)
    send(self(), {:toast, gettext("Caches cleared!")})

    {:noreply, socket |> assign_caches()}
  end

  defp set_admin_locale(%{assigns: %{current_user: current_user}} = socket) do
    current_user.language
    |> to_string
    |> Gettext.put_locale()

    socket
  end

  defp assign_current_user(socket, token) do
    assign_new(socket, :current_user, fn ->
      Brando.Users.get_user_by_session_token(token)
    end)
  end

  defp assign_caches(socket) do
    {:ok, query_caches} = Cachex.keys(:query)
    assign(socket, :caches, %{query: query_caches})
  end
end
