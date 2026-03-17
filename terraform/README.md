# Terraform

## Purpose

This directory contains the Terraform configuration that manages the local
Keycloak realm and the `traefik-forward-auth` OpenID Connect client.

`keycloak-terraform` runs once on startup and makes sure the `${KEYCLOAK_REALM}`
realm exists and that the `traefik-forward-auth` OIDC client is configured with
the redirect URI `https://auth.localtest.me/_oauth`, confidential client
authentication, and PKCE disabled.

If that client is changed back to `public` or its PKCE method is set to `S256`,
protected routes such as the Traefik dashboard will fall into a redirect loop on
`keycloak.localtest.me`.

## Layout

```text
terraform/
  README.md
  keycloak/
    main.tf
    variables.tf
```

The Terraform state lives under `terraform/keycloak/` and is not committed.

## Existing Environments

If you already started this stack with the old bootstrap flow, `keycloak-terraform`
will try to import the existing realm and `traefik-forward-auth` client before it
applies changes.

When rotating `KEYCLOAK_FORWARD_AUTH_CLIENT_SECRET`, also increment
`KEYCLOAK_FORWARD_AUTH_CLIENT_SECRET_VERSION` so Terraform knows to push the new
write-only secret into Keycloak.

## Manual Terraform plan and apply

When you run `docker compose up --no-deps keycloak-terraform`, Compose injects the
correct values automatically.

The easiest local entrypoint is `terraform/keycloak/plan.py`. It reads the repo
root `.env`, fills in the Terraform defaults described below, preserves any
explicitly exported environment variables, and then runs `terraform plan` or
`terraform apply`.

Examples:

```powershell
python .\plan.py
python .\plan.py -out tfplan
python .\plan.py apply
python .\plan.py apply -auto-approve
python .\plan.py --dry-run
```

```bash
python3 ./plan.py
python3 ./plan.py -out tfplan
python3 ./plan.py apply
python3 ./plan.py apply -auto-approve
python3 ./plan.py --dry-run
```

When you run `terraform plan` manually in `terraform/keycloak`, set the following
environment variables first.

| Name                                        | Expected value                                                     | Purpose                                                                |
| ------------------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------- |
| `KEYCLOAK_URL`                              | `https://keycloak.localtest.me`                                    | Keycloak base URL reachable from your host terminal                    |
| `KEYCLOAK_CLIENT_ID`                        | `admin-cli`                                                        | Provider login client                                                  |
| `KEYCLOAK_USER`                             | Same value as `.env` `KEYCLOAK_ADMIN`                              | Admin username used by the provider                                    |
| `KEYCLOAK_PASSWORD`                         | Same value as `.env` `KEYCLOAK_ADMIN_PASSWORD`                     | Admin password used by the provider                                    |
| `KEYCLOAK_REALM`                            | `master`                                                           | Login realm for `admin-cli`; this is not the managed application realm |
| `TF_VAR_realm_name`                         | Same value as `.env` `KEYCLOAK_REALM`                              | Realm managed by Terraform, usually `default`                          |
| `TF_VAR_forward_auth_client_id`             | Same value as `.env` `KEYCLOAK_FORWARD_AUTH_CLIENT_ID`             | Client ID for `traefik-forward-auth`                                   |
| `TF_VAR_forward_auth_client_secret`         | Same value as `.env` `KEYCLOAK_FORWARD_AUTH_CLIENT_SECRET`         | Client secret for `traefik-forward-auth`                               |
| `TF_VAR_forward_auth_client_secret_version` | Same value as `.env` `KEYCLOAK_FORWARD_AUTH_CLIENT_SECRET_VERSION` | Integer used to force secret updates when rotating the secret          |
| `TF_VAR_forward_auth_root_url`              | `https://auth.localtest.me`                                        | Root, base, and admin URL for the forward-auth client                  |
| `TF_VAR_forward_auth_redirect_uri`          | `https://auth.localtest.me/_oauth`                                 | OAuth callback URL registered in Keycloak                              |

The most confusing point is the realm split:

- `.env` `KEYCLOAK_REALM` is the realm you want Terraform to manage.
- Manual `terraform plan` must use `KEYCLOAK_REALM=master` so the provider can log in with `admin-cli`.
- That managed realm value must instead be passed as `TF_VAR_realm_name`.

If your provider login realm is not `master`, you can set `KEYCLOAK_PROVIDER_REALM`
in `.env`. `plan.py` will use that value as the default login realm while still
treating `.env` `KEYCLOAK_REALM` as the managed realm.

PowerShell example:

```powershell
$env:KEYCLOAK_URL = "https://keycloak.localtest.me"
$env:KEYCLOAK_CLIENT_ID = "admin-cli"
$env:KEYCLOAK_USER = "admin"
$env:KEYCLOAK_PASSWORD = "admin"
$env:KEYCLOAK_REALM = "master"

$env:TF_VAR_realm_name = "default"
$env:TF_VAR_forward_auth_client_id = "traefik-forward-auth"
$env:TF_VAR_forward_auth_client_secret = "changeme"
$env:TF_VAR_forward_auth_client_secret_version = "1"
$env:TF_VAR_forward_auth_root_url = "https://auth.localtest.me"
$env:TF_VAR_forward_auth_redirect_uri = "https://auth.localtest.me/_oauth"

terraform init
terraform plan
```

Shell example (`bash` / `zsh`):

```bash
export KEYCLOAK_URL="https://keycloak.localtest.me"
export KEYCLOAK_CLIENT_ID="admin-cli"
export KEYCLOAK_USER="admin"
export KEYCLOAK_PASSWORD="admin"
export KEYCLOAK_REALM="master"

export TF_VAR_realm_name="default"
export TF_VAR_forward_auth_client_id="traefik-forward-auth"
export TF_VAR_forward_auth_client_secret="changeme"
export TF_VAR_forward_auth_client_secret_version="1"
export TF_VAR_forward_auth_root_url="https://auth.localtest.me"
export TF_VAR_forward_auth_redirect_uri="https://auth.localtest.me/_oauth"

terraform init
terraform plan
```

If you want to reuse values from `.env`, copy them into the corresponding
`TF_VAR_*` variables, but keep `KEYCLOAK_REALM=master` for the provider login.