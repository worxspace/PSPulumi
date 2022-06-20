Describe 'My Azure Infra' {
    BeforeDiscovery {
        $ParsedConfig = . $PSScriptRoot/powershell.ps1 | ConvertFrom-Json -AsHashtable
        $storageAccounts = $ParsedConfig.resources.values.where{$_.type -eq 'azure-native:storage:StorageAccount'}.properties
    }

    It 'generates configuration without error' {
        { $Config = . $PSScriptRoot/powershell.ps1 } | Should -Not -Throw

        $Config | Should -BeNullOrEmpty
    }

    context 'Compliance' {

        It 'should not contain any compute resource' {
            $ParsedConfig.resources.values.type -Match 'azure-native:compute:' | Should -BeNullOrEmpty -Because 'it should not return any resource types of type azure-native:compute:*'
        }

        It 'should follow my naming convention for storageaccounts. "<accountName>" should match "{project}st{000}"' -TestCases $storageAccounts {
            param($accountName)

            $accountName | Should -Match -RegularExpression 'st\d{3}$'
            $accountName.length | Should -BeLessOrEqual 24
        }
    }
}

Describe 'Code Style' {
    It 'should use sku type functions instead of strings for storage accounts' {
        $storagecounter = 0
        Mock New-AzureNativeStorageStorageAccount { $null = $storagecounter++ }
        Mock New-AzureNativeTypeStorageSku { 'testing value is passed from New-AzureNativeTypeStorageSku' }

        { $Config = . $PSScriptRoot/powershell.ps1 }

        Should -Invoke New-AzureNativeTypeStorageSku -Times $storagecounter -Exactly -Scope It

        # not currently working
        # Should -Invoke New-AzureNativeStorageStorageAccount -ParameterFilter { $Sku -eq 'testing value is passed from New-AzureNativeTypeStorageSku' } -Times $storagecounter -Exactly -Scope It
    }
}
