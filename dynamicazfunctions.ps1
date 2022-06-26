$ProgressPreference = 'SilentlyContinue'

irm https://raw.githubusercontent.com/pulumi/pulumi-azure-native/master/provider/cmd/pulumi-resource-azure-native/schema.json -OutFile $PSScriptRoot/schema.json
$schema = Get-Content ./schema.json | ConvertFrom-Json -AsHashtable

$OutputDirectory = "$PSScriptRoot/bin"
New-Item $OutputDirectory -ItemType Directory -Force | Out-Null
Remove-Item (Join-Path $OutputDirectory "*") -Force -re
$RootModuleName = "pspulumiyaml.azurenative"
$RootModule = Join-Path $OutputDirectory "$RootModuleName.psm1"

$script:classesToCreate = @()
$script:functionsToCreate = @()

$script:typeswithmultiplerefs = @{}

function Convert-PulumiNameToModuleName {
    param(
        [parameter(mandatory, valuefrompipeline)]
        [string]
        $Name
    )

    process {
        $NameParts = $Name -split ':'
        return    "pspulumiyaml.{0}.{1}" -f $NameParts[0].replace("-", ""), $NameParts[1].replace("-", "")
    }
}

function Convert-PulumiTypeToPowerShellType {
    param(
        [parameter(mandatory, valuefrompipeline)]
        [AllowEmptyString()]
        [string]
        $Type,

        [parameter()]
        [AllowEmptyString()]
        [string]
        $Description
    )

    process {
        switch ($Type) {
            'string' {
                return "[string]"
            }
            'number' {
                return "[int]"
            }
            'integer' {
                return "[int]"
            }
            'boolean' {
                if ($Description -match 'must not set the property to false') {
                    return "[Nullable[bool]]"
                }
                else {
                    return "[bool]"
                }
            }
            'array' {
                return "[array]"
            }
            default {
                return "[object]"
            }
        }
    }
}

function Convert-PulumiComplexTypeToPowerShellType {
    param(
        [parameter(mandatory, valuefrompipeline)]
        [AllowEmptyString()]
        [string]
        $Type
    )

    process {
        switch ($Type) {
            'string' {
                return "[hashtable]"
            }
            default {
                return "[object]"
            }
        }
    }
}

function Get-ClassPropertyText {
    param(
        [parameter(mandatory, valuefrompipeline)]
        [string]
        $PropertyName,

        [parameter(mandatory)]
        $TypeDefinition,

        [parameter()]
        [string]
        $CurrentModule
    )

    process {
        $Output = @()

        $inputProperty = $TypeDefinition.properties[$PropertyName]

        $propertytypestring = ""
        $validateset = $null

        $type = $($inputProperty.type, $inputProperty.oneOf.type | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $arraytype = $($inputProperty.items.type, $inputProperty.items.oneOf.type | Where-Object { -not [string]::IsNullOrEmpty($_) })

        $oneOfRefs = @($inputProperty.oneOf.'$ref') + @($inputProperty.items.oneOf.'$ref') | Where-Object { -not [string]::IsNullOrEmpty($_) }

        if ($oneOfRefs.count -gt 1) {
            #TODO: bad practice fix
            $script:typeswithmultiplerefs["$className-$PropertyName"] = $oneOfRefs
            return '[object] ${0} #todo add class here' -f $propertyName
        }

        $propertytypestring = Convert-PulumiTypeToPowerShellType -Type "$type" -Description $inputProperty.description

        write-verbose "creating class property $PropertyName with initial type $propertytypestring"

        if ($propertytypestring -eq "[object]") {
            $ref = $($inputProperty.'$ref', $inputProperty.oneOf.'$ref' | Where-Object { -not [string]::IsNullOrEmpty($_) })

            if ([string]::IsNullOrEmpty($ref)) {
                $type = $inputProperty.additionalProperties.type, $inputProperty.oneOf.additionalProperties.type, $inputProperty.additionalProperties.'$ref', $inputProperty.oneOf.additionalProperties.'$ref'
                $propertytypestring = Convert-PulumiTypeToPowerShellType -Type "$type" -Description $inputProperty.description
            }
            elseif ($ref -imatch '^pulumi.json#/') {
                $propertytypestring = "[object]"
            }
            else {
                write-verbose "creating class for object $ref"
                $parts = $ref -split '/'
                $refObject = $schema.types[$parts[-1]]

                if ($null -ne $refObject.enum) {
                    $validateset = $refObject.enum.value
                }
                else {
                    $classObject = $parts[-1] | Add-ClassDefinitionToModule -SchemaObject $SchemaObject -RootModuleFile $RootModuleFile
                    $classFQDN = $classObject.module -eq $CurrentModule ? $classObject.Name : "{0}.{1}" -f $classObject.module, $classObject.Name
                    $propertytypestring = "[$classFQDN]"
                }
            }
        }

        if ($propertytypestring -eq "[array]") {
            $propertytypestring = "[{0}[]]" -f (Convert-PulumiTypeToPowerShellType -Type $arraytype -Description $inputProperty.description).trim('[]')
        }

        if ($propertytypestring -eq '[object[]]') {
            $ref = $($inputProperty.items.'$ref', $inputProperty.items.oneOf.'$ref' | Where-Object { -not [string]::IsNullOrEmpty($_) })

            if ([string]::IsNullOrEmpty($ref)) {
                $type = $inputProperty.additionalProperties.type, $inputProperty.oneOf.additionalProperties.type
                $propertytypestring = "[{0}[]]" -f (Convert-PulumiComplexTypeToPowerShellType -Type "$type").trim('[]')
            }
            elseif ($ref -imatch '^pulumi.json#/') {
                $propertytypestring = "[object[]]"
            }
            else {
                $parts = $ref -split '/'
                $refObject = $schema.types[$parts[-1]]

                if ($null -ne $refObject.enum) {
                    $propertytypestring = Convert-PulumiTypeToPowerShellType -Type $refObject.type -Description $inputProperty.description
                    $validateset = $refObject.enum.value
                }
                else {
                    $classObject = $parts[-1] | Add-ClassDefinitionToModule -SchemaObject $SchemaObject -RootModuleFile $RootModuleFile
                    $classFQDN = $classObject.module -eq $CurrentModule ? $classObject.Name : "{0}.{1}" -f $classObject.module, $classObject.Name
                    $propertytypestring = "[$classFQDN[]]"
                }
            }
        }

        if ($null -ne $inputProperty.oneOf) {
            $parts = $inputProperty.oneOf.'$ref' -split '/'
            $refObject = $schema.types[$parts[-1]]

            if ($null -ne $refObject.enum) {
                $propertytypestring = Convert-PulumiTypeToPowerShellType -Type $refObject.type -Description $inputProperty.description
                $validateset = $refObject.enum.value
            }
        }

        if ($null -ne $validateset) {
            $attribute = "ArgumentCompletions"
            $Output += "[{0}({1})]" -f $attribute, $($validateset.foreach{ "'$_'" } -join ', ')
        }

        $Output += "$propertytypestring `${0}" -f $PropertyName

        return $Output
    }
}

function Get-FunctionParameterText {
    param(
        [parameter(mandatory, valuefrompipeline)]
        [string]
        $ParameterName,

        [parameter(mandatory)]
        $TypeDefinition,

        [parameter()]
        [ValidateSet("resource", "type", "function")]
        $ObjectType = "resource",

        [parameter()]
        [string]
        $CurrentModule
    )

    process {
        $Output = @()
        $validateset = $null

        $inputProperty = ""
        switch ($ObjectType) {
            "resource" {
                $inputProperty = $TypeDefinition.inputProperties[$ParameterName]
            }
            "type" {
                $inputProperty = $TypeDefinition.properties[$ParameterName]
            }
            "function" {
                $inputProperty = $TypeDefinition.inputs.properties[$ParameterName]
            }
        }

        $Output += "[parameter(mandatory=`${0},HelpMessage='{1}')]" -f $($requiredInputs -contains $ParameterName), $("$("$($inputProperty.description)" -replace '(\r\n)|\r|\n', [system.environment]::newline))" -replace "['’‘]", "''")

        $propertytypestring = ""

        $type = $($inputProperty.type, $inputProperty.oneOf.type | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $arraytype = $($inputProperty.items.type, $inputProperty.items.oneOf.type | Where-Object { -not [string]::IsNullOrEmpty($_) })
        if ($null -ne ($inputProperty.items.'$ref', $inputProperty.items.oneOf.'$ref' | Where-Object { -not [string]::IsNullOrEmpty($_) })) {
            $type = "[object[]]"
        }

        write-verbose "adding function parameter $ParameterName with initial type $type"

        $propertytypestring = $type | Convert-PulumiTypeToPowerShellType -Description $inputProperty.description

        if ($propertytypestring -eq "[object]") {
            $ref = $($inputProperty.'$ref', $inputProperty.oneOf.'$ref', $inputProperty.additionalProperties.'$ref', $inputProperty.oneOf.additionalProperties.'$ref' | Where-Object { -not [string]::IsNullOrEmpty($_) })

            if ([string]::IsNullOrEmpty($ref)) {
                $type = $inputProperty.additionalProperties.type, $inputProperty.oneOf.additionalProperties.type | Where-Object { -not [string]::IsNullOrEmpty($_) }
                $propertytypestring = $type | Convert-PulumiComplexTypeToPowerShellType
            }
            elseif ($ref -imatch '^pulumi.json#/') {
                $propertytypestring = "[object]"
            }
            else {
                $parts = $ref -split '/'
                $classObject = $parts[-1] | Add-ClassDefinitionToModule -SchemaObject $SchemaObject -RootModuleFile $RootModuleFile

                # Write-Verbose "Building parameter $parametername in $CurrentModule. Class to be used is $($classObject.Name) in module $($classObject.module)" -verbose

                $classFQDN = $classObject.module -eq $CurrentModule ? $classObject.Name : "{0}.{1}" -f $classObject.module, $classObject.Name
                $propertytypestring = "[$classFQDN]"
            }
        }

        if ($propertytypestring -eq "[array]") {
            write-verbose "adding function parameter $ParameterName with array type $arraytype"
            $propertytypestring = "[{0}[]]" -f ($arraytype | Convert-PulumiTypeToPowerShellType -Description $inputProperty.description).trim('[]')
        }

        if ($propertytypestring -eq '[object[]]') {
            $ref = $($inputProperty.items.'$ref', $inputProperty.items.oneOf.'$ref' | Where-Object { -not [string]::IsNullOrEmpty($_) })

            if ([string]::IsNullOrEmpty($ref)) {
                $type = $inputProperty.additionalProperties.type, $inputProperty.oneOf.additionalProperties.type
                $propertytypestring = "[{0}[]]" -f ($type | Convert-PulumiComplexTypeToPowerShellType).trim('[]')
            }
            elseif ($ref -imatch '^pulumi.json#/') {
                $propertytypestring = "[object[]]"
            }
            else {
                $parts = $ref -split '/'
                $classObject = $parts[-1] | Add-ClassDefinitionToModule -SchemaObject $SchemaObject -RootModuleFile $RootModuleFile
                $classFQDN = $classObject.module -eq $CurrentModule ? $classObject.Name : "{0}.{1}" -f $classObject.module, $classObject.Name
                $propertytypestring = "[$classFQDN[]]"
            }
        }

        $Output += $propertytypestring

        if ($null -ne $inputProperty.oneOf) {
            $parts = $inputProperty.oneOf.'$ref' -split '/'
            $refObject = $schema.types[$parts[-1]]

            if ($null -ne $refObject.enum) {
                $propertytypestring = Convert-PulumiTypeToPowerShellType -Type $refObject.type -Description $inputProperty.description
                $validateset = $refObject.enum.value
            }
        }

        if ($null -ne $validateset) {
            $Output += "[ArgumentCompletions({0})]" -f $($validateset.foreach{ "'$_'" } -join ', ')
        }

        $Output += "`${0}," -f $ParameterName

        return $Output
    }
}

function Add-ClassDefinitionToModule {
    param(
        [parameter(mandatory, valuefrompipeline)]
        [string]
        $PulumiType,

        [parameter(mandatory)]
        $SchemaObject,

        [parameter(mandatory)]
        $RootModuleFile
    )

    process {
        write-verbose "adding class $pulumitype"
        $ModuleName = $PulumiType | Convert-PulumiNameToModuleName
        $output = @()

        $typedefinition = $SchemaObject.types[$PulumiType]

        $className = $PulumiType.Split(":")[-1]

        if ($script:classesToCreate -icontains $PulumiType) {
            return [pscustomobject]@{
                name   = $classname
                module = $PulumiType | Convert-PulumiNameToModuleName
            }
        }
        $script:classesToCreate += $PulumiType

        $Output += "class {0} {".replace("{0}", $className)

        $Output += $typedefinition.properties.Keys | Get-ClassPropertyText -TypeDefinition $typedefinition -CurrentModule $ModuleName

        $output += "}"

        $fileContent = $output -join [system.environment]::newline

        $ModuleFile = Join-Path (Split-Path $RootModuleFile) "$ModuleName.psm1"

        $fileContent | Add-Content $ModuleFile -Force

        $null = $PulumiType | Add-TypeFunctionDefinitionToModule -SchemaObject $SchemaObject -RootModuleFile $RootModuleFile

        return [pscustomobject]@{
            name   = $classname
            module = $PulumiType | Convert-PulumiNameToModuleName
        }
    }
}

function Add-FunctionDefinitionToModule {
    param(
        [parameter(mandatory, valuefrompipeline)]
        [string]
        $PulumiResource,

        [parameter(mandatory)]
        $SchemaObject,

        [parameter(mandatory)]
        $RootModuleFile
    )

    process {
        write-verbose "adding function $PulumiResource"
        $ModuleName = $PulumiResource | Convert-PulumiNameToModuleName
        $output = @()

        $resourcedefinition = $SchemaObject.resources[$PulumiResource]

        if ($null -eq $resourcedefinition.inputProperties) {
            Write-Warning "resource $PulumiResource does not have any inputProperties"
            return $null
        }

        $functionName = $PulumiResource -replace '(^|_|:|-)(.)', { $_.Groups[2].Value.ToUpper() }
        $functionAlias = ($PulumiResource -replace '-|:', '_').tolower()

        if ($script:functionsToCreate -contains $functionName) {
            return $functionName
        }
        $script:functionsToCreate += $functionName

        $Output += "function New-{0} {".replace("{0}", $functionName)
        $Output += "[Alias('$functionAlias')]"
        $Output += "param ("

        $Output += $resourcedefinition.inputProperties.Keys | Get-FunctionParameterText -TypeDefinition $resourcedefinition -CurrentModule $ModuleName

        # define pulumiid used for referencing within pulumi state
        $Output += "[parameter(mandatory,HelpMessage='The reference to call when you want to make a dependency to another resource')]"
        $Output += "[string]"
        $Output += "`$pulumiid,"

        # define resource option params
        $Output += "[parameter(HelpMessage='Specifies a list of named output properties that should be treated as secrets, which means they will be encrypted. It augments the list of values that Pulumi detects, based on secret inputs to the resource.')]"
        $Output += "[string[]]"
        $Output += "`$PulumiSecretOutputs,"

        $Output += "[parameter(HelpMessage='The aliases parameter provides a list of aliases for a resource or component resource. If youre changing the name, type, or parent path of a resource or component resource, you can add the old name to the list of aliases for a resource to ensure that existing resources will be migrated to the new name instead of being deleted and replaced with the new named resource.')]"
        $Output += "[string[]]"
        $Output += "`$PulumiAliases,"

        $Output += "[parameter(HelpMessage='The customTimeouts parameter provides a set of custom timeouts for create, update, and delete operations on a resource. These timeouts are specified using a duration string such as 5m (5 minutes), 40s (40 seconds), or 1d (1 day). Supported duration units are ns, us (or µs), ms, s, m, and h (nanoseconds, microseconds, milliseconds, seconds, minutes, and hours, respectively).')]"
        $Output += "[pulumicustomtimeouts]"
        $Output += "`$PulumiCustomTimeouts,"

        $Output += "[parameter(HelpMessage='Setting the PulumiDeleteBeforeReplace parameter to true means that Pulumi will delete the existing resource before creating its replacement. Be aware that this behavior has a cascading impact on dependencies so more resources may be replaced, which can lead to downtime. However, this option may be necessary for some resources that manage scarce resources behind the scenes, and/or resources that cannot exist side-by-side.')]"
        $Output += "[bool]"
        $Output += "`$PulumiDeleteBeforeReplace,"

        $Output += "[parameter(HelpMessage='Creates a list of explicit dependencies between resources.The DependsOn parameter  ensures that resource creation, update, and deletion operations are done in the correct order.')]"
        $Output += "[object[]]"
        $Output += "`$PulumiDependsOn,"

        $Output += "[parameter(HelpMessage='Specifies a list of properties that Pulumi will ignore when it updates existing resources. Any properties specified in this list that are also specified in the resources arguments will only be used when creating the resource.')]"
        $Output += "[string[]]"
        $Output += "`$PulumiIgnoreChanges,"

        $Output += "[parameter(HelpMessage='Imports an existing cloud resource so that Pulumi can manage it. To import a resource, first specify the PulumiImport parameter with the resources ID')]"
        $Output += "[string]"
        $Output += "`$PulumiImport = [NullString]::Value,"

        $Output += "[parameter(HelpMessage='Specifies a parent for a resource. It is used to associate children with the parents that encapsulate or are responsible for them.')]"
        $Output += "[object]"
        $Output += "`$PulumiParent = [NullString]::Value,"

        $Output += "[parameter(HelpMessage='Marks a resource as protected. A protected resource cannot be deleted directly, and it will be an error to do a Pulumi deployment which tries to delete a protected resource for any reason.')]"
        $Output += "[bool]"
        $Output += "`$PulumiProtect,"
        
        $Output += "[parameter(HelpMessage='Sets a provider for the resource. The default is to inherit this value from the parent resource, and to use the ambient provider specified by Pulumi configuration for resources without a parent.')]"
        $Output += "[object]"
        $Output += "`$PulumiProvider = [NullString]::Value,"
        $Output += "[parameter(HelpMessage='Sets a list of providers for the resource and its children. This list is combined with resource parents providers lists. If no value is provided, the providers list is identical to the parent. When determining which provider to use for a resource, the providers list is used if provider is not supplied.')]"
        $Output += "[object[]]"
        $Output += "`$PulumiProviders,"

        $Output += "[parameter(HelpMessage='Used to indicate that changes to certain properties on a resource should force a replacement of the resource instead of an in-place update. Typically users rely on the resource provider to make this decision based on whether the input property is one that the provider knows how to update in place, or if not, requires a replacement to modify. However, there are cases where users want to replace a resource on a change to an input property even if the resource provider itself doesnt believe it has to replace the resource.')]"
        $Output += "[string[]]"
        $Output += "`$PulumiReplaceOnChanges,"

        $Output += "[parameter(HelpMessage='Marks a resource to be retained. If this option is set then Pulumi will not call through to the resource providers Delete method when deleting or replacing the resource during pulumi up or pulumi destroy. As a result, the resource will not be deleted from the backing cloud provider, but will be removed from the Pulumi state.')]"
        $Output += "[bool]"
        $Output += "`$PulumiRetainOnDelete,"

        $Output += "[parameter(HelpMessage='Specifies a provider version to use when operating on a resource. This version overrides the version information inferred from the current package. This option should be used rarely.')]"
        $Output += "[string]"
        $Output += "`$PulumiProviderVersion = [NullString]::Value"
        $Output += ")"
        $Output += ""

        $Output += "process {"
        $Output += "`$resource = [pulumiresource]::new(`$pulumiid, `"$PulumiResource`")"
        $Output += ""

        $Output += "`$resource.options.additionalSecretOutputs = `$PulumiSecretOutputs"
        $Output += "`$resource.options.aliases = `$PulumiAliases"
        $Output += "`$resource.options.customTimeouts = `$PulumiCustomTimeouts"
        $Output += "`$resource.options.deleteBeforeReplace = `$PulumiDeleteBeforeReplace"
        $Output += "`$resource.options.ignoreChanges = `$PulumiIgnoreChanges"
        $Output += "`$resource.options.import = if([string]::IsNullOrEmpty(`$PulumiImport)) { [NullString]::Value } else { `$PulumiImport }"
        $Output += "`$resource.options.protect = `$PulumiProtect"
        $Output += "`$resource.options.replaceOnChanges = `$PulumiReplaceOnChanges"
        $Output += "`$resource.options.retainOnDelete = `$PulumiRetainOnDelete"
        $Output += "`$resource.options.version = if([string]::IsNullOrEmpty(`$PulumiProviderVersion)) { [NullString]::Value } else { `$PulumiProviderVersion }"
        $Output += ""


        $Output += "foreach(`$Dependency in `$DependsOn) {"
        $Output += "if(`$Dependency -is [pulumiresource]) {"
        $Output += "`$resource.options.dependson += `$Dependency.Reference()"
        $Output += "} else {"
        $Output += "`$resource.options.dependson += `$Dependency"
        $Output += "}"
        $Output += "}"

        $Output += "if(`$PulumiParent -is [pulumiresource]) {"
        $Output += "`$resource.options.parent = `$PulumiParent.Reference()"
        $Output += "} else {"
        $Output += "`$resource.options.parent = `$PulumiParent"
        $Output += "}"

        $Output += "foreach(`$provider in `$PulumiProviders) {"
        $Output += "if(`$provider -is [pulumiprovider]) {"
        $Output += "`$resource.options.providers += `$provider.Reference()"
        $Output += "} else {"
        $Output += "`$resource.options.providers += `$provider"
        $Output += "}"
        $Output += "}"

        $Output += "if(`$PulumiProvider -is [pulumiprovider]) {"
        $Output += "`$resource.options.provider = `$PulumiProvider.Reference()"
        $Output += "} else {"
        $Output += "`$resource.options.provider = `$PulumiProvider"
        $Output += "}"

        $resourcedefinition.requiredInputs.where{ -not [string]::IsNullOrEmpty($_) } | ForEach-Object {
            $Output += "`$resource.properties[`"$_`"] = `$$_"
        }

        $Output += ""

        @($resourcedefinition.inputProperties.Keys).where{ $_ -notin $resourcedefinition.requiredInputs } | ForEach-Object {
            $Output += "if(`$PSBoundParameters.Keys -icontains '$_') {"
            $Output += "`$resource.properties[`"$_`"] = `$$_"
            $Output += "}"
            $Output += ""
        }

        $Output += "`$global:pulumiresources += `$resource"
        $Output += "return `$resource"
        $Output += "}"

        $output += "}"

        $fileContent = $output -join [system.environment]::newline

        $ModuleFile = Join-Path (Split-Path $RootModuleFile) "$ModuleName.psm1"

        $fileContent | Add-Content $ModuleFile -Force

        return $functionName
    }
}

function Add-FunctionFunctionDefinitionToModule {
    param(
        [parameter(mandatory, valuefrompipeline)]
        [string]
        $PulumiFunction,

        [parameter(mandatory)]
        $SchemaObject,

        [parameter(mandatory)]
        $RootModuleFile
    )

    process {
        write-verbose "adding function $PulumiFunction"
        $ModuleName = $PulumiFunction | Convert-PulumiNameToModuleName
        $output = @()

        $functiondefinition = $SchemaObject.functions[$PulumiFunction]

        $functionName = $PulumiFunction -replace '(^[^:]*):', '$1Function:' -replace '(^|_|:|-)(.)', { $_.Groups[2].Value.ToUpper() }

        if ($script:functionsToCreate -contains $functionName) {
            return $functionName
        }
        $script:functionsToCreate += $functionName

        $Output += "function Invoke-{0} {".replace("{0}", $functionName)
        $Output += "param ("

        if ($null -ne $functiondefinition.inputs.properties) {
            $Output += $functiondefinition.inputs.properties.Keys | Get-FunctionParameterText -TypeDefinition $functiondefinition -ObjectType function -CurrentModule $ModuleName
        }

        $Output[-1] = $Output[-1].trim(",")
        $Output += ")"
        $Output += ""

        $Output += "process {"
        $Output += "`$arguments = @{}"

        $functiondefinition.inputs.required.where{ -not [string]::IsNullOrEmpty($_) } | ForEach-Object {
            $Output += "`$arguments[`"$_`"] = `$$_"
        }

        $Output += ""

        @($functiondefinition.inputs.properties.Keys).where{ $_ -notin $functiondefinition.inputs.required } | ForEach-Object {
            $Output += "if(`$PSBoundParameters.Keys -icontains '$_') {"
            $Output += "`$arguments[`"$_`"] = `$$_"
            $Output += "}"
            $Output += ""
        }

        $Output += "`$functionObject = Invoke-PulumiFunction -Name $PulumiFunction -variableName `$([guid]::NewGuid().Guid) -Arguments `$arguments"
        $Output += "return `$functionObject"
        $Output += "}"

        $output += "}"

        $fileContent = $output -join [system.environment]::newline

        $ModuleFile = Join-Path (Split-Path $RootModuleFile) "$ModuleName.psm1"

        $fileContent | Add-Content $ModuleFile -Force

        return $functionName
    }
}

function Add-TypeFunctionDefinitionToModule {
    param(
        [parameter(mandatory, valuefrompipeline)]
        [string]
        $PulumiType,

        [parameter(mandatory)]
        $SchemaObject,

        [parameter(mandatory)]
        $RootModuleFile
    )

    process {
        write-verbose "adding function $PulumiType"
        $ModuleName = $PulumiType | Convert-PulumiNameToModuleName
        $output = @()

        $typedefinition = $SchemaObject.types[$PulumiType]

        if ($null -eq $typedefinition.properties) {
            Write-Warning "resource $PulumiType does not have any inputProperties"
            return $null
        }

        $functionName = $PulumiType -replace '(^[^:]*):', '$1Type:' -replace '(^|_|:|-)(.)', { $_.Groups[2].Value.ToUpper() }

        if ($script:functionsToCreate -contains $functionName) {
            return $functionName
        }
        $script:functionsToCreate += $functionName

        $Output += "function New-{0} {".replace("{0}", $functionName)
        $Output += "param ("

        $Output += $typedefinition.properties.Keys | Get-FunctionParameterText -TypeDefinition $typedefinition -ObjectType type -CurrentModule $ModuleName

        $Output[-1] = $Output[-1].trim(",")
        $Output += ")"
        $Output += ""

        $Output += "process {"
        $Output += "return `$([{0}]`$PSBoundParameters)" -f ($PulumiType.Split(":")[-1])
        $Output += "}"

        $output += "}"

        $fileContent = $output -join [system.environment]::newline

        $ModuleFile = Join-Path (Split-Path $RootModuleFile) "$ModuleName.psm1"

        $fileContent | Add-Content $ModuleFile -Force

        return $functionName
    }
}

function New-PSPulumiModuleBundle {
    param(
        [parameter(Mandatory)]
        [string]
        $OutputDirectory,

        [parameter(Mandatory)]
        [string]
        $RootModuleName,

        [parameter()]
        [string]
        $Version = $env:GITVERSION_MAJORMINORPATCH,

        [parameter()]
        [string]
        $Prerelease = $env:GITVERSION_NUGETPRERELEASETAGV2
    )

    process {
        $pspulumimoduledef = @{ ModuleName = "PSPulumiYaml"; ModuleVersion = "0.0.3"; GUID = '909344e0-a08f-45f6-8177-80e36bb2ba58' }

        $Modules = @( $pspulumimoduledef)
        Get-ChildItem $OutputDirectory | ForEach-Object {
            $ModulePath = Join-Path $OutputDirectory $_.BaseName
            New-Item $ModulePath -ItemType Directory -Force | Out-Null
            Move-Item $_.FullName -Destination $ModulePath

            $ManifestFile = Join-Path $ModulePath "$($_.BaseName).psd1"
            $guid = ($_.BaseName | New-ModuleGuid)
            $ModuleManifestParams = @{
                Description     = 'Module containing functions required to create YAML/JSON definitions for Azure Native pulumi provider'
                Path            = $ManifestFile
                RootModule      = "$($_.BaseName).psm1"
                Author          = 'Worxspace'
                CompanyName     = 'Worxspace'
                Guid            = $guid
                ModuleVersion   = $Version
                RequiredModules = @( $pspulumimoduledef)
            }

            if ($Prerelease.Length -gt 1) {
                $ModuleManifestParams['Prerelease'] = $Prerelease
            }
            New-ModuleManifest @ModuleManifestParams

            $fullversion = $version + $Prerelease
            $Modules += @{ ModuleName = $_.BaseName; ModuleVersion = $fullversion; GUID = $guid }
        }

        $ModulePath = Join-Path $OutputDirectory $RootModuleName
        New-Item $ModulePath -ItemType Directory -Force | Out-Null
        $ModuleFile = Join-Path $ModulePath "$RootModuleName.psm1"
        New-Item $ModuleFile -ItemType File -Force | Out-Null
        $ManifestFile = Join-Path $ModulePath "$RootModuleName.psd1"
        $guid = ($RootModuleName | New-ModuleGuid)
        $ModuleManifestParams = @{
            Description     = 'Parent module containing all Azure Native modules required to create YAML/JSON definitions for pulumi'
            Path            = $ManifestFile
            RootModule      = "$RootModuleName.psm1"
            Author          = 'Worxspace'
            CompanyName     = 'Worxspace'
            Guid            = $guid
            ModuleVersion   = $Version
            RequiredModules = $Modules
            ProjectUri      = 'https://github.com/worxspace/PSPulumiYaml'
        }

        if ($Prerelease.Length -gt 1) {
            $ModuleManifestParams['Prerelease'] = $Prerelease
        }
        New-ModuleManifest @ModuleManifestParams
    }
}

function New-ModuleGuid {
    param(
        [parameter(Mandatory, ValueFromPipeline)]
        $name
    )

    process {
        $algorithm = [System.Security.Cryptography.HashAlgorithm]::Create('MD5')
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($name)
        $hash = $algorithm.ComputeHash($bytes)
        return [guid]::new($hash).Guid.ToString()
    }
}

$functionkeys = $schema.functions.Keys
$i = 0
$functionkeys | ? { $true } | ForEach-Object {
    Write-Progress -Activity "Processing functions" -Id 0 -PercentComplete ($i++ / $functionkeys.count * 100) $_
    $null = Add-FunctionFunctionDefinitionToModule -PulumiFunction $_ -SchemaObject $schema -RootModuleFile $RootModule
}

Write-Progress -Activity "Processing functions" -Id 0 -Completed

$resourcekeys = $schema.resources.Keys
$i = 0
$resourcekeys | ? { $true } | ForEach-Object {
    Write-Progress -Activity "Processing resources" -Id 0 -PercentComplete ($i++ / $resourcekeys.count * 100) $_
    $null = Add-FunctionDefinitionToModule -PulumiResource $_ -SchemaObject $schema -RootModuleFile $RootModule
}

Write-Progress -Activity "Processing resources" -Id 0 -Completed

$i = 0
$script:classesToCreate | ForEach-Object {
    Write-Progress -Activity "Processing classes" -Id 0 -PercentComplete ($i++ / $script:classesToCreate.count * 100) $_
    $null = Add-ClassDefinitionToModule -PulumiType $_ -SchemaObject $schema -RootModuleFile $RootModule
}
Write-Progress -Activity "Processing classes" -Id 0 -Completed

$settings = @{
    IncludeRules = @("PSPlaceOpenBrace", "PSUseConsistentIndentation")
    Rules        = @{
        PSPlaceOpenBrace           = @{
            Enable     = $true
            OnSameLine = $false
        }
        PSUseConsistentIndentation = @{
            Enable = $true
        }
    }
}

try {
    Import-Module PSScriptAnalyzer -ErrorAction Stop
}
catch {
    Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
}

#loop all module files
Get-ChildItem (Split-Path $RootModule) | ForEach-Object {
    $Content = (Get-Content $_.FullName -Raw)
    $newContent = 'using module @{ ModuleName = "PSPulumiYaml"; ModuleVersion = "0.0.3"; GUID = "909344e0-a08f-45f6-8177-80e36bb2ba58" }' + [System.Environment]::newline + $Content

    Invoke-Formatter -ScriptDefinition $newContent -Settings $settings | Set-Content $_.FullName -Force
}

New-PSPulumiModuleBundle -OutputDirectory $OutputDirectory -RootModuleName $RootModuleName -Version '0.0.4'
