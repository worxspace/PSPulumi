Import-Module pspulumiyaml.azurenative.resources
Import-Module pspulumiyaml.azurenative.storage

pulumi_configuration {

  $location = , 'switzerlandnorth'#, 'westeurope'

  $resourceGroup = azure_native_resources_resourcegroup -pulumiid "static-web-app" -resourceGroupName "static-web-app" -location $(get-random $location)

  $Props = @{
    pulumiid          = "sa"
    accountName       = "pspulumistweb"
    ResourceGroupName = $resourceGroup.reference("name")
    location          = $(get-random $location)
    Kind              = "StorageV2"
    Sku               = @{
      Name = "Standard_LRS"
    }
  }
  $storageAccount = azure_native_storage_storageaccount @Props

  $Props = @{
    pulumiid          = "website"
    accountName       = $storageAccount.reference("name")
    resourceGroupName = $resourceGroup.reference("name")
    indexDocument     = "index.html"
    error404Document  = "404.html"
  }
  $website = azure_native_storage_storageaccountstaticwebsite @Props

  "index.html", "404.html" | ForEach-Object {
    $Props = @{
      pulumiid          = $_
      ResourceGroupName = $resourceGroup.reference("name")
      AccountName       = $storageAccount.reference("name")
      ContainerName     = $website.reference("containerName")
      contentType       = "text/html"
      Type              = "Block"
      Source            = pulumi_file_asset "./www/$_"
    }
    $null = azure_native_storage_blob @Props
  }
  
  $Props = @{
    pulumiid          = "favicon.png"
    ResourceGroupName = $resourceGroup.reference("name")
    AccountName       = $storageAccount.reference("name")
    ContainerName     = $website.reference("containerName")
    contentType       = "image/png"
    Type              = "Block"
    Source            = pulumi_file_asset "./www/favicon.png"
  }
  $null = azure_native_storage_blob @Props

  $keys = Invoke-AzureNativeFunctionStorageListStorageAccountKeys -accountName $storageAccount.reference("name") -resourceGroupName $resourceGroup.reference("name")

  pulumi_output test $storageAccount.reference("primaryEndpoints.web")
  pulumi_output primarykey $keys.reference("keys[0].value")
}
