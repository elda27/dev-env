variable "realm_name" {
  description = "Realm name for protected local services."
  type        = string
}

variable "forward_auth_client_id" {
  description = "Client ID used by traefik-forward-auth."
  type        = string
}

variable "forward_auth_client_secret" {
  description = "Client secret used by traefik-forward-auth."
  type        = string
  sensitive   = true
}

variable "forward_auth_client_secret_version" {
  description = "Increment this when rotating the forward-auth client secret."
  type        = number
  default     = 1
}

variable "forward_auth_root_url" {
  description = "Root URL for the auth callback host."
  type        = string
}

variable "forward_auth_redirect_uri" {
  description = "Redirect URI registered for the forward-auth callback."
  type        = string
}