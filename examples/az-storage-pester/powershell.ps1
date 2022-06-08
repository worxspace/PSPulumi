Import-Module pspulumi.azurenative.resources
Import-Module pspulumi.azurenative.storage
Import-Module pspulumi.azurenative.compute

New-PulumiYamlFile {

  $location = 'switzerlandnorth'

  $resourceGroup = New-AzureNativeResourcesResourceGroup -pulumiid "MyResourceGroup" -resourceGroupName "MyResourceGroup" -location $location

  $Props = @{
    pulumiid          = "MyStorageAccount"
    accountName       = "pspulumist001"
    ResourceGroupName = $resourceGroup.reference("name")
    location          = $location
    Kind              = "StorageV2"
    Sku               = New-AzureNativeTypeStorageSku -name Standard_LRS
  }

  $storageAccount = New-AzureNativeStorageStorageAccount @Props

  # I'll sneak this in, no one will notice
  $AvailabilitySet = New-AzureNativeComputeAvailabilitySet -resourceGroupName $resourceGroup.reference("name") -location $location -pulumiid 'avset' -availabilitySetName 'MyAvailabilitySet'

}
