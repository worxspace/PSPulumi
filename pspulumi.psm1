class pulumiprogram {
    [pulumiresource[]] $resources

    [pscustomobject[]] $variables

    [pscustomobject[]] $outputs

    pulumiprogram () {
        $this.resources = @()
        $this.variables = @()
        $this.outputs = @()
    }

    [string] Execute() {
        $output = [pscustomobject]@{
            resources = @{}
        }

        $this.resources | % { $output.resources[$_.pspuluminame] = $_ | Select -property @{n = "type"; e = { $_.pspulumitype } }, properties }

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

    $script:resources += $resource
    return $resource
}

function pulumi ([scriptblock]$scriptblock) {
    $script:resources = @()

    $null = $scriptblock.invoke()

    $program = [pulumiprogram]::new()

    $program.resources += $script:resources

    $program.Execute()
}