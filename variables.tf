variable "base_url" {
  description = "The Okta base URL. Example: okta.com, oktapreview.com, etc. This is the domain part of your Okta org URL"
}
variable "org_name" {
  description = "The Okta org name. This is the part before the domain in your Okta org URL"
}
variable "api_token" {
  type        = string
  description = "The Okta API token, this will be read from environment variable (TF_VAR_api_token) for security"
  sensitive   = true
}

variable "users" {
    type = list(map(string))
    description = "The list of users to be created on Okta"
}

variable "groups" {
    type = list
    description = "List of groups to be created on Okta"
}
