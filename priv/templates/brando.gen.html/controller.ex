defmodule <%= module %>Controller do
  use <%= base %>Web, :controller
  alias <%= base %>.<%= domain %>

  @doc false
  def index(conn, _params) do
    {:ok, <%= plural %>} = <%= domain %>.list_<%= plural %>()

    render conn, :index, [
      <%= plural %>: <%= plural %>,
      page_title: "<%= plural %>"
    ]
  end
end
