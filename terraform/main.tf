terraform {
  required_providers {
    terracurl = {
      source  = "devops-rob/terracurl"
      version = "1.0.1"
    }
  }
}

variable "prefix" {
  default = "example"
}
variable "location" {
  default = "East US"
}

variable "vault_license" {
  type = string
}

variable "tde_namespace" {
  type    = string
  default = ""
}

variable "tfc" {
  type = object({
    organization = string
    workspace    = string
    ttl          = optional(string, "")
  })
}

variable "tfc_api_token" {
  type      = string
  sensitive = true
}

module "azure-env" {
  source   = "./azure-env"
  prefix   = var.prefix
  location = var.location
}

module "vault-server" {
  source                      = "./vault-server"
  prefix                      = var.prefix
  license                     = var.vault_license
  tde_namespace               = var.tde_namespace
  resource_group_name         = module.azure-env.azurerm_resource_group_name
  resource_group_location     = module.azure-env.azurerm_resource_group_location
  resource_group_subnet_id    = module.azure-env.azurerm_resource_group_subnet_id
  network_security_group_name = module.azure-env.network_security_group_name
}

module "mssql-server" {
  source                      = "./mssql-server"
  prefix                      = var.prefix
  resource_group_name         = module.azure-env.azurerm_resource_group_name
  resource_group_location     = module.azure-env.azurerm_resource_group_location
  resource_group_subnet_id    = module.azure-env.azurerm_resource_group_subnet_id
  network_security_group_name = module.azure-env.network_security_group_name
}

resource "terracurl_request" "schedule_destroy" {
  name   = "schedule-destroy-at"
  url    = format("https://app.terraform.io/api/v2/organizations/%s/workspaces/%s", var.tfc.organization, var.tfc.workspace)
  method = "PATCH"
  request_body = jsonencode({
    data = {
      type = "workspaces"
      attributes = {
        auto-destroy-at = var.tfc.ttl != "" ? timeadd(timestamp(), var.tfc.ttl) : null
      }
    }
  })
  headers = {
    Authorization = "Bearer ${var.tfc_api_token}"
    Content-Type  = "application/vnd.api+json"
  }
  response_codes = [200]
}

output "vault_server_public_ip" {
  value = module.vault-server.azurerm_public_ip
}

output "vault_server_http_url" {
  value = "http://${module.vault-server.azurerm_public_ip}:8200"
}

output "vault_server_ssh_cmd" {
  value = "ssh -i private-key vadmin@${module.vault-server.azurerm_public_ip}"
}

output "mssql_server_public_ip" {
  value = module.mssql-server.azurerm_public_ip
}

output "password" {
  value     = module.mssql-server.password
  sensitive = true
}

output "start_rdp_session" {
  value = module.mssql-server.start_rdp_session
}

output "ssh_private_key" {
  value     = module.vault-server.private_key_openssh
  sensitive = true
}
