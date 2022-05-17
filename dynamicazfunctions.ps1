# irm https://raw.githubusercontent.com/pulumi/pulumi-azure-native/master/provider/cmd/pulumi-resource-azure-native/schema.json -OutFile $PSScriptRoot/schema.json
# $schema = Get-Content ./schema.json | ConvertFrom-Json -AsHashtable

$OutputFile = "$PSScriptRoot/bin/aznativemodule.psm1"

Set-Content $OutputFile -Value '' -Force

$script:classesToCreate = @()

$script:typeswithmultiplerefs = @{}

function Convert-PulumiTypeToPowerShellType {
    param(
        [parameter(mandatory, valuefrompipeline)]
        [AllowEmptyString()]
        [string]
        $Type
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
                return "[bool]"
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
        $TypeDefinition
    )

    process {
        $Output = @()

        $inputProperty = $TypeDefinition.properties[$PropertyName]

        $propertytypestring = ""

        $type = $($inputProperty.type, $inputProperty.oneOf.type | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $arraytype = $($inputProperty.items.type, $inputProperty.items.oneOf.type | Where-Object { -not [string]::IsNullOrEmpty($_) })

        $oneOfRefs = @($inputProperty.oneOf.'$ref') + @($inputProperty.items.oneOf.'$ref') | Where-Object { -not [string]::IsNullOrEmpty($_) }

        if ($oneOfRefs.count -gt 1) {
            #TODO: bad practice fix
            $script:typeswithmultiplerefs["$className-$PropertyName"] = $oneOfRefs
            return '[object] ${0} #todo add class here' -f $propertyName
        }

        $propertytypestring = Convert-PulumiTypeToPowerShellType -Type "$type"

        write-verbose "creating class property $PropertyName with initial type $propertytypestring"

        if ($propertytypestring -eq "[object]") {
            $ref = $($inputProperty.'$ref', $inputProperty.oneOf.'$ref' | Where-Object { -not [string]::IsNullOrEmpty($_) })

            if ([string]::IsNullOrEmpty($ref)) {
                $type = $inputProperty.additionalProperties.type, $inputProperty.oneOf.additionalProperties.type, $inputProperty.additionalProperties.'$ref', $inputProperty.oneOf.additionalProperties.'$ref'
                $propertytypestring = Convert-PulumiTypeToPowerShellType -Type "$type"
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
                    $propertytypestring = "[{0}]" -f ($parts[-1] | Add-ClassDefinitionToModule -SchemaObject $SchemaObject -ModuleFile $ModuleFile)
                }
            }
        }

        if ($propertytypestring -eq "[array]") {
            $propertytypestring = "[{0}[]]" -f (Convert-PulumiTypeToPowerShellType -Type $arraytype).trim('[]')
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
                    $propertytypestring = Convert-PulumiTypeToPowerShellType -Type $refObject.type
                    $validateset = $refObject.enum.value
                }
                else {
                    $propertytypestring = "[{0}[]]" -f ($parts[-1] | Add-ClassDefinitionToModule -SchemaObject $SchemaObject -ModuleFile $ModuleFile)
                }
            }
        }
        
        if ($null -ne $inputProperty.oneOf) {
            $parts = $inputProperty.oneOf.'$ref' -split '/'
            $refObject = $schema.types[$parts[-1]]

            if ($null -ne $refObject.enum) {
                $propertytypestring = Convert-PulumiTypeToPowerShellType -Type $refObject.type
                $validateset = $refObject.enum.value
            }
        }

        if ($null -ne $validateset) {
            $Output += "[ValidateSet({0})]" -f $($validateset.foreach{ "'$_'" } -join ', ')
        }

        $Output += "$propertytypestring `${0}" -f $propertyName

        return $Output
    }
}

function Get-FunctionParameterText {
    param(
        [parameter(mandatory, valuefrompipeline)]
        [string]
        $ParameterName,

        [parameter(mandatory)]
        $TypeDefinition
    )

    process {
        $Output = @()
        $validateset = $null

        $inputProperty = $TypeDefinition.inputProperties[$ParameterName]

        $Output += "[parameter(mandatory=`${0})]" -f $($requiredInputs -contains $ParameterName)

        $propertytypestring = ""

        $type = $($inputProperty.type, $inputProperty.oneOf.type | Where-Object { -not [string]::IsNullOrEmpty($_) })
        $arraytype = $($inputProperty.items.type, $inputProperty.items.oneOf.type | Where-Object { -not [string]::IsNullOrEmpty($_) })
        if ($null -ne ($inputProperty.items.'$ref', $inputProperty.items.oneOf.'$ref' | Where-Object { -not [string]::IsNullOrEmpty($_) })) {
            $type = "[object[]]"
        }

        write-verbose "adding function parameter $ParameterName with initial type $type"

        $propertytypestring = $type | Convert-PulumiTypeToPowerShellType

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
                $propertytypestring = "[{0}]" -f ($parts[-1] | Add-ClassDefinitionToModule -SchemaObject $SchemaObject -ModuleFile $ModuleFile)
            }
        }

        if ($propertytypestring -eq "[array]") {
            write-verbose "adding function parameter $ParameterName with array type $arraytype"
            $propertytypestring = "[{0}[]]" -f ($arraytype | Convert-PulumiTypeToPowerShellType).trim('[]')
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
                $propertytypestring = "[{0}[]]" -f ($parts[-1] | Add-ClassDefinitionToModule -SchemaObject $SchemaObject -ModuleFile $ModuleFile)
            }
        }
        
        $Output += $propertytypestring

        if ($null -ne $inputProperty.oneOf) {
            $parts = $inputProperty.oneOf.'$ref' -split '/'
            $refObject = $schema.types[$parts[-1]]

            if ($null -ne $refObject.enum) {
                $propertytypestring = Convert-PulumiTypeToPowerShellType -Type $refObject.type
                $validateset = $refObject.enum.value
            }
        }

        if ($null -ne $validateset) {
            $Output += "[ValidateSet({0})]" -f $($validateset.foreach{ "'$_'" } -join ', ')
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
        $ModuleFile
    )

    process {
        write-verbose "adding class $pulumitype"
        $output = @()
        
        $typedefinition = $SchemaObject.types[$PulumiType]
        
        $className = ($PulumiType -replace '-|:').tolower()
        
        if ($script:classesToCreate -contains $classname) {
            return $classname
        }
        $script:classesToCreate += $classname

        $Output += "class {0} {".replace("{0}", $className)

        $Output += $typedefinition.properties.Keys | Get-ClassPropertyText -TypeDefinition $typedefinition

        $output += "}"

        $fileContent = $output -join [system.environment]::newline

        $fileContent | Add-Content $ModuleFile -Force

        return $className
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
        $ModuleFile
    )

    process {
        write-verbose "adding function $PulumiResource"
        $output = @()
        
        $resourcedefinition = $SchemaObject.resources[$PulumiResource]
        
        if($null -eq $resourcedefinition.inputProperties) {
            Write-Warning "resource $PulumiResource does not have any inputProperties"
            return $null
        }

        $functionName = ($PulumiResource -replace '-|:', '_').tolower()

        $Output += "function {0} {".replace("{0}", $functionName)
        $Output += "param ("

        $Output += $resourcedefinition.inputProperties.Keys | Get-FunctionParameterText -TypeDefinition $resourcedefinition

        $Output += "[parameter(mandatory)]"
        $Output += "[string]"
        $Output += "`$pulumiid"
        $Output += ")"
        $Output += ""

        $Output += "process {"
        $Output += "`$resource = [pulumiresource]::new(`$pulumiid, `"$PulumiResource`")"
        $Output += ""

        $resourcedefinition.requiredInputs.where{-not [string]::IsNullOrEmpty($_)} | ForEach-Object {
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

        $fileContent | Add-Content $ModuleFile -Force

        return $functionName
    }
}

$resourcekeys = $schema.resources.Keys
$i = 0
$resourcekeys | ForEach-Object {
    Write-Progress -Activity "Processing resources" -Id 0 -PercentComplete ($i++ / $resourcekeys.count * 100) $_
    $null = Add-FunctionDefinitionToModule -PulumiResource $_ -SchemaObject $schema -ModuleFile $OutputFile
}

Write-Progress -Activity "Processing resources" -Id 0 -Completed

$i = 0
$script:classesToCreate | ForEach-Object {
    Write-Progress -Activity "Processing classes" -Id 0 -PercentComplete ($i++ / $script:classesToCreate.count * 100) $_
    $null = Add-ClassDefinitionToModule -PulumiType $_ -SchemaObject $schema -ModuleFile $OutputFile
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

Invoke-Formatter -ScriptDefinition (Get-Content $OutputFile -Raw) -Settings $settings | Set-Content $OutputFile -Force

