- Static builds request their pages from the endpoint's own HTTP listener, on whatever port it listens, instead of `http://localhost:4000`, still as host `localhost`, so an endpoint's `force_ssl` lets them through, and fail with a message before requesting anything when the endpoint has no listener.

- `mix brando.ssg --site <key>` with several sites writes to the site's own `sites/<key>/ssg/manual` by default instead of `./ssg`, and no longer starts the Vite watchers.

- Queuing a job tracked as admin work without a queued or running message (a static build) no longer logs `Could not report a job`.
