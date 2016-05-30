defmodule <%= module %>Controller do
  use <%= base %>.Web, :controller
  alias <%= module %>

  def index(conn, _params) do
    <%= plural %> = Brando.repo.all(<%= alias %>)

    render conn, :index, [
      <%= plural %>: <%= plural %>,
      page_title: "<%= plural %>"
    ]
  end
end
