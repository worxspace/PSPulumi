using module ./pspulumi.psm1

pulumi {

  $props = @{
    pulumiid = "test"
    name     = "MyResourceGroup"
  }
  $test = azresourcegroup @props

  $props = @{
    pulumiid          = "teststorage"
    name              = "ryanjantest1"
    kind              = "StorageV2"
    sku               = "Standard_LRS"
    resourcegroupname = $test
  }
  $storage = azstorageaccount @props

  $props = @{
    pulumiid          = "teststorage"
    name              = "ryanjantest1"
    kind              = "StorageV2"
    sku               = @{
      name = "Standard_LRS"
    }
    resourcegroupname = $test
  }
  $storage = azstorageaccount @props

  $props = @{
    pulumiid          = "teststorage"
    name              = "ryanjantest1"
    kind              = "StorageV2"
    sku               = storageaccountsku -name "standard_lrs"
    resourcegroupname = $test
  }
  $storage = azstorageaccount @props

  azNativestorageStorageAccount -pulumiid test `
    -name teststorage `
    -kind storagev2 `
    -sku [classname]@ { name = "bob" } `
    -resourcegroupname (ref $test.name)

  aznative_storage_storageaccount -sku $(aznative_type_storage_storageaccountsku -name [storagesku]::storagev2)

  $sku = functioncall -name 
  $saspolicy = ""
  azNativestorageStorageAccount -pulumiid test `
    -name teststorage `
    -kind storagev2 `
    -sku $sku `
    -resourcegroupname (ref $test.name)

  azNativestorageStorageAccount @{

  }
}

function aznative/storage/storageaccount {

}