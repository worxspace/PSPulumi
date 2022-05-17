class pulumiprogram {
    [pulumiresource[]] $resources

    [pscustomobject[]] $variables

    [hashtable] $outputs = @{}

    pulumiprogram () {
        $this.resources = @()
        $this.variables = @()
        $this.outputs = @{}
    }

    [string] Execute() {
        $output = [pscustomobject]@{
            resources = @{}
            variables = @{}
            outputs   = $this.outputs
        }

        $this.resources.foreach{ $output.resources[$_.pspuluminame] = $_ | Select-Object -property @{n = "type"; e = { $_.pspulumitype } }, properties }

        return $output | ConvertTo-Json -Depth 99
    }
}

class pulumiresource {
    hidden [string] $pspuluminame
    hidden [string] $pspulumitype
    [hashtable] $properties = @{}

    pulumiresource($name, $type) {
        $this.pspuluminame = $name
        $this.pspulumitype = $type
    }

    [string] reference ([string]$PropertyName) {
        return "`${{0}.{1}}".Replace('{0}', $this.pspuluminame).Replace('{1}', $PropertyName)
    }
}

function pulumi_generic_resource {
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

function pulumi_asset {
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

function pulumi_remote_asset {
    param (
        [parameter(mandatory = $true)]
        [string]
        $Value
    )

    return (pulumi_asset String $Value)
}

function pulumi_file_asset {
    param (
        [parameter(mandatory = $true)]
        [string]
        $Value
    )

    return (pulumi_asset File $Value)
}

function pulumi_string_asset {
    param (
        [parameter(mandatory = $true)]
        [string]
        $Value
    )

    return (pulumi_asset String $Value)
}

function pulumi_archive {
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

function pulumi_remote_archive {
    param (
        [parameter(mandatory = $true)]
        [string]
        $Value
    )

    return (pulumi_archive Remote $Value)
}

function pulumi_file_archive {
    param (
        [parameter(mandatory = $true)]
        [string]
        $Value
    )

    return (pulumi_archive File $Value)
}

function pulumi_asset_archive {
    param (
        [parameter(mandatory = $true)]
        [hashtable]
        $Value
    )

    return (pulumi_archive Asset $Value)
}

function pulumi_output {
    param (
        [parameter(mandatory = $true)]
        [string]
        $Value
    )

    $global:outputs += @{ $Name = $value }
}

function pulumi ([scriptblock]$scriptblock) {
    $global:pulumiresources = @()
    $global:outputs = @{}
    $global:functions = @()

    $null = $scriptblock.invoke()

    $program = [pulumiprogram]::new()

    $program.resources += $global:pulumiresources
    $program.outputs += $global:outputs

    $program.Execute()
}
