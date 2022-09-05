# Enable and configure the Okta provider
terraform {
  required_providers {
    okta = {
      source  = "okta/okta"
      version = "~> 3.15"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
  required_version = "v1.0.4"
}

provider "okta" {
  org_name  = var.org_name
  base_url  = var.base_url
  api_token = var.api_token
}

resource "okta_user" "users" {
    for_each = {for idx, specs in var.users: idx => specs}
    first_name = each.value.first_name
    last_name  = each.value.last_name
    email      = each.value.email
    login      = each.value.login
    group_memberships = [each.value.group_membership == "k8s-admin" ? okta_group.groups["0"].id : (each.value.group_membership == "k8s-dev" ? okta_group.groups["1"].id : (each.value.group_membership == "k8s-test" ? okta_group.groups["2"].id : ""))]
    depends_on = [okta_group.groups]
}

resource "okta_group" "groups" {
    count = length(var.groups)
    name = var.groups[count.index]
}

# Create an OIDC application

resource "okta_app_oauth" "k8s_oidc" {
  label                      = "k8s OIDC"
  type                       = "native" # this is important
  token_endpoint_auth_method = "none"   # this sets the client authentication to PKCE
  grant_types = [
    "authorization_code"
  ]
  response_types = ["code"]
  redirect_uris = [
    "http://localhost:8000",
  ]
  post_logout_redirect_uris = [
    "http://localhost:8000",
  ]
  lifecycle {
    ignore_changes = [groups]
  }
}

# Assign groups to the OIDC application
resource "okta_app_group_assignments" "k8s_oidc_group" {
  app_id = okta_app_oauth.k8s_oidc.id
  dynamic "group" {
    for_each = {for index, id in okta_group.groups.*.id: index => id}
    content {
        id = group.value
    }
  }
}

output "k8s_oidc_client_id" {
  value = okta_app_oauth.k8s_oidc.client_id
}

# Create an authorization server

resource "okta_auth_server" "oidc_auth_server" {
  name      = "k8s-auth"
  audiences = ["http:://localhost:8000"]
}

output "k8s_oidc_issuer_url" {
  value = okta_auth_server.oidc_auth_server.issuer
}

# Add claims to the authorization server

resource "okta_auth_server_claim" "auth_claim" {
  name                    = "groups"
  auth_server_id          = okta_auth_server.oidc_auth_server.id
  always_include_in_token = true
  claim_type              = "IDENTITY"
  group_filter_type       = "STARTS_WITH"
  value                   = "k8s-"
  value_type              = "GROUPS"
}
# Add policy and rules to the authorization server

resource "okta_auth_server_policy" "auth_policy" {
  name             = "k8s_policy"
  auth_server_id   = okta_auth_server.oidc_auth_server.id
  description      = "Policy for allowed clients"
  priority         = 1
  client_whitelist = [okta_app_oauth.k8s_oidc.id]
}

resource "okta_auth_server_policy_rule" "auth_policy_rule" {
  name           = "AuthCode + PKCE"
  auth_server_id = okta_auth_server.oidc_auth_server.id
  policy_id      = okta_auth_server_policy.auth_policy.id
  priority       = 1
  grant_type_whitelist = [
    "authorization_code"
  ]
  scope_whitelist = ["*"]
  group_whitelist = ["EVERYONE"]
}

#### Create rolebindings using default roles.
resource "kubectl_manifest" "admin_rolebinding" {
  yaml_body = <<YAML
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: admin-rolebinding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: admin
subjects:
- kind: Group
  name: k8s-admin
YAML
}

resource "kubectl_manifest" "dev-rolebinding" {
  yaml_body = <<YAML
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: dev-rolebinding
  namespace: development
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: edit
subjects:
- kind: Group
  name: k8s-dev
YAML
}
resource "kubectl_manifest" "test-rolebinding" {
  yaml_body = <<YAML
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: test-rolebinding
  namespace: testing
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: view
subjects:
- kind: Group
  name: k8s-test
YAML
}