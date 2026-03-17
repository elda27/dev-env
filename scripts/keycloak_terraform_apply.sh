#!/bin/sh
set -eu

terraform_dir="/workspace/terraform/keycloak"
keycloak_url="${KEYCLOAK_URL:?KEYCLOAK_URL is required}"
keycloak_user="${KEYCLOAK_USER:?KEYCLOAK_USER is required}"
keycloak_password="${KEYCLOAK_PASSWORD:?KEYCLOAK_PASSWORD is required}"
keycloak_client_id="${KEYCLOAK_CLIENT_ID:-admin-cli}"
realm_name="${TF_VAR_realm_name:?TF_VAR_realm_name is required}"
forward_auth_client_id="${TF_VAR_forward_auth_client_id:?TF_VAR_forward_auth_client_id is required}"

wait_for_keycloak() {
  echo "Waiting for Keycloak at ${keycloak_url}..."
  until wget -q --spider "${keycloak_url}/realms/master/.well-known/openid-configuration"; do
    sleep 2
  done
}

fetch_admin_token() {
  response="$(wget -qO- \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --post-data "client_id=${keycloak_client_id}&username=${keycloak_user}&password=${keycloak_password}&grant_type=password" \
    "${keycloak_url}/realms/master/protocol/openid-connect/token")"
  printf '%s' "$response" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

import_realm_if_present() {
  access_token="$1"

  if terraform state show keycloak_realm.realm >/dev/null 2>&1; then
    return
  fi

  if realm_json="$(wget -qO- --header "Authorization: Bearer ${access_token}" "${keycloak_url}/admin/realms/${realm_name}" 2>/dev/null)"; then
    if printf '%s' "$realm_json" | grep -q "\"realm\":\"${realm_name}\""; then
      echo "Importing existing realm ${realm_name} into Terraform state"
      terraform import -input=false keycloak_realm.realm "${realm_name}" >/dev/null
    fi
  fi
}

import_client_if_present() {
  access_token="$1"

  if terraform state show keycloak_openid_client.traefik_forward_auth >/dev/null 2>&1; then
    return
  fi

  client_json="$(wget -qO- --header "Authorization: Bearer ${access_token}" "${keycloak_url}/admin/realms/${realm_name}/clients?clientId=${forward_auth_client_id}" 2>/dev/null || true)"
  client_uuid="$(printf '%s' "$client_json" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' | awk 'NR==1 { print; exit }')"

  if [ -n "$client_uuid" ]; then
    echo "Importing existing client ${forward_auth_client_id} into Terraform state"
    terraform import -input=false keycloak_openid_client.traefik_forward_auth "${realm_name}/${client_uuid}" >/dev/null
  fi
}

main() {
  wait_for_keycloak
  cd "$terraform_dir"
  terraform init -input=false

  access_token="$(fetch_admin_token)"
  if [ -z "$access_token" ]; then
    echo "Failed to retrieve Keycloak admin access token" >&2
    exit 1
  fi

  import_realm_if_present "$access_token"
  import_client_if_present "$access_token"

  terraform apply -input=false -auto-approve
}

main "$@"