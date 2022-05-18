resource "azurerm_resource_group" "PSPulumiEquivalent-rg" {
  name     = "PSPulumiVTerraform"
  location = "switzerlandnorth"
}

resource "azurerm_storage_account" "PSPulumiEquivalent-sa" {
  name                     = "pspulumivterraformsa01"
  location                 = azurerm_resource_group.PSPulumiEquivalent-rg.location
  resource_group_name      = azurerm_resource_group.PSPulumiEquivalent-rg.name
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  static_website {
    index_document     = "index.html"
    error_404_document = "404.html"
  }
}

resource "azurerm_storage_container" "PSPulumiEquivalent-sc" {
  name                 = "$web"
  storage_account_name = azurerm_storage_account.PSPulumiEquivalent-sa.name
}

resource "azurerm_storage_blob" "PSPulumiEquivalent-sbindex" {
  name                   = "index.html"
  storage_account_name   = azurerm_storage_account.PSPulumiEquivalent-sa.name
  storage_container_name = azurerm_storage_container.PSPulumiEquivalent-sc.name
  content_type           = "text/html"
  type                   = "Block"
  source                 = "../www/index.html"
}

resource "azurerm_storage_blob" "PSPulumiEquivalent-sb404" {
  name                   = "404.html"
  storage_account_name   = azurerm_storage_account.PSPulumiEquivalent-sa.name
  storage_container_name = azurerm_storage_container.PSPulumiEquivalent-sc.name
  content_type           = "text/html"
  type                   = "Block"
  source                 = "../www/404.html"
}

resource "azurerm_storage_blob" "PSPulumiEquivalent-sbfavicon" {
  name                   = "favicon.png"
  storage_account_name   = azurerm_storage_account.PSPulumiEquivalent-sa.name
  storage_container_name = azurerm_storage_container.PSPulumiEquivalent-sc.name
  content_type           = "image/png"
  type                   = "Block"
  source                 = "../www/favicon.png"
}

output "storageKey" {
  value     = azurerm_storage_account.PSPulumiEquivalent-sa.primary_access_key
  sensitive = true
}
