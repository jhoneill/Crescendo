# Module created by Microsoft.PowerShell.Crescendo
class PowerShellCustomFunctionAttribute : System.Attribute {
    [bool]$RequiresElevation
    [string]$Source
    PowerShellCustomFunctionAttribute() { $this.RequiresElevation = $false; $this.Source = "Microsoft.PowerShell.Crescendo" }
    PowerShellCustomFunctionAttribute([bool]$rElevation) {
        $this.RequiresElevation = $rElevation
        $this.Source = "Microsoft.PowerShell.Crescendo"
    }
}

function tfVersionJsonToObject {
  $tfver = $input | ConvertFrom-Json -AsHashtable
  $providers =  $tfver.provider_selections.Keys | ForEach-Object { [pscustomObject]@{Provider=$_;Version=$tfver.provider_selections[$_]}}
  [Pscustomobject][ordered]@{
                    Platform  = $tfver.platform
                    Version   = $tfver.terraform_version
                    OutDated  = $tfver.terraform_outdated
                    Providers = $Providers }    | Add-Member -TypeName TerraformVersion -PassThru
 }

function NewArgument {
    param  ($value, $param)
    if ($value -is [switch]) {
        if ($value.IsPresent) {
            if ($param.OriginalName)        {  $param.OriginalName }
        }
        elseif ($param.DefaultMissingValue) {  $param.DefaultMissingValue }
    }
    elseif (    $param.NoGap -and
                   $value -match "\s" )     { "$($param.OriginalName)""$value"""}
    elseif (    $param.NoGap )              { "$($param.OriginalName)$value"}

    else {
        if (    $param.OriginalName)        {  $param.OriginalName }
        $value
    }
}

function tfPlanJsonToObject {
    $result     = $input | convertfrom-json
    $errResults = $result | Where-Object {$_.type  -eq "diagnostic"} | ForEach-Object diagnostic |
            Select-Object @{n='Severity';e={$_.severity.toUpper()}}, @{n="Summary";e='Summary'},
                          @{n='Context'; e={if (-not $_.range) {""} else {$_.range.filename + " @ Line "  + $_.range.start.line + ": " +
                            ($_.snippet.code -replace "(?<=^.{$($_.snippet.highlight_end_offset)})",$PSStyle.Reset -replace "(?<=^.{$($_.snippet.highlight_start_offset)})",$PSStyle.underline)}}} |
                Add-Member -TypeName TerraformError -PassThru
    if ($errResults) {$errResults}
    else { $result | Where-Object {$_.type -eq 'planned_change'} |
            Select-Object @{n='Action';  e={$_.change.action}},
                        @{n='Resource';e={$_.change.resource.resource}}  |
                Add-Member -TypeName TerraformChange -PassThru
    }
}

function rendertfgraph {
    param (
        #Destination
        $Path,
        #GraphViz markup
        $GVCode,
        #Open the result
        [switch]$ShowGraph
    )
    if ($Path -match '\.gv$|\.gxl$|.dot$') {
        $GVCode | Out-File -Encoding utf8 -FilePath $Path
        if ($ShowGraph) {Write-Warning "Show ignored when outputting Graphviz files."}
    }
    elseif ($Path -notmatch '\.(jpg|png|gif|pdf|svg)$') {
        throw "Unsupported file extension. Please use '.jpg', '.png', '.gif', '.svg', '.pdf', '.dot', '.gxl' or '.gv'"
    }
    elseif (-not (Get-Command Export-PSGraph -ErrorAction SilentlyContinue)) {
        throw "To Convert to one of these formats you need to install the PSGraph module"
    }
    else {
        $GVCode  | Export-PSGraph -DestinationPath $Path -OutputFormat $Matches[1] -ShowGraph:$ShowGraph
    }
 }

function tfFormatCheckOK {
    param ($Ignore)
    return (!$lastExitCode)
}

function tfFormatResults {
    param ($ChangedFiles)
    if     ($ChangedFiles.count -gt 1 ) {Write-Host "$($ChangedFiles.count) files changed:" -ForegroundColor Green}
    elseif ($ChangedFiles.count -eq 1 ) {Write-Host "1 file changed:" -ForegroundColor Green}
    else                                {Write-Host "No files changed." -ForegroundColor Green}
    $changedFiles
}

function tfStateJsonToObject {
    param   (
        [parameter(ValueFromPipeline=$true)]
        $Json,
        $Address = '*'
    )
    begin   {$text = ''}
    process {$text += $Json}
    end     {
        #recursively expand the resoruces in each module.
        function expandTfModule {
            param (
                [parameter(ValueFromPipeline=$true)]
                $module ,
                $tfVersion
            )
            begin {
                $defaultPropertySet = ([System.Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet', [string[]]@('parent', 'provider_Name', 'type', 'name')))
            }
            process {
                write-host "."
                if ($module.address) {$path = $module.address} else {$path = "/" }# place holder - this probably isn't correct
                if ($module.resources) {
                    $module.resources |
                        Add-Member -PassThru -MemberType MemberSet -Name PSStandardMembers -Value $defaultPropertySet|
                        Add-Member -PassThru -NotePropertyName 'Parent'           -NotePropertyValue $path |
                        Add-Member -PassThru -NotePropertyName 'TerraformVersion' -NotePropertyValue $tfVersion |
                        Add-Member -PassThru -TypeName TerraformResource
                }
                if ( $module.child_modules) {$module.child_modules| expandTfModule -tfversion $tfVersion   }
            }
        }

        $result = $text | ConvertFrom-Json
        $result.values.root_module | expandTfModule -tfVersion $result.terraform_version | Where-Object -Property address -Like $Address
    }
}

function Get-TerraformVersion {
<#
  .SYNOPSIS
    Gets the Terraform Version
  .DESCRIPTION
    Calls terraform version and converts the result into an object
#>
  [CmdletBinding()]
  [PowerShellCustomFunctionAttribute(RequiresElevation=$false)]
  [Alias('Get-TFVersion','tfVersion')]

  param   (  )
  begin   {
    if ( -not (Get-Command -ErrorAction Ignore terraform)) {throw  "Cannot find executable 'terraform'"}
    $parameterMap   = @{   }
    $outputHandlers = @{
        Default = @{ StreamOutput = $True; Handler = 'tfVersionJsonToObject' }
    }
  }
  process {
    if ($psboundParameters["Debug"]) { Wait-Debugger }

    #region add those parameters which have default values, and absent switches, perform any value translations required
    $boundParameters        =  $PSBoundParameters
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].containskey('DefaultValue') -and -not $PSBoundParameters.ContainsKey($_)} |
                                 ForEach-Object {$boundParameters[$_] = Get-Variable $_ -ValueOnly }
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].ParameterType -eq "switch"  -and -not $PSBoundParameters.ContainsKey($_)} |
                                 ForEach-Object {$boundParameters[$_] = [switch]::new($false) }
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].containskey('ValueMap')     -and $boundParameters.ContainsKey($_)} |
                                 ForEach-Object { $boundParameters[$_] = $parameterMap[$_].ValueMap[$boundParameters[$_]]}
    #endregion

    #region build the list of command line argumnets
    $commandArgs            = @()
    # now the original command elements may be added

    $commandArgs += 'version'
    $commandArgs += '-json'

    $commandArgs = $commandArgs | Where-Object {$_ -ne $null} # strip only nulls
    #endregion

    #region invoke the command with arguments and handle results
    if ($boundParameters["Debug"])   {Wait-Debugger}

    $handlerInfo = $outputHandlers[$PSCmdlet.ParameterSetName]
    if (-not  $handlerInfo ) {$handlerInfo = $outputHandlers["Default"]} # Guaranteed to be present
    $handler     = $handlerInfo.Handler
    Write-Verbose -Message ("& ""terraform"" $commandArgs")
    if ( $handlerInfo.StreamOutput ) { & "terraform" $commandArgs | & $handler}
    else {
        $result = & "terraform" $commandArgs
        & $handler $result  # handler must be able to process an empty result
    }
    #endregion
  }
}

function New-TerraformPlan {
<#
  .SYNOPSIS
    Builds a new terraform plan from the current configuration
  .DESCRIPTION
    Calls terraform plan, optionally with -Destroy and -Out <file> options, returns planned steps as objects.
#>
  [CmdletBinding()]
  [PowerShellCustomFunctionAttribute(RequiresElevation=$false)]
  [Alias('New-TFPlan','tfPlan')]

  param   (
    [object]$Directory,
    [Parameter(Position=0)]
    [String]$OutFile,
    [Switch]$Destroy
  )
  begin   {
    if ( -not (Get-Command -ErrorAction Ignore terraform)) {throw  "Cannot find executable 'terraform'"}
    $parameterMap   = @{
        Directory = @{
            OriginalName        = '-chdir='
            OriginalPosition    = '0'
            ParameterType       = 'object'
            ApplyToExecutable   =  $True
            NoGap               =  $True
        }
        OutFile = @{
            OriginalName        = '-out'
            OriginalPosition    = '0'
            ParameterType       = 'String'
            ApplyToExecutable   =  $False
            NoGap               =  $False
        }
        Destroy = @{
            OriginalName        = '-destroy'
            OriginalPosition    = '1'
            ParameterType       = 'Switch'
            ApplyToExecutable   =  $False
            NoGap               =  $False
        }
   }
    $outputHandlers = @{
        Default = @{ StreamOutput = $True; Handler = 'tfPlanJsonToObject' }
    }
  }
  process {
    if ($psboundParameters["Debug"]) { Wait-Debugger }

    #region add those parameters which have default values, and absent switches, perform any value translations required
    $boundParameters        =  $PSBoundParameters
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].containskey('DefaultValue') -and -not $PSBoundParameters.ContainsKey($_)} |
                                 ForEach-Object {$boundParameters[$_] = Get-Variable $_ -ValueOnly }
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].ParameterType -eq "switch"  -and -not $PSBoundParameters.ContainsKey($_)} |
                                 ForEach-Object {$boundParameters[$_] = [switch]::new($false) }
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].containskey('ValueMap')     -and $boundParameters.ContainsKey($_)} |
                                 ForEach-Object { $boundParameters[$_] = $parameterMap[$_].ValueMap[$boundParameters[$_]]}
    #endregion

    #region build the list of command line argumnets
    $commandArgs            = @()
    # now the original command elements may be added
    # add any arguments which apply to the executable and must be before the original command elements, then the original elements if any then trailing arguments.
    $boundParameters.Keys | Where-Object {     $parameterMap[$_].ApplyToExecutable} |
        Sort-Object {$parameterMap[$_].OriginalPosition} | Foreach-Object { # take those parameters which apply to the executable
        $commandArgs += NewArgument $boundParameters[$_]  $parameterMap[$_]  #only have parameters where $parameterMap[that name].Apply to executable is true, so this always returns a value
    }
    $commandArgs += 'plan'
    $commandArgs += '-json'
    # Add parameters which don't apply to the executable - use a negative original position to say this only in the wrapper, not passed to the command.
    $boundParameters.Keys | Where-Object {[int]$parameterMap[$_].OriginalPosition -ge 0 -and
                                          -not $parameterMap[$_].ApplyToExecutable} |
        Sort-Object {$parameterMap[$_].OriginalPosition} | Foreach-Object {
            $commandArgs += NewArgument $boundParameters[$_]  $parameterMap[$_]  #only have parameters where $parameterMap[that name].Original postion >=, so this always returns a value
    }

    $commandArgs = $commandArgs | Where-Object {$_ -ne $null} # strip only nulls
    #endregion

    #region invoke the command with arguments and handle results
    if ($boundParameters["Debug"])   {Wait-Debugger}

    $handlerInfo = $outputHandlers[$PSCmdlet.ParameterSetName]
    if (-not  $handlerInfo ) {$handlerInfo = $outputHandlers["Default"]} # Guaranteed to be present
    $handler     = $handlerInfo.Handler
    Write-Verbose -Message ("& ""terraform"" $commandArgs")
    if ( $handlerInfo.StreamOutput ) { & "terraform" $commandArgs | & $handler}
    else {
        $result = & "terraform" $commandArgs
        & $handler $result  # handler must be able to process an empty result
    }
    #endregion
  }
}

function New-TerraformGraph {
<#
  .SYNOPSIS
    Draws a graph of the resources in the current configuration
  .DESCRIPTION
    Calls terraform graph, if the PSGraphModule is present converts the graphviz output to something viewable
  .PARAMETER Path
    Path for the outputfile
#>
  [CmdletBinding()]
  [PowerShellCustomFunctionAttribute(RequiresElevation=$false)]
  [Alias('New-TFGraph','tfGraph')]

  param   (
    [Parameter(Position=0)]
    [String]$Path,
    [Parameter(Position=1)]
    [switch]$ShowGraph
  )
  begin   {
    if ( -not (Get-Command -ErrorAction Ignore terraform)) {throw  "Cannot find executable 'terraform'"}
    $parameterMap   = @{
        Path = @{
            OriginalName        = ''
            OriginalPosition    = '-1'
            ParameterType       = 'String'
            ApplyToExecutable   =  $False
            NoGap               =  $False
        }
        ShowGraph = @{
            OriginalName        = ''
            OriginalPosition    = '-1'
            ParameterType       = 'switch'
            ApplyToExecutable   =  $False
            NoGap               =  $False
        }
   }
    $outputHandlers = @{
        Default = @{ StreamOutput = $True; Handler = { rendertfgraph -Path $Path -ShowGraph:$ShowGraph $input } }
    }
  }
  process {
    if ($psboundParameters["Debug"]) { Wait-Debugger }

    #region add those parameters which have default values, and absent switches, perform any value translations required
    $boundParameters        =  $PSBoundParameters
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].containskey('DefaultValue') -and -not $PSBoundParameters.ContainsKey($_)} |
                                 ForEach-Object {$boundParameters[$_] = Get-Variable $_ -ValueOnly }
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].ParameterType -eq "switch"  -and -not $PSBoundParameters.ContainsKey($_)} |
                                 ForEach-Object {$boundParameters[$_] = [switch]::new($false) }
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].containskey('ValueMap')     -and $boundParameters.ContainsKey($_)} |
                                 ForEach-Object { $boundParameters[$_] = $parameterMap[$_].ValueMap[$boundParameters[$_]]}
    #endregion

    #region build the list of command line argumnets
    $commandArgs            = @()
    # now the original command elements may be added

    $commandArgs += 'graph'

    $commandArgs = $commandArgs | Where-Object {$_ -ne $null} # strip only nulls
    #endregion

    #region invoke the command with arguments and handle results
    if ($boundParameters["Debug"])   {Wait-Debugger}

    $handlerInfo = $outputHandlers[$PSCmdlet.ParameterSetName]
    if (-not  $handlerInfo ) {$handlerInfo = $outputHandlers["Default"]} # Guaranteed to be present
    $handler     = $handlerInfo.Handler
    Write-Verbose -Message ("& ""terraform"" $commandArgs")
    if ( $handlerInfo.StreamOutput ) { & "terraform" $commandArgs | & $handler}
    else {
        $result = & "terraform" $commandArgs
        & $handler $result  # handler must be able to process an empty result
    }
    #endregion
  }
}

function Test-TerraformFormat {
<#
  .SYNOPSIS
    Calls terraform fmt -check and returns true or false depending on whether the format check passed
  .DESCRIPTION
    See help for terraform
#>
  [CmdletBinding()]
  [PowerShellCustomFunctionAttribute(RequiresElevation=$false)]

  param   (
    [Alias('Recursive')]
    [Parameter(Position=0)]
    [switch]$Recurse
  )
  begin   {
    if ( -not (Get-Command -ErrorAction Ignore terraform)) {throw  "Cannot find executable 'terraform'"}
    $parameterMap   = @{
        Recurse = @{
            OriginalName        = '-recursive'
            OriginalPosition    = '2'
            ParameterType       = 'switch'
            ApplyToExecutable   =  $False
            NoGap               =  $False
        }
   }
    $outputHandlers = @{
        Default = @{ StreamOutput = $False; Handler = 'tfFormatCheckOK' }
    }
  }
  process {
    if ($psboundParameters["Debug"]) { Wait-Debugger }

    #region add those parameters which have default values, and absent switches, perform any value translations required
    $boundParameters        =  $PSBoundParameters
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].containskey('DefaultValue') -and -not $PSBoundParameters.ContainsKey($_)} |
                                 ForEach-Object {$boundParameters[$_] = Get-Variable $_ -ValueOnly }
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].ParameterType -eq "switch"  -and -not $PSBoundParameters.ContainsKey($_)} |
                                 ForEach-Object {$boundParameters[$_] = [switch]::new($false) }
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].containskey('ValueMap')     -and $boundParameters.ContainsKey($_)} |
                                 ForEach-Object { $boundParameters[$_] = $parameterMap[$_].ValueMap[$boundParameters[$_]]}
    #endregion

    #region build the list of command line argumnets
    $commandArgs            = @()
    # now the original command elements may be added

    $commandArgs += 'fmt'
    $commandArgs += '-check'
    # Add parameters which don't apply to the executable - use a negative original position to say this only in the wrapper, not passed to the command.
    $boundParameters.Keys | Where-Object {[int]$parameterMap[$_].OriginalPosition -ge 0 -and
                                          -not $parameterMap[$_].ApplyToExecutable} |
        Sort-Object {$parameterMap[$_].OriginalPosition} | Foreach-Object {
            $commandArgs += NewArgument $boundParameters[$_]  $parameterMap[$_]  #only have parameters where $parameterMap[that name].Original postion >=, so this always returns a value
    }

    $commandArgs = $commandArgs | Where-Object {$_ -ne $null} # strip only nulls
    #endregion

    #region invoke the command with arguments and handle results
    if ($boundParameters["Debug"])   {Wait-Debugger}

    $handlerInfo = $outputHandlers[$PSCmdlet.ParameterSetName]
    if (-not  $handlerInfo ) {$handlerInfo = $outputHandlers["Default"]} # Guaranteed to be present
    $handler     = $handlerInfo.Handler
    Write-Verbose -Message ("& ""terraform"" $commandArgs")
    if ( $handlerInfo.StreamOutput ) { & "terraform" $commandArgs | & $handler}
    else {
        $result = & "terraform" $commandArgs
        & $handler $result  # handler must be able to process an empty result
    }
    #endregion
  }
}

function Format-TerraformConfiguration {
<#
  .SYNOPSIS
    Calls terraform fmt and formats files 
  .DESCRIPTION
    See help for terraform
#>
  [CmdletBinding()]
  [PowerShellCustomFunctionAttribute(RequiresElevation=$false)]
  [Alias('Format-TF','tffmt')]

  param   (
    [Alias('Recursive')]
    [Parameter(Position=0)]
    [switch]$Recurse
  )
  begin   {
    if ( -not (Get-Command -ErrorAction Ignore terraform)) {throw  "Cannot find executable 'terraform'"}
    $parameterMap   = @{
        Recurse = @{
            OriginalName        = '-recursive'
            OriginalPosition    = '2'
            ParameterType       = 'switch'
            ApplyToExecutable   =  $False
            NoGap               =  $False
        }
   }
    $outputHandlers = @{
        Default = @{ StreamOutput = $False; Handler = 'tfFormatResults' }
    }
  }
  process {
    if ($psboundParameters["Debug"]) { Wait-Debugger }

    #region add those parameters which have default values, and absent switches, perform any value translations required
    $boundParameters        =  $PSBoundParameters
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].containskey('DefaultValue') -and -not $PSBoundParameters.ContainsKey($_)} |
                                 ForEach-Object {$boundParameters[$_] = Get-Variable $_ -ValueOnly }
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].ParameterType -eq "switch"  -and -not $PSBoundParameters.ContainsKey($_)} |
                                 ForEach-Object {$boundParameters[$_] = [switch]::new($false) }
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].containskey('ValueMap')     -and $boundParameters.ContainsKey($_)} |
                                 ForEach-Object { $boundParameters[$_] = $parameterMap[$_].ValueMap[$boundParameters[$_]]}
    #endregion

    #region build the list of command line argumnets
    $commandArgs            = @()
    # now the original command elements may be added

    $commandArgs += 'fmt'
    # Add parameters which don't apply to the executable - use a negative original position to say this only in the wrapper, not passed to the command.
    $boundParameters.Keys | Where-Object {[int]$parameterMap[$_].OriginalPosition -ge 0 -and
                                          -not $parameterMap[$_].ApplyToExecutable} |
        Sort-Object {$parameterMap[$_].OriginalPosition} | Foreach-Object {
            $commandArgs += NewArgument $boundParameters[$_]  $parameterMap[$_]  #only have parameters where $parameterMap[that name].Original postion >=, so this always returns a value
    }

    $commandArgs = $commandArgs | Where-Object {$_ -ne $null} # strip only nulls
    #endregion

    #region invoke the command with arguments and handle results
    if ($boundParameters["Debug"])   {Wait-Debugger}

    $handlerInfo = $outputHandlers[$PSCmdlet.ParameterSetName]
    if (-not  $handlerInfo ) {$handlerInfo = $outputHandlers["Default"]} # Guaranteed to be present
    $handler     = $handlerInfo.Handler
    Write-Verbose -Message ("& ""terraform"" $commandArgs")
    if ( $handlerInfo.StreamOutput ) { & "terraform" $commandArgs | & $handler}
    else {
        $result = & "terraform" $commandArgs
        & $handler $result  # handler must be able to process an empty result
    }
    #endregion
  }
}

function Get-TerraformState {
<#
  .SYNOPSIS
    Calls terraform state and converts the results to objects
  .DESCRIPTION
    See help for terraform
  .PARAMETER Address
    If specified, will filter the results to the selected address(es). Wildcards are allowed. 
#>
  [CmdletBinding()]
  [PowerShellCustomFunctionAttribute(RequiresElevation=$false)]
  [Alias('Get-TFState','tfshow')]

  param   (
    [PSDefaultValue(Value='*')]
    [String]$Address="*"
  )
  begin   {
    if ( -not (Get-Command -ErrorAction Ignore terraform)) {throw  "Cannot find executable 'terraform'"}
    $parameterMap   = @{
        Address = @{
            OriginalName        = ''
            OriginalPosition    = '-1'
            ParameterType       = 'String'
            ApplyToExecutable   =  $False
            NoGap               =  $False
            DefaultValue        = '*'
        }
   }
    $outputHandlers = @{
        Default = @{ StreamOutput = $True; Handler = { tfStateJsonToObject -Address $Address $input } }
    }
  }
  process {
    if ($psboundParameters["Debug"]) { Wait-Debugger }

    #region add those parameters which have default values, and absent switches, perform any value translations required
    $boundParameters        =  $PSBoundParameters
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].containskey('DefaultValue') -and -not $PSBoundParameters.ContainsKey($_)} |
                                 ForEach-Object {$boundParameters[$_] = Get-Variable $_ -ValueOnly }
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].ParameterType -eq "switch"  -and -not $PSBoundParameters.ContainsKey($_)} |
                                 ForEach-Object {$boundParameters[$_] = [switch]::new($false) }
    $parameterMap.Keys      |  Where-Object {$parameterMap[$_].containskey('ValueMap')     -and $boundParameters.ContainsKey($_)} |
                                 ForEach-Object { $boundParameters[$_] = $parameterMap[$_].ValueMap[$boundParameters[$_]]}
    #endregion

    #region build the list of command line argumnets
    $commandArgs            = @()
    # now the original command elements may be added

    $commandArgs += 'show'
    $commandArgs += '-json'

    $commandArgs = $commandArgs | Where-Object {$_ -ne $null} # strip only nulls
    #endregion

    #region invoke the command with arguments and handle results
    if ($boundParameters["Debug"])   {Wait-Debugger}

    $handlerInfo = $outputHandlers[$PSCmdlet.ParameterSetName]
    if (-not  $handlerInfo ) {$handlerInfo = $outputHandlers["Default"]} # Guaranteed to be present
    $handler     = $handlerInfo.Handler
    Write-Verbose -Message ("& ""terraform"" $commandArgs")
    if ( $handlerInfo.StreamOutput ) { & "terraform" $commandArgs | & $handler}
    else {
        $result = & "terraform" $commandArgs
        & $handler $result  # handler must be able to process an empty result
    }
    #endregion
  }
}

