defmodule Brando.Sites.FourOhFourTest do
  use ExUnit.Case, async: true

  alias Brando.Sites.FourOhFour

  test "scanner probes are recognised" do
    for url <- ~w(
          /wp-login.php /index.php /index.php~ /index.php.bak /index.php.txt /.index.php.swp
          /index%20copy.php /.env /.env.production /.git/config /.git/HEAD /.ssh/id_rsa
          /.aws/credentials /.htaccess /.npmrc /.svn/entries /config.json /config.yml
          /secrets.json /credentials.json /wp-content/plugins/x/composer.json
          /vendor/phpunit/phpunit/src/Util/PHP/eval-stdin.php /containers/json
        ) do
      assert FourOhFour.probe?(url), "expected #{url} to be a probe"
    end
  end

  test "moved pages, old uploads, broken assets and well-known paths are not" do
    for url <- ~w(
          /projects/lasse-flode /feed /ads.txt /sitemap.xml /apple-touch-icon.png
          /content/uploads/2015/08/BY_NP_45.jpg /assets/vidstack-video-ClHktyRI.js
          /.well-known/traffic-advice /.well-known/acme-challenge/abc /support /null
        ) do
      refute FourOhFour.probe?(url), "expected #{url} not to be a probe"
    end
  end
end
