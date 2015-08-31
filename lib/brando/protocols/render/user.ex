import Brando.Utils, only: [media_url: 0]
import Brando.HTML, only: [img: 3]

defimpl Brando.Render, for: Brando.User do
  def r(data) do
    ~s(<img class="micro-avatar" src="#{img(data.avatar, :micro, [default: Brando.helpers.static_path(Brando.endpoint, "/images/brando/defaults/avatar_default.jpg"), prefix: media_url()])}" /> #{data.username})
  end
end