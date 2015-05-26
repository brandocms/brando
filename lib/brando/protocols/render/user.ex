import Brando.HTML, only: [media_url: 1, img: 3]

defimpl Brando.Render, for: Brando.User do
  def r(data) do
    ~s(<img class="micro-avatar" src="#{media_url(img(data.avatar, :micro, "defaults/avatar_default.jpg"))}" /> #{data.username})
  end
end