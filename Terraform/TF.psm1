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
  $providers =  $tfver.provider_selections.Keys | ForEach-Object { [pscustomObject]@{Provider=$_;Version=$tv.provider_selections[$_]}}
  [Pscustomobject][ordered]@{
                    Platform  = $tfver.platform
                    Version   = $tfver.terraform_version
                    OutDated  = $tfver.terraform_outdated
                    Providers = $Providers }    | Add-Member -TypeName TerraformVersion -PassThru
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
    # check for the application and throw if it cannot be found
    if ( -not (Get-Command -ErrorAction Ignore terraform)) {
               throw  "Cannot find executable 'terraform'"
    }
    $parameterMap   = @{   }
    $outputHandlers = @{
        Default = @{ StreamOutput = $True; Handler = 'tfVersionJsonToObject' }
    }
  }
  process {
    if ($psboundParameters["Debug"]) { Wait-Debugger }

    function NewArgument {
        param  ($value, $param)
            if ($value -is [switch]) {
                 if ($value.IsPresent) {
                     if ($param.OriginalName)        { $param.OriginalName }
                 }
                 elseif ($param.DefaultMissingValue) { $param.DefaultMissingValue }
            }
            elseif ( $param.NoGap -and
                     $value -match "\s" )            { "$($param.OriginalName)""$value"""}
            elseif ( $param.NoGap )                  { "$($param.OriginalName)$value"}

            else {
                if($param.OriginalName)              {  $param.OriginalName }
                $value | Foreach-Object {$_}
            }
    }

    #Add those parameters which have default values, excluding the ubiquitous parameters
    $commandArgs            = @()
    $boundParameters        =  $PSBoundParameters
    $cmdParameters          =  $MyInvocation.MyCommand.Parameters.Values
    $defaultValueParameters = ($cmdParameters | Where-Object {$_.Attributes.TypeId.Name -eq "PSDefaultValueAttribute" } ).Name
    $switchParameters       = ($cmdParameters | Where-Object {$_.SwitchParameter -and $_.Name -notmatch "Debug|Whatif|Confirm|Verbose"}).Name
    foreach ($p in $defaultValueParameters) {if (-not $PSBoundParameters.ContainsKey($p)) {$boundParameters[$p] = Get-Variable -Name $p -ValueOnly } }
    foreach ($p in $switchParameters)       {if (-not $PSBoundParameters.ContainsKey($p)) {$boundParameters[$p] = [switch]::new($false) } }
    $lateParams              = $boundParameters.Keys | Where-Object {-not $parameterMap[$_].ApplyToExecutable} | Sort-Object {$parameterMap[$_].OriginalPosition}
    $earlyParams             = $boundParameters.Keys | Where-Object {     $parameterMap[$_].ApplyToExecutable} | Sort-Object {$parameterMap[$_].OriginalPosition}

    # look for any parameter values which apply to the executable and must be before the original command elements
    foreach ($paramName in $earlyParams) { # take those parameters which apply to the executable
        $commandArgs += NewArgument $boundParameters[$paramName]  $parameterMap[$paramName]  #paramnname is only names where $parameterMap[that name].Apply to executable is true, so this always returns a value
    }

    # now the original command elements may be added
    $commandArgs += 'version'
    $commandArgs += '-json'

    # skip any parameters which apply to the executable at the start of the command line
    foreach ($paramName in $lateparams) {
        $param = $parameterMap[$paramName]
        if ($param) { $commandArgs += NewArgument $boundParameters[$paramName] $param}
    }

    $commandArgs = $commandArgs | Where-Object {$_ -ne $null} # strip only nulls

    Write-Verbose -Message ("terraform $commandArgs")
    if ($boundParameters["Debug"])   {Wait-Debugger}

    $handlerInfo = $outputHandlers[$PSCmdlet.ParameterSetName]
    if (-not  $handlerInfo ) {$handlerInfo = $outputHandlers["Default"]} # Guaranteed to be present
    $handler     = $handlerInfo.Handler
    if ( $handlerInfo.StreamOutput ) { & "terraform" $commandArgs | & $handler}
    else {
        $result = & "terraform" $commandArgs
        if ($result) {& $handler $result}
    }

  }
}

function tfPlanJsonToObject {
    $result     = $input | convertfrom-json    
    $errResults = $result | Where-Object {$_.type  -eq "diagnostic"} | ForEach-Object diagnostic |
            Select-Object @{n='Severity';e={$_.severity.toUpper()}}, @{n="Summary";e='Summary'},
                          @{n='Context'; e={if (-not $range) {""} else {$_.range.filename + " @ Line "  + $_.range.start.line + ": " +
                            ($_.snippet.code -replace "(?<=^.{$($_.snippet.highlight_end_offset)})",$PSStyle.Reset -replace "(?<=^.{$($_.snippet.highlight_start_offset)})",$PSStyle.underline)}}} | 
                Add-Member -TypeName TerraformError -PassThru 
    if ($errResults) {$errResults}
    else { $result | Where-Object {$_.type -eq 'planned_change'} |   
            Select-Object @{n='Action';  e={$_.change.action}}, 
                        @{n='Resource';e={$_.change.resource.resource}}  | 
                Add-Member -TypeName TerraformChange -PassThru 
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
    # check for the application and throw if it cannot be found
    if ( -not (Get-Command -ErrorAction Ignore terraform)) {
               throw  "Cannot find executable 'terraform'"
    }
    $parameterMap   = @{
        Directory = @{
            OriginalName        = '-chdir='
            OriginalPosition    = '0'
            Position            = '2147483647'
            ParameterType       = 'object'
            ApplyToExecutable   =  $True
            NoGap               =  $True
        }
        OutFile = @{
            OriginalName        = '-out'
            OriginalPosition    = '0'
            Position            = '0'
            ParameterType       = 'String'
            ApplyToExecutable   =  $False
            NoGap               =  $False
        }
        Destroy = @{
            OriginalName        = '-destroy'
            OriginalPosition    = '1'
            Position            = '2147483647'
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

    function NewArgument {
        param  ($value, $param)
            if ($value -is [switch]) {
                 if ($value.IsPresent) {
                     if ($param.OriginalName)        { $param.OriginalName }
                 }
                 elseif ($param.DefaultMissingValue) { $param.DefaultMissingValue }
            }
            elseif ( $param.NoGap -and
                     $value -match "\s" )            { "$($param.OriginalName)""$value"""}
            elseif ( $param.NoGap )                  { "$($param.OriginalName)$value"}

            else {
                if($param.OriginalName)              {  $param.OriginalName }
                $value | Foreach-Object {$_}
            }
    }

    #Add those parameters which have default values, excluding the ubiquitous parameters
    $commandArgs            = @()
    $boundParameters        =  $PSBoundParameters
    $cmdParameters          =  $MyInvocation.MyCommand.Parameters.Values
    $defaultValueParameters = ($cmdParameters | Where-Object {$_.Attributes.TypeId.Name -eq "PSDefaultValueAttribute" } ).Name
    $switchParameters       = ($cmdParameters | Where-Object {$_.SwitchParameter -and $_.Name -notmatch "Debug|Whatif|Confirm|Verbose"}).Name
    foreach ($p in $defaultValueParameters) {if (-not $PSBoundParameters.ContainsKey($p)) {$boundParameters[$p] = Get-Variable -Name $p -ValueOnly } }
    foreach ($p in $switchParameters)       {if (-not $PSBoundParameters.ContainsKey($p)) {$boundParameters[$p] = [switch]::new($false) } }
    $lateParams              = $boundParameters.Keys | Where-Object {-not $parameterMap[$_].ApplyToExecutable} | Sort-Object {$parameterMap[$_].OriginalPosition}
    $earlyParams             = $boundParameters.Keys | Where-Object {     $parameterMap[$_].ApplyToExecutable} | Sort-Object {$parameterMap[$_].OriginalPosition}

    # look for any parameter values which apply to the executable and must be before the original command elements
    foreach ($paramName in $earlyParams) { # take those parameters which apply to the executable
        $commandArgs += NewArgument $boundParameters[$paramName]  $parameterMap[$paramName]  #paramnname is only names where $parameterMap[that name].Apply to executable is true, so this always returns a value
    }

    # now the original command elements may be added
    $commandArgs += 'plan'
    $commandArgs += '-json'

    # skip any parameters which apply to the executable at the start of the command line
    foreach ($paramName in $lateparams) {
        $param = $parameterMap[$paramName]
        if ($param) { $commandArgs += NewArgument $boundParameters[$paramName] $param}
    }

    $commandArgs = $commandArgs | Where-Object {$_ -ne $null} # strip only nulls

    Write-Verbose -Message ("terraform $commandArgs")
    if ($boundParameters["Debug"])   {Wait-Debugger}

    $handlerInfo = $outputHandlers[$PSCmdlet.ParameterSetName]
    if (-not  $handlerInfo ) {$handlerInfo = $outputHandlers["Default"]} # Guaranteed to be present
    $handler     = $handlerInfo.Handler
    if ( $handlerInfo.StreamOutput ) { & "terraform" $commandArgs | & $handler}
    else {
        $result = & "terraform" $commandArgs
        if ($result) {& $handler $result}
    }

  }
}

