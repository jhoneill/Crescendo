# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License
# this contains code common for all generators
# OM VERSION 1.2
# =========================================================================
using namespace System.Collections.Generic

$FunctionTemplate =  @'
<#HELPERFUNCTIONS#>
function <#FUNCTIONNAME#> {
<#
<#COMMANDHELP#>
#>
  [CmdletBinding(<#CBATTRIBUTES#>)]
<#FUNCTIONATTRIBUTES#>
  param   (<#PARAMLIST#>  )
  begin   {
    if ( -not (Get-Command -ErrorAction Ignore <#ORIGINALNAME#>)) {throw  "Cannot find executable '<#ORIGINALNAME#>'"}
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
    $parameterMap   = @{<#PARAMETERMAP#>   }
    $outputHandlers = @{<#HANDLERMAP#>    }
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
<#BUILDARGS#>

    $commandArgs = $commandArgs | Where-Object {$_ -ne $null} # strip only nulls
    #endregionn

<#COMMANDBLOCK#>
  }
}

'@
$EarlyParameters   = @'
    # add any arguments which apply to the executable and must be before the original command elements, then the original elements if any then trailing arguments.
    $boundParameters.Keys | Where-Object {     $parameterMap[$_].ApplyToExecutable} |
        Sort-Object {$parameterMap[$_].OriginalPosition} | Foreach-Object { # take those parameters which apply to the executable
        $commandArgs += NewArgument $boundParameters[$_]  $parameterMap[$_]  #only have parameters where $parameterMap[that name].Apply to executable is true, so this always returns a value
    }
'@
$LateParameters = @'
    # Add parameters which don't apply to the executable - use a negative original position to say this only in the wrapper, not passed to the command.
    $boundParameters.Keys | Where-Object {[int]$parameterMap[$_].OriginalPosition -ge 0 -and
                                          -not $parameterMap[$_].ApplyToExecutable} |
        Sort-Object {$parameterMap[$_].OriginalPosition} | Foreach-Object {
            $commandArgs += NewArgument $boundParameters[$_]  $parameterMap[$_]  #only have parameters where $parameterMap[that name].Original postion >=, so this always returns a value
    }
'@

class UsageInfo     {  # used for .SYNOPSIS of the comment-based help
    [string]         $Synopsis
    [bool]           $SupportsFlags
    [bool]           $HasOptions
    hidden [string[]]$OriginalText

    UsageInfo() { }
    UsageInfo([string] $synopsis) {$this.Synopsis = $synopsis }

    [string]ToString() {
        return ("  .SYNOPSIS`n    $($this.synopsis)")
    }
}

class ExampleInfo   {  # used for .EXAMPLE of the comment-based help
    [string]   $Command         # ps-command
    [string]   $OriginalCommand # original native tool command
    [string]   $Description

    ExampleInfo() { }
    ExampleInfo([string]$Command, [string]$OriginalCommand, [string]$Description) {
        $this.Command         = $Command
        $this.OriginalCommand = $OriginalCommand
        $this.Description     = $Description
    }

    [string]ToString() {
        $text = "  .EXAMPLE`n    PS> $($this.Command)`n`n    " +
                                     ($this.Description -replace "\r?\n\s*",   "$([System.Environment]::NewLine)    " )
        if ($this.OriginalCommand) {
            $text += "`n    Original Command: $($this.OriginalCommand)"
        }
        return $text
    }
}

class ParameterInfo {
    [string]   $Name          # PS-function name
    [string]   $OriginalName # original native parameter name
    [string]   $OriginalText
    [string]   $Description
    [string]   $DefaultValue
    # some parameters are -param or +param which can be represented with a switch parameter so we need way to provide for this
    [string]   $DefaultMissingValue
    # this is in case that the parameters apply before the OriginalCommandElements
    [bool]     $ApplyToExecutable
    [string]   $ParameterType = 'object' # PS type
    [string[]] $AdditionalParameterAttributes
    [bool]     $Mandatory
    [string[]] $ParameterSetName
    [string[]] $Aliases
    [hashtable]$ValueMap
    [int]      $Position = [int]::MaxValue
    [int]      $OriginalPosition
    [bool]     $ValueFromPipeline
    [bool]     $ValueFromPipelineByPropertyName
    [bool]     $ValueFromRemainingArguments
    [bool]     $NoGap # this means that we need to construct the parameter as "foo=bar"

    ParameterInfo() {
        $this.Position      = [int]::MaxValue
    }
    ParameterInfo (   [string]$Name, [string]$OriginalName) {
        $this.Name          = $Name
        $this.OriginalName  = $OriginalName
        $this.Position      = [int]::MaxValue
    }

    [string]ToString() {
        if ($this.Name -eq [string]::Empty) {return $null}
        if ($this.AdditionalParameterAttributes)  {
                $paramText = "    " + ($this.AdditionalParameterAttributes -join "`n    ") +"`n"
        }
        else {  $paramText += ""  }
        if ($this.ValueMap.Keys.Count -and $paramtext -notmatch 'ValidateSet') {
                $paramText += "    [ValidateSet('" + ($this.ValueMap.Keys -join "', '") + "')]`n"
        }
        if ($this.Aliases ) {
                $paramText += "    [Alias('" + ($this.Aliases -join "','")  + "')]`n"
        }
        # TODO: This logic does not handle parameters in multiple sets correctly
        $elements = @()
        if ( $this.Position -ne [int]::MaxValue )    { $elements += "Position=" + $this.Position }
        if ( $this.ValueFromPipeline )               { $elements += 'ValueFromPipeline=$true' }
        if ( $this.ValueFromPipelineByPropertyName ) { $elements += 'ValueFromPipelineByPropertyName=$true' }
        if ( $this.ValueFromRemainingArguments )     { $elements += 'ValueFromRemainingArguments=$true' }
        if ( $this.Mandatory )                       { $elements += 'Mandatory=$true' }
        if ( $this.ParameterSetName.Count)           {
            foreach($parameterSetName in $this.ParameterSetName) {
                $elements   =  @("ParameterSetName='$parameterSetName'") + $elements
                $paramText +=  '    [Parameter(' + ($elements -join ",") + ")]`n"
            }
        }
        elseif ($elements.Count -gt 0)               {
                $paramText +=  '    [Parameter(' + ($elements -join ",") + ")]`n"
        }

        <# We need a way to find those parameters which have default values because they will not be in
           psboundparmeters but still need to be added to the command arguments.
           We can search through the parameters for this attribute. We may need to handle collections as well. #>
        if ( $null -ne $this.DefaultValue ) {
              return ($paramText + "    [PSDefaultValue(Value='$($this.DefaultValue)')]`n" +
                                   "    [$($this.ParameterType)]`$$($this.Name)=""$($this.DefaultValue)""")
        }
        else {return ($paramText + "    [$($this.ParameterType)]`$$($this.Name)") }
    }

    [string]GetParameterHelp() {
        return ( "  .PARAMETER $($this.Name)`n    " +
                                ($this.Description -replace "\r?\n\s*", "`n    " ) + "`n")
    }
}

class OutputHandler {
    [string]    $ParameterSetName
    [string]    $Handler     # This is a scriptblock which does the conversion to an object
    [string]    $HandlerType # Inline, Function, or Script
    [bool]      $StreamOutput  # this indicates whether the output should be streamed to the handler
    OutputHandler() {
        $this.HandlerType = "Inline" # default is an inline script
    }
    [string]ToString() {
        if     ($this.HandlerType -eq "Inline" -or ($this.HandlerType -eq "Function" -and $this.Handler -match '\s')) {
                return ('        {0} = @{{ StreamOutput = ${1}; Handler = {{ {2} }} }}'           -f $this.ParameterSetName, $this.StreamOutput, $this.Handler)
        }
        elseif ($this.HandlerType -eq "Script") {
                return ('        {0} = @{{ StreamOutput = ${1}; Handler = "$PSScriptRoot/{2}" }}' -f $this.ParameterSetName, $this.StreamOutput, $this.Handler)
        }
        else { # function
                return ('        {0} = @{{ StreamOutput = ${1}; Handler = ''{2}'' }}'             -f $this.ParameterSetName, $this.StreamOutput, $this.Handler)
        }
    }
}

class Elevation     {
    [string]$Command
    [List[ParameterInfo]]$Arguments
}

class Command       {
    [string]              $Verb                    # PS-function name verb
    [string]              $Noun                    # PS-function name noun
    [string]              $OriginalName            # e.g. "cubectl get user" -> "cubectl"
    [string[]]            $OriginalCommandElements # e.g. "cubectl get user" -> "get", "user"
    [string[]]            $Platform                # can be any (or all) of "Windows","Linux","MacOS"
    [Elevation]           $Elevation
    [string[]]            $Aliases
    [string]              $DefaultParameterSetName
    [bool]                $SupportsShouldProcess
    [string]              $ConfirmImpact
    [bool]                $SupportsTransactions
    [bool]                $NoInvocation            # certain scenarios want to use the generated code as a front end. When true, the generated code will return the arguments only.
    [string]              $Description
    [UsageInfo]           $Usage
    [List[ParameterInfo]] $Parameters
    [List[ExampleInfo]]   $Examples
    [string]              $OriginalText
    [string[]]            $HelpLinks
    [OutputHandler[]]     $OutputHandlers

    Command () {$this.Platform = "Windows","Linux","MacOS"}
    Command ([string]$Verb, [string]$Noun) {
        $this.Verb       = $Verb
        $this.Noun       = $Noun
        $this.Parameters = [List[ParameterInfo]]::new()
        $this.Examples   = [List[ExampleInfo]]::new()
        $this.Platform   = "Windows","Linux","MacOS"
    }

    [string]ToString() {
        return $this.ToString($false)
    }
    # emit the function, if EmitAttribute is true, the Crescendo attribute will be included
    [string]ToString([bool]$EmitAttribute) {
        $parameterTemplate    = @'
        {0} = @{{
            OriginalName        = '{1}'
            OriginalPosition    = '{2}'
            ParameterType       = '{3}'
            ApplyToExecutable   =  ${4}
            NoGap               =  ${5}

'@
        #xxxx todo we should check platform and insert a check / "this is the wrong OS" message
        #region build the param block, put it into the function template and put the parameter and handler hashtables into begin block
        #We will always provide a parameter block, even if it's empty
        $paramlist            = @()
        $parameterMap         = ""
        foreach ($p in $this.Parameters) {
            $paramlist        += "`n" + $p.ToString()
            $parameterMap     += $ParameterTemplate -f $p.Name, $p.OriginalName, $p.OriginalPosition,  $p.ParameterType, $p.ApplyToExecutable, $p.NoGap
            if ($p.DefaultValue) {
                $parameterMap += "            DefaultValue        = '$($p.DefaultValue)'`n"
            }
            if ($p.DefaultMissingValue) {
                $parameterMap += "            DefaultMissingValue = '$($p.DefaultMissingValue)'`n"
            }
            if ($p.ValueMap.keys.count) {
                $mapItems = @()
                foreach ($k in $p.valuemap.keys) {
                    $mapitems += "'{0}' = '{1}'" -f $k, ($p.valuemap[$k] -replace "'","''")
                }
                $parameterMap += "            ValueMap            = @{ " + ($mapitems -join '; ') + " }`n"
            }
            $parameterMap     += "        }`n"
        }
        if ($parameterMap)    {$parameterMap  =  "`n$parameterMap" }
        if ($paramlist.count) {$paramlist[-1] += "`n"}
        $thefunction = $script:FunctionTemplate.Replace("<#PARAMLIST#>", ($paramlist -join ',')).replace("<#PARAMETERMAP#>", $parameterMap)

        if ( -not $this.OutputHandlers) { $handlerText = '        Default = @{ StreamOutput = $true; Handler = { $input } } ' }
        else {
            $handlerText  = "`n"
            foreach($handler in $this.OutputHandlers) {$handlerText += $handler.ToString() + "`n"}
        }
        $theFunction = $theFunction.Replace("<#HANDLERMAP#>", $handlerText)
        #endregion

        #region add the command invocation to the template - unlesss NoInvocation is specified, it must be non-null otherwise we won't actually be invoking anything
        if   ( $this.NoInvocation ) { $theFunction  = $thefunction.Replace('<#COMMANDBLOCK#>', '    return $commandArgs')}
        else {
            $commandBlock = @'
    #region invoke the command with arguments and handle results
    Write-Verbose -Message ("<#ORIGINALNAME#> $commandArgs")
    if ($boundParameters["Debug"])   {Wait-Debugger}

    $handlerInfo = $outputHandlers[$PSCmdlet.ParameterSetName]
    if (-not  $handlerInfo ) {$handlerInfo = $outputHandlers["Default"]} # Guaranteed to be present
    $handler     = $handlerInfo.Handler

'@
            if ($this.SupportsShouldProcess) {$commandBlock += @'
    if ( $PSCmdlet.ShouldProcess("<#OriginalName#> $commandArgs")) {
        if ( $handlerInfo.StreamOutput ) { & <#THECOMMAND#> | & $handler}
        else {
            $result = & <#THECOMMAND#>
            if ($result) {& $handler $result}
        }
    }
    #endregion
'@      }
            else {$commandBlock += @'
    if ( $handlerInfo.StreamOutput ) { & <#THECOMMAND#> | & $handler}
    else {
        $result = & <#THECOMMAND#>
        if ($result) {& $handler $result}
    }
    #endregion
'@      }

            if   ( $this.Elevation.Command ) {
                    $elevationArgs    =  $($this.Elevation.Arguments | Foreach-Object { "{0} {1}" -f $_.OriginalName, $_.DefaultValue }) -join " "
                    $theCommand       = '"{0}" {1} "{2}" $commandArgs' -f $this.Elevation.Command, $elevationArgs, $this.OriginalName
             }
            else {  $theCommand       = '"{0}" $commandArgs'           -f  $this.OriginalName }
            $commandblock = $commandBlock.Replace("<#THECOMMAND#>",$theCommand)
            $theFunction  = $thefunction.Replace('<#COMMANDBLOCK#>', $commandBlock)
        }
        #endregion

        #region add any original command elements (parameters that are always specified for this version of the command) and code to add arguments before/after them if required.
        if ($this.parameters.where({$_.ApplyToExecutable})) {
                $argBuilder  = $script:earlyParameters
        }
        else   {$argBuilder  = "`n"}
        if ($this.OriginalCommandElements) {
            $argBuilder      = "    # now the original command elements may be added`n" + $argBuilder
            foreach($element in $this.OriginalCommandElements) {
                # we put single quotes into the code to reduce injection attacks
                $argBuilder  +=  "    `$commandArgs += '$element'`n"
            }
        }
        if ($this.parameters.where({-not $_.ApplyToExecutable -and $_.originalposition -ge 0}) ) {
                $argBuilder += $script:LateParameters
        }
        $theFunction = $theFunction.Replace("<#BUILDARGS#>",$argBuilder)
        #endregion

        #region build and add the helptext
        $helpText = ""
        if ( $this.Usage.Synopsis) {$helptext +=  "  .SYNOPSIS`n    $($this.Usage.Synopsis)`n" }
        $helptext +=   "  .DESCRIPTION`n    "
        if ( $this.Description )   { $helptext += ($this.Description -replace "\r?\n\s*",   "`n    " )}
        else                       { $helptext +=  "See help for $($this.OriginalName)" }
        foreach ( $parameter in $this.Parameters.where({$_.Description})) {
                $helptext +=  [System.Environment]::NewLine + "  .PARAMETER $($parameter.Name)`n    " +
                                 ($parameter.Description -replace "\r?\n\s*",   "`n    " )
        }
        foreach ( $example in $this.Examples ) {
                $helptext +=  "`n" +  $example.ToString()
        }
        if ( $this.HelpLinks.Count -gt 0 ) {
            $helptext += "`n  .LINK"
            foreach ( $link in $this.HelpLinks ) {  $helptext +=  "`n    $link"}
        }
        $theFunction = $theFunction  -replace "<#COMMANDHELP#>",  $helpText
        #endregion

        #region get any values which will appear in [cmdletbinding()]
        $cbAttributes         = @()
        if ( $this.DefaultParameterSetName  ) {$cbAttributes += "DefaultParameterSetName='$($this.DefaultParameterSetName)'"}
        if ( $this.SupportsShouldProcess    ) {$cbAttributes += 'SupportsShouldProcess=$true'}
        if ( $this.ConfirmImpact -in
             @("high","medium","low","none")) {$cbAttributes += "ConfirmImpact='$($this.ConfirmImpact)'" }
        elseif ($this.ConfirmImpact)          {throw ("Confirm Impact '{0}' is invalid. It must be High, Medium, Low, or None." -f $this.ConfirmImpact) }
        $theFunction = $theFunction.Replace("<#CBATTRIBUTES#>",   ($cbAttributes -join ","))
        #endregion

        #region get function attributes to appear wtih [cmdletbinding()]
        $functionAttributes   = ""
        if ( $this.Elevation.Command -and
                 $EmitAttribute ) {$functionAttributes +=  "  [PowerShellCustomFunctionAttribute(RequiresElevation=`$true)]`n" }
        elseif ( $EmitAttribute ) {$functionAttributes +=  "  [PowerShellCustomFunctionAttribute(RequiresElevation=`$false)]`n" }
        if ($this.Aliases)        {$functionAttributes +=  "  [Alias('" + ($this.Aliases -join "','")  +"')]`n"}
        $thefunction = $theFunction.Replace("<#FUNCTIONATTRIBUTES#>",  $functionAttributes)
        #endregion

        #region add any output handlers which were implemened as functions so they're available in the exported module.
        $helperFunctions = ""
        foreach ($handler in $this.OutputHandlers.where({$_.HandlerType -eq 'Function'}) ) {
                 $handlerName      = $handler.Handler -replace '^(\S+)\s.*$','$1'
                 $functionHandler  = Get-Content function:$handlerName -ErrorAction Ignore
                 if ( $null -eq $functionHandler ) {throw "Cannot find function '$handlerName'."}
                 $helperFunctions +=  $functionHandler.Ast.Extent.Text + "`n"
        }
        $theFunction = $theFunction.Replace("<#HELPERFUNCTIONS#>" ,$helperFunctions)
        #endregion

        #Put the original command name and powerShell name into the template and return what we've built
        return  $thefunction -replace "<#FUNCTIONNAME#>", "$($this.Verb)-$($this.Noun)"   -replace '<#ORIGINALNAME#>', $this.OriginalName
    }

    [string]GetCrescendoConfiguration() {
        $sOptions = [System.Text.Json.JsonSerializerOptions]::new()
        $sOptions.WriteIndented = $true
        $sOptions.MaxDepth = 10
        $sOptions.IgnoreNullValues = $true
        $text = [System.Text.Json.JsonSerializer]::Serialize($this, $sOptions)
        return $text
    }

    [void]ExportConfigurationFile([string]$filePath) {
        Set-Content -Path $filePath -Value $this.GetCrescendoConfiguration()
    }
}

function Test-Handler {
    <#
        .SYNOPSIS
            function to test whether there is a parser error in the output handler
    #>
    param (
        [Parameter(Mandatory=$true)][string]$script,
        [Parameter(Mandatory=$true)][ref]$parserErrors
    )
    $null = [System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$null, $parserErrors)
    (0 -eq $parserErrors.Value.Count)
}

# functions to create the classes since you can't access the classes outside the module
function New-ParameterInfo {
    [alias('CrescendoParameter')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions","")]
    param (
        [Parameter(Position=0,Mandatory=$true)]
        [string]$Name,
        [Parameter(Position=1,Mandatory=$true)][AllowEmptyString()]
        [string]$OriginalName,
        [int]$OriginalPosition,
        [string]$OriginalText,
        [int]$Position = [int]::MaxValue,
        [string]$Description,
        [string]$DefaultValue,
        [string]$DefaultMissingValue,
        [string]$ParameterType = 'object', # PS type
        [string[]]$AdditionalParameterAttributes,
        [string[]]$ParameterSetName,
        [string[]]$Aliases,
        [hashtable]$ValueMap,
        [switch]$Mandatory,
        [switch]$ValueFromPipeline,
        [switch]$ValueFromPipelineByPropertyName,
        [switch]$ValueFromRemainingArguments,
        [switch]$ApplyToExecutable,
        [switch]$NoGap  # this means that we need to construct the parameter as "foo=bar"
    )
    New-object -TypeName ParameterInfo -ArgumentList $Name,$OriginalName -Property $PSBoundParameters
}

function New-UsageInfo {
    [alias('CrescendoSynopsis')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions","")]
    param (
        [Parameter(Position=0,Mandatory=$true)][string]$usage
        )
    [UsageInfo]::new($usage)
}

function New-ExampleInfo {
    [alias('CrescendoExample')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions","")]
    param (
        [Parameter(Position=0,Mandatory=$true)][string]$command,
        [Parameter(Position=1,Mandatory=$true)][string]$description,
        [Parameter(Position=2)][string]$originalCommand = ""
        )
    [ExampleInfo]::new($command, $originalCommand, $description)
}

function New-OutputHandler    {
    [alias('CrescendoHandler')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions","")]
    param (
        [ValidateSet('Inline','Script','Funtion')]
        [Alias('HandlerType')]
        $Type = 'Funtion',
        $Handler,
        $ParameterSetName,
        [switch]$StreamOutput
     )

     New-object -TypeName Outputhandler -Property $PSBoundParameters
}

function New-CrescendoCommand {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions","")]
    param (
        [Parameter(Position=0,Mandatory=$true)][string]$Verb,
        [Parameter(Position=1,Mandatory=$true)][string]$Noun,
        [Parameter(Position=2)][string]$OriginalName
    )
    $cmd = [Command]::new($Verb, $Noun)
    $cmd.OriginalName = $OriginalName
    $cmd
}

function Export-CrescendoCommand {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$true)]
        [Command[]]$command,
        [Parameter()][string]$targetDirectory = "."
    )

    process {
        foreach($crescendoCommand in $command) {
            if($PSCmdlet.ShouldProcess($crescendoCommand)) {
                $fileName = "{0}-{1}.crescendo.json" -f $crescendoCommand.Verb, $crescendoCommand.Noun
                $exportPath = Join-Path $targetDirectory $fileName
                $crescendoCommand.ExportConfigurationFile($exportPath)
            }
        }
    }
}

function Import-CommandConfiguration {
[CmdletBinding()]
param ([Parameter(Position=0,Mandatory=$true)][string]$file)
    $options = [System.Text.Json.JsonSerializerOptions]::new()
    # this dance is to support multiple configurations in a single file
    # The deserializer doesn't seem to support creating [command[]]
    (Get-Content $file | ConvertFrom-Json -depth 10).Commands |
        ForEach-Object { $_ | ConvertTo-Json -depth 10 |
            Foreach-Object {
                $configuration = [System.Text.Json.JsonSerializer]::Deserialize($_, [command], $options)
                $errs = $null
                if (!(Test-Configuration -configuration $configuration -errors ([ref]$errs))) {
                    $errs | Foreach-Object { Write-Error -ErrorRecord $_ }
                }
                # emit the configuration even if there was an error
                $configuration
            }
        }
}

function Test-Configuration {
    param ([Command]$Configuration, [ref]$errors)

    $configErrors = @()
    $configurationOK = $true

    # Validate the Platform types
    $allowedPlatforms = "Windows","Linux","MacOS"
    foreach($platform in $Configuration.Platform) {
        if ($allowedPlatforms -notcontains $platform) {
            $configurationOK = $false
            $e = [System.Management.Automation.ErrorRecord]::new(
                [Exception]::new("Platform '$platform' is not allowed. Use 'Windows', 'Linux', or 'MacOS'"),
                "ParserError",
                "InvalidArgument",
                "Import-CommandConfiguration:Platform")
            $configErrors += $e
        }
    }

    # Validate the output handlers in the configuration
    foreach ( $handler in $configuration.OutputHandlers ) {
        $parserErrors = $null
        if ( -not (Test-Handler -Script $handler.Handler -ParserErrors ([ref]$parserErrors))) {
            $configurationOK = $false
            $exceptionMessage = "OutputHandler Error in '{0}' for ParameterSet '{1}'" -f $configuration.FunctionName, $handler.ParameterSetName
            $e = [System.Management.Automation.ErrorRecord]::new(
                ([Exception]::new($exceptionMessage)),
                "Import-CommandConfiguration:OutputHandler",
                "ParserError",
                $parserErrors)
            $configErrors += $e
        }
    }
    if ($configErrors.Count -gt 0) {
        $errors.Value = $configErrors
    }

    return $configurationOK

}

function Export-Schema() {
    $sGen = [Newtonsoft.Json.Schema.JsonSchemaGenerator]::new()
    $sGen.Generate([command])
}

function Export-CrescendoModule {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param   (
        [Parameter(Position=1,Mandatory=$true,ValueFromPipelineByPropertyName=$true)][SupportsWildcards()][string[]]$ConfigurationFile,
        [Parameter(Position=0,Mandatory=$true)][string]$ModuleName,
        [Parameter()][switch]$Force
        )
    begin   {
        [array]$crescendoCollection = @()
        if ($ModuleName -notmatch "\.psm1$")          { $ModuleName += ".psm1"}
        if ((Test-Path $ModuleName) -and -not $Force) {throw "$ModuleName already exists"}
        if (-not $PSCmdlet.ShouldProcess("Creating Module '$ModuleName'")) {return}

        # static parts of the crescendo module
        Set-content $ModuleName @'
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

'@
        $moduleBase = [System.IO.Path]::GetDirectoryName($ModuleName)
    }
    process {
        if ( $PSBoundParameters['WhatIf'] ) {return}
        $resolvedConfigurationPaths = (Resolve-Path $ConfigurationFile).Path
        foreach($file in $resolvedConfigurationPaths) {
            Write-Verbose "Adding $file to Crescendo collection"
            $crescendoCollection += Import-CommandConfiguration $file
        }
    }
    end {
        if ( $PSBoundParameters['WhatIf'] ) {return}
         $ModuleManifestArguments            = @{
            Path              = $ModuleName -Replace "psm1$","psd1"
            RootModule        = [io.path]::GetFileName(${ModuleName})
            Tags              = "CrescendoBuilt"
            PowerShellVersion = "5.1.0"
            CmdletsToExport   = @()
            AliasesToExport   = @()
            VariablesToExport = @()
            FunctionsToExport = @()
            PrivateData       = @{ CrescendoGenerated = Get-Date; CrescendoVersion = (Get-Module Microsoft.PowerShell.Crescendo).Version }
        }

        # include the windows helper if it has been included
        if ($crescendoCollection.Elevation.Command -eq "Invoke-WindowsNativeAppWithElevation") {
            "function Invoke-WindowsNativeAppWithElevation {" >> $ModuleName
            $InvokeWindowsNativeAppWithElevationFunction >> $ModuleName
            "}" >> $ModuleName
        }

        foreach($proxy in $crescendoCollection) {
            # we need the aliases without value for the psd1
            foreach ($a in $proxy.Aliases) {$ModuleManifestArguments.AliasesToExport += $_}
            $ModuleManifestArguments.FunctionsToExport += $proxy.FunctionName
            # when set to true, we will emit the Crescendo attribute
            $proxy.ToString($true) >> $ModuleName
        }
        New-ModuleManifest @ModuleManifestArguments

        # copy the script output handlers into place
        foreach($handler in $crescendoCollection.OutputHandlers.where({$_.HandlerType -eq "Script"})) {
            $scriptInfo = Get-Command -ErrorAction Ignore -CommandType ExternalScript $handler.Handler
            if($scriptInfo) { Copy-Item $scriptInfo.Source $moduleBase }
            else {
                $errArgs = @{
                    Category          = "ObjectNotFound"
                    TargetObject      = $scriptInfo.Source
                    Message           = "Handler '" + $scriptInfo.Source + "' not found."
                    RecommendedAction = "Copy the handler to the module directory before packaging."
                }
                Write-Error @errArgs
            }
        }
    }
}

# This is an elevation function for Windows which may be distributed with a crescendo module
$InvokeWindowsNativeAppWithElevationFunction = @'
    [CmdletBinding(DefaultParameterSetName="username")]
    param (
        [Parameter(Position=0,Mandatory=$true)]
        [string]$command,
        [Parameter(ParameterSetName="credential")]
        [PSCredential]$Credential,
        [Parameter(ParameterSetName="username")]
        [string]$User = "Administrator",
        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$cArguments
    )

    $app    = "cmd.exe"
    $nargs  = @("/c","cd","/d","%CD%","&&")
    $nargs += $command
    if ( $cArguments.count ) {$nargs += $cArguments}
    $OUTPUT = Join-Path ([io.Path]::GetTempPath()) "CrescendoOutput.txt"
    $ERROR  = Join-Path ([io.Path]::GetTempPath()) "CrescendoError.txt"
    if (-not $Credential ) {$Credential = Get-Credential $User }

    $spArgs = @{
        Credential              = $Credential
        File                    = $app
        ArgumentList            = $nargs
        RedirectStandardOutput  = $OUTPUT
        RedirectStandardError   = $ERROR
        WindowStyle             = "Minimized"
        PassThru                = $True
        ErrorAction             = "Stop"
    }
    $timeout    = 10000
    $sleepTime  = 500
    $totalSleep = 0
    try {
        $p = start-process @spArgs
        while(!$p.HasExited) {
            Start-Sleep -mill $sleepTime
            $totalSleep  +=   $sleepTime
            if ( $totalSleep -gt $timeout ) {
                throw "'$(cArguments -join " ")' has timed out"
            }
        }
    }
    catch {
        # should we report error output?
        # It's most likely that there will be none if the process can't be started
        # or other issue with start-process. We catch actual error output from the
        # elevated command below.
        if ( Test-Path $OUTPUT ) { Remove-Item $OUTPUT }
        if ( Test-Path $ERROR )  { Remove-Item $ERROR }
        $msg = "Error running '{0} {1}'" -f $command,($cArguments -join " ")
        throw "$msg`n$_"
    }

    try {
        if ( test-path $OUTPUT ) {$output = Get-Content $OUTPUT        }
        if ( test-path $ERROR  ) {$errorText = (Get-Content $ERROR) -join "`n"}
    }
    finally {
        if ( $errorText ) {
            $exception   = [System.Exception]::new($errorText)
            $errorRecord = [system.management.automation.errorrecord]::new(
                $exception, "CrescendoElevationFailure", "InvalidOperation",
                ("{0} {1}" -f $command,($cArguments -join " "))
            )
            # errors emitted during the application are not fatal
            Write-Error $errorRecord
        }
        if ( Test-Path $OUTPUT ) { Remove-Item $OUTPUT }
        if ( Test-Path $ERROR )  { Remove-Item $ERROR }
    }
    # return the output to the caller
    $output
'@

class CrescendoCommandInfo {
    [string]$Module
    [string]$Source
    [string]$Name
    [bool]$IsCrescendoCommand
    [bool]$RequiresElevation
    CrescendoCommandInfo([string]$module, [string]$name, [Attribute]$attribute) {
        $this.Module = $module
        $this.Name   = $name
        $this.IsCrescendoCommand = $null -eq $attribute ? $false : ($attribute.Source -eq "Microsoft.PowerShell.Crescendo")
        $this.RequiresElevation  = $null -eq $attribute ? $false :  $attribute.RequiresElevation
        $this.Source             = $null -eq $attribute ? ""     :  $attribute.Source
    }
}

function Test-IsCrescendoCommand {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline=$true,Mandatory=$true,Position=0)]
        [object[]]$Command
    )
    PROCESS {
        # loop through the commands and determine whether it is a Crescendo Function
        foreach( $cmd in $Command) {
            $fInfo = $null
            if ($cmd -is [System.Management.Automation.FunctionInfo]) {
                $fInfo = $cmd
            }
            elseif ($cmd -is [string]) {
                $fInfo = Get-Command -Name $cmd -CommandType Function -ErrorAction Ignore
            }
            if(-not $fInfo) {
                Write-Error -Message "'$cmd' is not a function" -TargetObject "$cmd" -RecommendedAction "Be sure that the command is a function"
                continue
            }
            #  check for the PowerShellFunctionAttribute and report on findings
            $crescendoAttribute = $fInfo.ScriptBlock.Attributes|Where-Object {$_.TypeId.Name -eq "PowerShellCustomFunctionAttribute"} | Select-Object -Last 1
            [CrescendoCommandInfo]::new($fInfo.Source, $fInfo.Name, $crescendoAttribute)
        }
    }
}
