terraform {
  required_version = ">= 1.10.0"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.7"
    }
  }
}

provider "keycloak" {}

resource "keycloak_realm" "realm" {
  realm   = var.realm_name
  enabled = true
}

resource "keycloak_openid_client" "traefik_forward_auth" {
  realm_id    = keycloak_realm.realm.id
  client_id   = var.forward_auth_client_id
  name        = "Traefik Forward Auth"
  description = "OIDC client for Traefik forward auth"
  enabled     = true

  access_type               = "CONFIDENTIAL"
  client_authenticator_type = "client-secret"
  client_secret_wo          = var.forward_auth_client_secret
  client_secret_wo_version  = var.forward_auth_client_secret_version

  standard_flow_enabled        = true
  implicit_flow_enabled        = false
  direct_access_grants_enabled = false
  service_accounts_enabled     = false

  valid_redirect_uris         = [var.forward_auth_redirect_uri]
  web_origins                 = [var.forward_auth_root_url]
  root_url                    = var.forward_auth_root_url
  base_url                    = var.forward_auth_root_url
  admin_url                   = var.forward_auth_root_url
  pkce_code_challenge_method  = ""
}