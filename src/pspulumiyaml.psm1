class pulumiprogram {
    [pulumiresource[]] $resources

    [hashtable] $variables

    [hashtable] $outputs

    pulumiprogram () {
        $this.resources = @()
        $this.variables = @{}
        $this.outputs = @{}
    }

    [string] Execute() {
        $output = [pscustomobject]@{
            resources = @{}
            variables = $this.variables
            outputs   = $this.outputs
        }

        foreach($resource in $this.resources){
            $output.resources[$resource.pspuluminame] = @{
                type = $resource.pspulumitype
                properties = $resource.properties
                options = @{
                    dependson = $resource.dependson
                }
            }
        }

        return $output | ConvertTo-Json -Depth 99
    }
}

class pulumiresource {
    hidden [string] $pspuluminame
    hidden [string] $pspulumitype
    [hashtable] $properties = @{}
    [string[]] $dependson

    pulumiresource($name, $type) {
        $this.pspuluminame = $name
        $this.pspulumitype = $type
    }

    [string] reference ([string]$PropertyName) {
        return "`${{0}.{1}}".Replace('{0}', $this.pspuluminame).Replace('{1}', $PropertyName)
    }

    [string] reference () {
        return "`${{0}}".Replace('{0}', $this.pspuluminame)
    }
}

function New-PulumiGenericResource {
    [Alias("pulumi_generic_resource")]
    param (
        [parameter(mandatory = $true)]
        [string]
        $pulumiid,

        [parameter(mandatory = $true)]
        [string]
        $type,

        [parameter(mandatory = $true)]
        [hashtable]
        $properties
    )

    $resource = [pulumiresource]::new($pulumiid, $type)

    $resource.properties = $properties

    $global:pulumiresources += $resource
    return $resource
}

function New-PulumiAsset {
    [Alias("pulumi_asset")]
    param (
        [parameter(mandatory = $true)]
        [ValidateSet("String", "File", "Remote")]
        [string]
        $Type,

        [parameter(mandatory = $true)]
        [string]
        $Value
    )

    return @{"Fn::$($Type)Asset" = $Value }
}

function New-PulumiRemoteAsset {
    [Alias("pulumi_remote_asset")]
    param (
        [parameter(mandatory = $true)]
        [string]
        $Value
    )

    return (pulumi_asset String $Value)
}

function New-PulumiFileAsset {
    [Alias("pulumi_file_asset")]
    param (
        [parameter(mandatory = $true)]
        [string]
        $Value
    )

    return (pulumi_asset File $Value)
}

function New-PulumiStringAsset {
    [Alias("pulumi_string_asset")]
    param (
        [parameter(mandatory = $true)]
        [string]
        $Value
    )

    return (pulumi_asset String $Value)
}

function New-PulumiArchive {
    [Alias("pulumi_archive")]
    param (
        [parameter(mandatory = $true)]
        [ValidateSet("Asset", "File", "Remote")]
        [string]
        $Type,

        [parameter(mandatory = $true)]
        $Value
    )

    return @{"Fn::$($Type)Archive" = $Value }
}

function New-PulumiRemoteArchive {
    [Alias("pulumi_remote_archive")]
    param (
        [parameter(mandatory = $true)]
        [string]
        $Value
    )

    return (pulumi_archive Remote $Value)
}

function New-PulumiFileArchive {
    [Alias("pulumi_file_archive")]
    param (
        [parameter(mandatory = $true)]
        [string]
        $Value
    )

    return (pulumi_archive File $Value)
}

function New-PulumiAssetArchive {
    [Alias("pulumi_asset_archive")]
    param (
        [parameter(mandatory = $true)]
        [hashtable]
        $Value
    )

    return (pulumi_archive Asset $Value)
}

function New-PulumiOutput {
    [Alias("pulumi_output")]
    param (
        [parameter(mandatory = $true)]
        [string]
        $Name,

        [parameter(mandatory = $true)]
        [string]
        $Value
    )

    $global:outputs += @{ $Name = $value }
}

class pulumi_variable {
    [string] $name

    [object] $value

    [string] reference ([string]$PropertyName) {
        return "`${{0}{2}{1}}".Replace('{0}', $this.name).Replace('{1}', $PropertyName).replace("{2}", $(if ($PropertyName[0] -ne '[') { '.' }))
    }

    pulumi_variable ([string]$name, [object]$value) {
        $this.name = $name
        $this.value = $value
    }
}

function Invoke-PulumiFunction {
    [Alias("pulumi_function")]
    param (
        [parameter(mandatory)]
        [string]
        $name,

        [parameter(mandatory)]
        [hashtable]
        $arguments,

        [parameter()]
        [string]
        $returnproperty,

        [parameter(mandatory)]
        [string]
        $variablename
    )

    $function = @{
        "Fn::Invoke" = @{
            Function  = $name
            Arguments = $arguments
        }
    }

    if ($PSBoundParameters.ContainsKey("returnproperty")) {
        $function["Fn::Invoke"]["return"] = $returnproperty
    }

    $global:variables += @{ $variablename = $function }
    return [pulumi_variable]::new($variablename, $value)
}

function New-PulumiYamlFile ([scriptblock]$scriptblock) {
    [Alias("pulumi_configuration")]

    $global:pulumiresources = @()
    $global:outputs = @{}
    $global:variables = @{}

    $null = $scriptblock.invoke()

    $program = [pulumiprogram]::new()

    $program.resources += $global:pulumiresources
    $program.outputs += $global:outputs
    $program.variables += $global:variables

    $program.Execute()
}
