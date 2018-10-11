import Brando.Utils, only: [media_url: 0, img_url: 3]

defimpl Brando.Render, for: Brando.User do
  def r(data) do
    src =
      img_url(data.avatar, :micro,
        prefix: media_url(),
        default:
          Brando.helpers().static_path(
            Brando.endpoint(),
            "/images/brando/defaults/avatar_default.jpg"
          )
      )

    ~s(<img class="micro-avatar" src="#{src}" /> #{data.full_name})
  end
end
