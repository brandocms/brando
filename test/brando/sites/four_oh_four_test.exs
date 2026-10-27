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

  test "source maps, dev servers, keys, dumps and deploy config are probes" do
    for url <- ~w(
          /assets/index-B2kd9.js.map /_astro/page.astro_astro_type_script.astro.mjs.map /app.css.map
          /@fs/etc/passwd /proc/self/environ /../../proc/self/environ /static/..%2f..%2fproc%2fself%2fcmdline
          /__vite_ping /@vite/__vite_client /_profiler/phpinfo /_profiler /storage/logs/laravel.log
          /laravel.log /id_rsa /backup/id_ed25519 /server.pem /private.key /docker-compose.yml
          /docker-compose.prod.yaml /Dockerfile /composer.lock /appsettings.json /appsettings.Production.json
          /application.yml /application-prod.properties /config/application.yaml /service-account.json
          /vercel.json /netlify.toml /wrangler.toml /railway.json /values.yaml /rclone.conf
          /supabase/config.toml /aws-exports.js /src/aws-exports.js /aws/production.env /config/aws.yml
          /database.sql /backup.sql /dump.sql.gz /assets/env.js /actuator/health /phpmyadmin/ /server-status
        ) do
      assert FourOhFour.probe?(url), "expected #{url} to be a probe"
    end
  end

  # Real sites have these pages; scanners that try them are caught by the
  # self-referrer rule in list/0 instead
  test "generic words scanners also try are not probes by path" do
    for url <- ~w(
          /team /billing /dashboard/settings /login /settings/api-keys /docs /contact /blog /about
          /assets/app-4f9a1c.js /sitemap /maps /keynote /application /100%
        ) do
      refute FourOhFour.probe?(url), "expected #{url} not to be a probe"
    end
  end

  test "a referrer is the URL itself whatever its scheme, host, query and trailing slash" do
    for {url, referrer} <- [
          {"/wrangler.toml", "http://bielkeyang.com/wrangler.toml"},
          {"/blog", "http://bielkeyang.com/blog/"},
          {"/blog/", "https://www.bielkeyang.com/blog"},
          {"/apple-touch-icon.png", "https://64.227.71.155/apple-touch-icon.png"},
          {"/team", "http://ghost-rider/team?x=1"},
          {"/a b", "https://example.com/a%20b"},
          {"/100%", "https://example.com/100%25"},
          # Not a valid escape; compared as it is rather than raising
          {"/100%", "https://example.com/100%"},
          {"/", "http://ghost-rider/"},
          {"/", "http://ghost-rider"}
        ] do
      assert FourOhFour.self_referrer?(url, referrer), "expected #{referrer} to refer #{url} to itself"
    end

    for {url, referrer} <- [
          {"/blog", "http://bielkeyang.com/"},
          {"/blog", "http://bielkeyang.com/blog/post"},
          {"/old", "https://news.example.com/story"},
          {"/old", "/old"}
        ] do
      refute FourOhFour.self_referrer?(url, referrer), "expected #{referrer} not to refer #{url} to itself"
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
