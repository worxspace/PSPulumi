Import-Module pspulumiyaml.azurenative.compute
Import-Module pspulumiyaml.azurenative.resources
Import-Module pspulumiyaml.azurenative.storage
Import-Module pspulumiyaml.azurenative.network

New-PulumiYamlFile {

    $TestRG = New-AzureNativeResourcesResourceGroup -pulumiid testrg -resourceGroupName test-rg

    $vNetProps = @{
        pulumiid          = "vnet"
        addressSpace      = @{
            addressPrefixes = @("10.0.0.0/16")
        }
        location          = "norwayeast"
        ResourceGroupName = $testrg.reference("name")
        subnets           = @(
            @{
                addressPrefix      = "10.0.0.0/24"
                name               = "test-1"
                virtualNetworkName = "test-vnet"
            }
        )
    }
    $vnet = New-AzureNativeNetworkVirtualNetwork @vNetProps

    $subnet = Invoke-AzureNativeFunctionNetworkGetSubnet -resourceGroupName $testrg.reference("name") -subnetName "test-1" -virtualNetworkName $vnet.reference("name")

    $Props = @{
        pulumiid          = "sa"
        ResourceGroupName = $testrg.reference("name")
        location          = "norwayeast"
        Kind              = "StorageV2"
        Sku               = @{
            Name = "Standard_LRS"
        }
    }
    $storageAccount = azure_native_storage_storageaccount @Props

    $NicProperties = @{
        resourceGroupName    = $testrg.reference("name")
        networkInterfaceName = "jandemovm01-nic"
        pulumiid             = "nic"
        ipConfigurations     = @(
            [pscustomobject]@{
                name   = "ipconfig1"
                subnet = @{
                    id = $subnet.reference("id")
                }
                #publicIPAddress = @{id = $null}
            }
        )
    }

    $VmNic = New-AzureNativeNetworkNetworkInterface @NicProperties

    $VmProperties = @{
        pulumiid          = "vm"
        resourceGroupName = $testrg.reference("name")
        vmName            = "jandemovm01"
        osProfile         = @{
            "computerName"  = "jandemovm01"
            "adminUsername" = "jandemoadmin"
            "adminPassword" = "!SuperSecret12345!"
            #LinuxConfiguration = @{ProvisionVMAgent = $true}
        }
        hardwareProfile   = @{
            "vmSize" = "Standard_D2s_v4"
        }
        networkProfile    = @{
            NetworkInterfaces = @{
                id      = $VmNic.reference("id")
                Primary = $true
            }
        }
        storageProfile    = @{
            imageReference = @{
                "offer"     = "0001-com-ubuntu-server-focal"
                "publisher" = "canonical"
                "sku"       = "20_04-lts-gen2"
                "version"   = "latest"
            }
            osDisk         = @{
                CreateOption = "FromImage"
                Caching      = "ReadWrite"
                managedDisk  = New-AzureNativeTypeComputeManagedDiskParameters -storageAccountType Standard_LRS
                Name         = "jandemovm01OsDisk"
                diskSizeGB   = 30
            }
        }
    }

    New-AzureNativeComputeVirtualMachine @VmProperties
}