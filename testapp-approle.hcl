path "auth/approle/role/testapp/role-id" {
  policy = "read"
}

path "auth/approle/role/testapp/secret-id" {
  policy = "write"
}
