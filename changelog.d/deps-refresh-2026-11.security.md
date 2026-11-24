- The lock moves to versions with security fixes: `ex_aws` 2.8.1 and `ex_aws_s3` 2.6.0 (S3 keys and
  bucket names that could redirect or reshape a signed request, and the instance metadata token
  request following redirects), `db_connection` 2.10.3, `ecto` 3.14.3 (unbounded query cache growth)
  and `idna` 8.0.0 (slow rejection of over-long labels).
  Run `mix deps.update ex_aws ex_aws_s3 db_connection ecto idna`.
