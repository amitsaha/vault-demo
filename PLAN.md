## Goal: Application reads precreated secret from vault

### Start vault server

```
$ sudo ./vault server -config=./vault.conf
[sudo] password for asaha:
==> Vault server configuration:

                     Cgo: disabled
              Listener 1: tcp (addr: "127.0.0.1:8200", cluster address: "127.0.0.1:8201", tls: "disabled")
               Log Level: info
                   Mlock: supported: true, enabled: true
                 Storage: file
                 Version: Vault v0.7.3
             Version Sha: 0b20ae0b9b7a748d607082b1add3663a28e31b68

==> Vault server started! Log data will stream in below:

```

### Initialize Vault server

```
$ VAULT_ADDR=http://127.0.0.1:8200 ./vault init

Unseal Key 1: zZi0trHXYAX4neuttonFwU3Lst/T47ngHM2UIKLIeIQW
Unseal Key 2: NVgiE9S0j5009HTzosRwnfxjGfI9azRsumZZ4nv9Brd5
Unseal Key 3: nGpTPkchfiud6hJmvujikusqsgisYS15SjEBO7nV8Bh6
Unseal Key 4: q4c8tkirmlQlr28i28WrsfYp4OaECxIy1WCClPtGnlWU
Unseal Key 5: DUFlmucGBZ4U0AKEw4Hhh52ccK6SLRBXMG3GlfPs+ylf
Initial Root Token: ffd0f4f5-65af-6a8b-6048-7d12a5e3e657

Vault initialized with 5 keys and a key threshold of 3. Please
securely distribute the above keys. When the vault is re-sealed,
restarted, or stopped, you must provide at least 3 of these keys
to unseal it again.

Vault does not store the master key. Without at least 3 keys,
your vault will remain permanently sealed.
```

### Unseal Vault

```
$ VAULT_ADDR=http://127.0.0.1:8200 ./vault unseal zZi0trHXYAX4neuttonFwU3Lst/T47ngHM2UIKLIeIQW
Sealed: true
Key Shares: 5
Key Threshold: 3
Unseal Progress: 1
Unseal Nonce: ac761062-9a4e-726e-4b4a-9893e3a2ac1a
asaha@asaha-desktop:~/work/github.com/amitsaha/vault$
asaha@asaha-desktop:~/work/github.com/amitsaha/vault$ VAULT_ADDR=http://127.0.0.1:8200 ./vault unseal NVgiE9S0j5009HTzosRwnfxjGfI9azRsumZZ4nv9Brd5
Sealed: true
Key Shares: 5
Key Threshold: 3
Unseal Progress: 2
Unseal Nonce: ac761062-9a4e-726e-4b4a-9893e3a2ac1a
```

Perform above with two more keys.

### Create the secret for the app

Now, we will create a secret for the application to access: `secret/testapp/facebook_api_key` (where `testapp` is the application name and will be the `approle`).

We will create a secret as a non-admin user who has a token associated with a policy to write to `secret/*`. First, let's create a policy:

```
// secret-creator.hcl
path "secret/*" {
  policy = "write"
}
```

Write the policy using the root token:

```
$ VAULT_TOKEN=ffd0f4f5-65af-6a8b-6048-7d12a5e3e657 VAULT_ADDR=http://127.0.0.1:8200 ./vault policy-write secret-creator ./secret-creator.hcl
Policy 'secret-creator' written.
```

Now, create a token with the above policy by using the root token:

```
$ VAULT_TOKEN=ffd0f4f5-65af-6a8b-6048-7d12a5e3e657 VAULT_ADDR=http://127.0.0.1:8200 ./vault token-create -policy=secret-creator
Key             Value
---             -----
token           88096632-1e74-6a09-3a57-e78b06597010
token_accessor  3a3b0686-ac2a-71ea-3ab4-a721d2c70d57
token_duration  768h0m0s
token_renewable true
token_policies  [default secret-creator]
```

Then, create the secret using the above token:

```
$ VAULT_TOKEN=88096632-1e74-6a09-3a57-e78b06597010 VAULT_ADDR=http://127.0.0.1:8200 ./vault write secret/testapp/facebook_api_key value=myapitoken

```

### Setup `approle` - `testapp`

#### Enable approle auth backend

```
$ VAULT_TOKEN=ffd0f4f5-65af-6a8b-6048-7d12a5e3e657 VAULT_ADDR=http://127.0.0.1:8200 ./vault auth-enable 
Successfully enabled 'approle' at 'approle'!
```
#### Create a policy for the approle token

As admin, create an `approle` in vault, associate with it policy to access the secret:

```
// read policy
path "secret/testapp/*" {
  policy = "read"
}
```

Create the policy:
```
$ VAULT_TOKEN=ffd0f4f5-65af-6a8b-6048-7d12a5e3e657 VAULT_ADDR=http://127.0.0.1:8200 ./vault policy-write secrets-testapp-read ./testapp-read.hcl
Policy 'secrets-testapp-read' written.
```


#### Create an approle and associate with it a policy to read the secret

```

$ VAULT_TOKEN=ffd0f4f5-65af-6a8b-6048-7d12a5e3e657 VAULT_ADDR=http://127.0.0.1:8200 ./vault write auth/approle/role/testapp secret_id_ttl=10m token_num_uses=10 token_ttl=20m token_max_ttl=30m secret_id_num_uses=40 policies=secrets-testapp-read
Success! Data written to: auth/approle/role/testapp
```

### Setup for application to access the secret

#### Setup policy to access secret

As admin create a token for the app, which will be able to get the role_id, secret_id from vault with the following policy:

```
// testapp-approle.hcl

path "auth/approle/role/testapp/role-id" {
  policy = "read"
}

path "auth/approle/role/testapp/secret-id" {
  policy = "write"
}
```

Write the above policy:

```
$ VAULT_TOKEN=ffd0f4f5-65af-6a8b-6048-7d12a5e3e657 VAULT_ADDR=http://127.0.0.1:8200 ./vault policy-write approle-testapp-get-token ./testapp-approle.hcl
Policy 'approle-testapp-get-token' written.
```

#### Wrap it in a cubbyhole token temporary with max usage

```
$ VAULT_TOKEN=ffd0f4f5-65af-6a8b-6048-7d12a5e3e657 VAULT_ADDR=http://127.0.0.1:8200 ./vault token-create -policy=approle-testapp-get-token --wrap-ttl=24h --use-limit=10
Key                             Value
---                             -----
wrapping_token:                 b1c367d2-cbb5-7aa4-6c1b-86845f8b13c1
wrapping_token_ttl:             24h0m0s
wrapping_token_creation_time:   2017-07-04 16:56:54.833347211 +1000 AEST
wrapped_accessor:               f6d780ba-229b-51c3-d90c-e194d57704a5
```
#### Access secret from the application

Use the above `wrapping_token` to unwrap the above token:

```
$ VAULT_TOKEN=b1c367d2-cbb5-7aa4-6c1b-86845f8b13c1 VAULT_ADDR=http://127.0.0.1:8200 ./vault unwrap
Key             Value
---             -----
token           4dbefb16-d3fa-a86e-e08c-7f02c869ebf2
token_accessor  f6d780ba-229b-51c3-d90c-e194d57704a5
token_duration  768h0m0s
token_renewable true
token_policies  [approle-testapp-get-token default]
```
Use the above `token` to get the `role_id` and `secret-id` for `testapp` role:

```
$ VAULT_TOKEN=4dbefb16-d3fa-a86e-e08c-7f02c869ebf2 VAULT_ADDR=http://127.0.0.1:8200 ./vault write -f auth/approle/role/testapp/secret-id
Key                     Value
---                     -----
secret_id               29a796f7-9ae3-acfd-a73e-353f36e5f3e5
secret_id_accessor      79c02e10-4a06-3b49-d875-aa9c23a482d7

$ VAULT_TOKEN=4dbefb16-d3fa-a86e-e08c-7f02c869ebf2 VAULT_ADDR=http://127.0.0.1:8200 ./vault read auth/approle/role/testapp/role-id
Key     Value
---     -----
role_id 204a4d33-206a-066e-591d-e23cb1cb3736
```

Use the above `role_id` and `secret_id` to get a token:

```
$ VAULT_ADDR=http://127.0.0.1:8200 ./vault write auth/approle/login role_id=204a4d33-206a-066e-591d-e23cb1cb3736 secret_id=29a796f7-9ae3-acfd-a73e-353f36e5f3e5
Key             Value
---             -----
token           5d2a2d0b-5963-d148-5a60-4c7828b4d916
token_accessor  a671170e-4394-be05-1674-83d97555f01d
token_duration  20m0s
token_renewable true
token_policies  [default secrets-testapp-read]
```

Now, we can read the secret:

```
$ VAULT_TOKEN=5d2a2d0b-5963-d148-5a60-4c7828b4d916 VAULT_ADDR=http://127.0.0.1:8200 ./vault read secret/testapp/facebook_api_key
Key                     Value
---                     -----
refresh_interval        768h0m0s
value                   myapitoken
```


### Questions

- Identity of the app? https://www.hashicorp.com/blog/cubbyhole-authentication-principles/

#### Plan to implement above

A trusted process gets the `temptoken` (wrapped) and launches the application with the `temptoken` as an ENV VAR. But how does this process get the wrapped `temptoken`? May be that happens as part of the provisioning by contacting another locked down "admin" process.

Refer:

- https://kickstarter.engineering/ecs-vault-shhhhh-i-have-a-secret-40e41af42c28
  - https://github.com/kickstarter/serverless-approle-manager
- https://github.com/DavidWittman/envconsul/tree/135-vault-unwrap

Vault controller implementation on Kubernetes:

- https://github.com/kelseyhightower/vault-controller
- https://github.com/Boostport/kubernetes-vault

##### Application deployed on a VM - one application instance per VM

Strategy 1:

- Instance boots up
- Starts the proxy process, P with a vault token `xxxx` which will be responsible for handing out wrapped secret IDs by talking directly to Vault cluster
  - This can only hand out approle secret ids for a designated approle ensured by token `xxxx`
  - A proxy process per instance, P
  - This proxy process is handed out the token by the initialization script, injected as part of the initialization process
    - Approle of the instance derived from the instance metadata
    - Authenticity from the Instance security certificate and other ways
    - Access lock down of the vault cluster ensures that only designated instances can talk to it
      - For AWS: https://www.vaultproject.io/docs/auth/aws.html
   
- Application initialization script kicks off the following:
  - Contact P for the `approle`'s wrapped `secret_id` (with max # of uses set to 2)
  - P verifies that the process has priveleges to access the wrapped token (How?)
  - Sends the wrapped token
  - Starts the application passing the wrapped token in an environment variable
  - Application reads the real `secret_id`. Using the `role_id` it then proceeds to get a token to access the secret




