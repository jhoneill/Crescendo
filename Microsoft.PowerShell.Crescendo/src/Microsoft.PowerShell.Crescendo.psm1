# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License
# this contains code common for all generators
# OM VERSION 1.2
# =========================================================================
using namespace System.Collections.Generic
using namespace System.Management.Automation

$FunctionTemplate   = @'
function <#FUNCTIONNAME#> {
<#
<#COMMANDHELP#>
#>
  [CmdletBinding(<#CBATTRIBUTES#>)]
<#FUNCTIONATTRIBUTES#>
  param   (<#PARAMLIST#>  )
  begin   {<#PLATFORMCHECK#>
    if ( -not (Get-Command -ErrorAction Ignore <#ORIGINALNAME#>)) {throw  "Cannot find executable '<#ORIGINALNAME#>'"}
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
    #endregion

<#COMMANDBLOCK#>
  }
}

'@
#Each entry in the parameter map uses this template.
$parameterTemplate  = @'
        {0} = @{{
            OriginalName        = '{1}'
            OriginalPosition    = '{2}'
            ParameterType       = '{3}'
            ApplyToExecutable   =  ${4}
            NoGap               =  ${5}

'@
#Some arguments are fixed - early parameters (if any) go before them, late parameters (if any) go after.
$EarlyParameters    = @'
    # add any arguments which apply to the executable and must be before the original command elements, then the original elements if any then trailing arguments.
    $boundParameters.Keys | Where-Object {     $parameterMap[$_].ApplyToExecutable} |
        Sort-Object {$parameterMap[$_].OriginalPosition} | Foreach-Object { # take those parameters which apply to the executable
        $commandArgs += NewArgument $boundParameters[$_]  $parameterMap[$_]  #only have parameters where $parameterMap[that name].Apply to executable is true, so this always returns a value
    }
'@
$LateParameters     = @'
    # Add parameters which don't apply to the executable - use a negative original position to say this only in the wrapper, not passed to the command.
    $boundParameters.Keys | Where-Object {[int]$parameterMap[$_].OriginalPosition -ge 0 -and
                                          -not $parameterMap[$_].ApplyToExecutable} |
        Sort-Object {$parameterMap[$_].OriginalPosition} | Foreach-Object {
            $commandArgs += NewArgument $boundParameters[$_]  $parameterMap[$_]  #only have parameters where $parameterMap[that name].Original postion >=, so this always returns a value
    }
'@
#if NoInvocation is specified we skip the command block; otherwise it's a fixed part and a part to ask shouldProcess or a part which doesn't  ask.
$cmdblockStart      = @'
    #region invoke the command with arguments and handle results
    if ($boundParameters["Debug"])   {Wait-Debugger}

    $handlerInfo = $outputHandlers[$PSCmdlet.ParameterSetName]
    if (-not  $handlerInfo ) {$handlerInfo = $outputHandlers["Default"]} # Guaranteed to be present
    $handler     = $handlerInfo.Handler

'@
$cmdblockProcess    = @'
    if ( $PSCmdlet.ShouldProcess("<#PRERUNMESSAGE#>")) {
        if ( $handlerInfo.StreamOutput ) { & <#THECOMMAND#> | & $handler}
        else {
            $result = & <#THECOMMAND#>
            if ($result) {& $handler $result}
        }
    }
    #endregion
'@
$cmdblockAlways     = @'
    Write-Verbose -Message ("& <#PRERUNMESSAGE#>")
    if ( $handlerInfo.StreamOutput ) { & <#THECOMMAND#> | & $handler}
    else {
        $result = & <#THECOMMAND#>
        if ($result) {& $handler $result}
    }
    #endregion
'@
$HelperFunctions    = [ordered]@{NewArgument=@'
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
'@}
$ModuleStart        = @'
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
    CrescendoCommandInfo([string]$Module, [string]$Name, [Attribute]$Attribute) {
        $this.Module             = $Module
        $this.Name               = $Name
        $this.IsCrescendoCommand = $null -eq $Attribute ? $false : ($Attribute.Source -eq "Microsoft.PowerShell.Crescendo")
        $this.RequiresElevation  = $null -eq $Attribute ? $false :  $Attribute.RequiresElevation
        $this.Source             = $null -eq $Attribute ? ""     :  $Attribute.Source
    }
}

class UsageInfo            {  # used for .SYNOPSIS of the comment-based help
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

class ExampleInfo          {  # used for .EXAMPLE of the comment-based help
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

class ParameterInfo        {
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
                $paramText +=  '    [Parameter(' + ((@("ParameterSetName='$parameterSetName'") + $elements) -join ",") + ")]`n"
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

class OutputHandler        {
    [string]    $ParameterSetName
    [string]    $Handler       # This is a scriptblock which does the conversion to an object
    [string]    $HandlerType   # Inline, Function, or Script
    [bool]      $StreamOutput  # this indicates whether the output should be streamed to the handler
    OutputHandler() {
        $this.HandlerType      = "Inline" # default is an inline script
        $this.ParameterSetName = 'Default'
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

class Elevation            {
    [string]$Command
    [List[ParameterInfo]]$Arguments
}

class Command              {
    #region properties
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
    #endregion

    Command () {$this.Platform = "Windows","Linux","MacOS"}
    Command ([string]$Verb, [string]$Noun) {
        $this.Verb       = $Verb
        $this.Noun       = $Noun
        $this.Parameters = [List[ParameterInfo]]::new()
        $this.Examples   = [List[ExampleInfo]]::new()
        $this.Platform   = "Windows","Linux","MacOS"
    }

    #return helper functions as a hashtable of Name=function so an export of mutliple commands can de-duplicate and write one set of helpers
    [hashtable]GetHelperFunctions() {
        $HelperTable = [ordered]@{} +$script:HelperFunctions
        foreach ($handler in $this.OutputHandlers.where({$_.HandlerType -eq 'Function'}) ) {
            $handlerName      = $handler.Handler -replace '^(\S+)\s.*$','$1'
            $functionHandler  = Get-Content function:$handlerName -ErrorAction Ignore
            if ( $null -eq $functionHandler ) {throw "Cannot find function '$handlerName'."}
            else {$HelperTable[$handlerName] =  $functionHandler.Ast.Extent.Text}
        }
        return $HelperTable
    }

    #emit the function: if EmitAttribute is true, the Crescendo attribute will be included, if helpers skipped they can be added seperately.
    #Three versions no params = helpers and no attribute; only attribute specified includes helpers; or both specified
    [string]ToString() {
        return $this.ToString($false,$false)
    }
    [string]ToString([bool]$EmitAttribute) {
        return $this.ToString($EmitAttribute,$false)
    }
    [string]ToString([bool]$EmitAttribute,[bool]$SkipHelpers) {

        #region add any output handlers which need to be helper functions in the exported module.
        if ($SkipHelpers) {$theFunction = $script:FunctionTemplate}
        else              {$theFunction = ($this.GetHelperFunctions().Values -join "`n") + "`n" + $script:FunctionTemplate}
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

        #region get any values which will appear in [cmdletbinding(   )]
        $cbAttributes         = @()
        if ( $this.DefaultParameterSetName  ) {$cbAttributes += "DefaultParameterSetName='$($this.DefaultParameterSetName)'"}
        if ( $this.SupportsShouldProcess    ) {$cbAttributes += 'SupportsShouldProcess=$true'}
        if ( $this.ConfirmImpact -in
             @("high","medium","low","none")) {$cbAttributes += "ConfirmImpact='$($this.ConfirmImpact)'" }
        elseif ($this.ConfirmImpact)          {throw ("Confirm Impact '{0}' is invalid. It must be High, Medium, Low, or None." -f $this.ConfirmImpact) }
        $theFunction = $theFunction.Replace("<#CBATTRIBUTES#>",   ($cbAttributes -join ","))
        #endregion

        #region insert any function attributes to appear with [cmdletbinding()]
        $functionAttributes   = ""
        if ( $this.Elevation.Command -and
                 $EmitAttribute ) {$functionAttributes +=  "  [PowerShellCustomFunctionAttribute(RequiresElevation=`$true)]`n" }
        elseif ( $EmitAttribute ) {$functionAttributes +=  "  [PowerShellCustomFunctionAttribute(RequiresElevation=`$false)]`n" }
        if ($this.Aliases)        {$functionAttributes +=  "  [Alias('" + ($this.Aliases -join "','")  +"')]`n"}
        $thefunction = $theFunction.Replace("<#FUNCTIONATTRIBUTES#>",  $functionAttributes)
        #endregion

        #region insert parameters in param () block, and populate the parametermap and Outputhandlers hashtables in the begin{} block
        $paramlist             = @()
        $parameterMap          = ""
        foreach ($p in $this.Parameters) {
            $paramlist        += "`n" + $p.ToString()
            $parameterMap     += $Script:ParameterTemplate -f $p.Name, $p.OriginalName, $p.OriginalPosition,  $p.ParameterType, $p.ApplyToExecutable, $p.NoGap
            if ($p.DefaultValue) {
                $parameterMap += "            DefaultValue        = '$($p.DefaultValue)'`n"
            }
            if ($p.DefaultMissingValue) {
                $parameterMap += "            DefaultMissingValue = '$($p.DefaultMissingValue)'`n"
            }
            if ($p.ValueMap.keys.count) {
                $mapItems      = @()
                foreach ($k in $p.valuemap.keys) {
                    $mapitems += "'{0}' = '{1}'" -f $k, ($p.valuemap[$k] -replace "'","''")
                }
                $parameterMap += "            ValueMap            = @{ " + ($mapitems -join '; ') + " }`n"
            }
            $parameterMap     += "        }`n"
        }
        if ($parameterMap)     {$parameterMap   = "`n$parameterMap" }
        if ($paramlist.count)  {$paramlist[-1] += "`n"}
        $thefunction           = $theFunction.Replace("<#PARAMLIST#>", ($paramlist -join ',')).replace("<#PARAMETERMAP#>", $parameterMap)

        if   ( -not $this.OutputHandlers) {
            $handlerText       = '        Default = @{ StreamOutput = $true; Handler = { $input } } ' }
        else {
            $handlerText       = "`n"
            foreach($handler in $this.OutputHandlers) {
                $handlerText  += $handler.ToString() + "`n"}
        }
        $theFunction           = $theFunction.Replace("<#HANDLERMAP#>", $handlerText)
        #endregion

        #region add platform check to begin block
        $platformCheck = ""
        if ($this.Platform.Count -ne 0) {               # ISWindows doesnot work on PS5. On PS5 $IsLinux and $IsMacOS will be null and therefore false.
            if ($this.Platform -notcontains "Windows") {$platformCheck += "`n    if ([System.Environment]::OSVersion.Platform -match '^Win')  {throw 'This functon does not support <#ORIGINALNAME#> on Windows.'}"}
            if ($this.Platform -notcontains "Linux")   {$platformCheck += "`n    if (`$IsLinux) {throw 'This functon does not support <#ORIGINALNAME#> on Linux.'}"}
            if ($this.Platform -notcontains "MacOS")   {$platformCheck += "`n    if (`$IsMacOS) {throw 'This functon does not support <#ORIGINALNAME#> on MacOS.'}"}
        }
        $theFunction = $theFunction.Replace("<#PLATFORMCHECK#>", $platformCheck)
        #endregion

        #region add any original command elements (parameters that are always specified for this version of the command) and code to add arguments before/after them if required.
        if ($this.parameters.where({$_.ApplyToExecutable}))   {$argBuilder  = $script:earlyParameters}
        else                                                  {$argBuilder  = "`n"}
        if ($this.OriginalCommandElements)                    {
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

        #region add the command invocation to the template - unlesss NoInvocation is specified
        if   ( $this.NoInvocation ) { $theFunction  = $thefunction.Replace('<#COMMANDBLOCK#>', '    return $commandArgs')}
        else {
            $commandBlock = $script:cmdblockStart
            if ($this.SupportsShouldProcess) {$commandBlock += $script:cmdblockProcess}
            else                             {$commandBlock += $script:cmdblockAlways }
            if   ( $this.Elevation.Command ) {
                    $elevationArgs    =  $($this.Elevation.Arguments | Foreach-Object { "{0} {1}" -f $_.OriginalName, $_.DefaultValue }) -join " "
                    $theCommand       = '"{0}" {1} "{2}" $commandArgs' -f $this.Elevation.Command, $elevationArgs, $this.OriginalName
             }
            else {  $theCommand       = '"{0}" $commandArgs'           -f  $this.OriginalName }
            $commandblock = $commandBlock.Replace("<#THECOMMAND#>",$theCommand).Replace("<#PRERUNMESSAGE#>",($theCommand.Replace('"','""')))
            $theFunction  = $thefunction.Replace('<#COMMANDBLOCK#>', $commandBlock)
        }
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

function Export-Schema     {
    $sGen = [Newtonsoft.Json.Schema.JsonSchemaGenerator]::new()
    $sGen.Generate([command])
}

function Test-Handler      {
    <#
        .SYNOPSIS
            function to test whether there is a parser error in the output handler
    #>
    param (
        [Parameter(Mandatory=$true)][string]$script,
        [Parameter(Mandatory=$true)][ref]$parserErrors
    )
    $null = [Language.Parser]::ParseInput($script, [ref]$null, $parserErrors)
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

function New-UsageInfo     {
    [alias('CrescendoSynopsis')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions","")]
    param (
        [Parameter(Position=0,Mandatory=$true)][string]$usage
    )
    [UsageInfo]::new($usage)
}

function New-ExampleInfo   {
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
        [ValidateSet('Inline','Script','Function')]
        [Alias('Type')]
        $HandlerType = 'Function',
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
        [Parameter(Position=2)][string]$OriginalName,
        [Parameter(Position=3)][List[ParameterInfo]] $Parameters,
        # e.g. "cubectl get user" -> "get", "user"
        [string[]]$OriginalCommandElements,
        [OutputHandler[]]$OutputHandlers,
        [string]$Description,
        [UsageInfo]$Usage,
        [List[ExampleInfo]]$Examples,
        [string]$OriginalText,
        [string[]]$HelpLinks,
        [ValidateSet("Windows","Linux","MacOS")]
        [string[]]$Platform     = @("Windows","Linux","MacOS"),
        [Elevation]$Elevation,
        [string[]]$Aliases,
        [string]$DefaultParameterSetName,
        [string]$ConfirmImpact,
        [switch]$SupportsShouldProcess,
        [switch]$SupportsTransactions,
        # certain scenarios want to use the generated code as a front end. When true, the generated code will return the arguments only.
        [switch]$NoInvocation
    )
    New-Object -TypeName Command -ArgumentList  $Verb, $Noun -Property $PSBoundParameters
}

function Export-CrescendoCommand {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true)]
        [Command[]]$Command,
        [Alias('TargetDirectory')]
        [string]$Path = $pwd.path,
        [alias('pt')]
        [switch]$PassThru
    )
    process {
        $filesAllowed = @{}
        foreach($crescendoCommand in $Command) {
            if (Test-Path -Path $Path -PathType Container) {
                $exportPath = Join-Path -Path  $Path -ChildPath "$($crescendoCommand.Verb)-$($crescendoCommand.Noun).crescendo.json"
            }
            elseif (Test-Path -IsValid $Path -PathType Leaf) {$exportPath = $Path}
            else   {throw "$Path must be a direcory or a valid file path."}

            #if we have already sent something to this file add ",", newline, and the JSON for this command - but don't close the JSON yet.
            if ($filesAllowed.ContainsKey($exportPath)) {
                $filesAllowed[$exportPath] +=
                    ",`n        " + ($crescendoCommand.GetCrescendoConfiguration() -replace '\n',"`n        ")
            }
            #If not, check we are allowed to output to it, and add the opening and the first command but leave the JSON open.
            elseif ($PSCmdlet.ShouldProcess($exportPath)) {
                $filesAllowed[$exportPath] =
                     "{`n" +
                     "    `"`$schema`": `"https://aka.ms/PowerShell/Crescendo/Schemas/2021-11`",`n"+
                     "    `"Commands`": [`n        " +
                                   ($crescendoCommand.GetCrescendoConfiguration() -replace '\n',"`n        " )
            }
        }
    }
    end {
        foreach ($exportPath in $filesAllowed.Keys)  {
            #close the json that was left open when we added the command(s) and write the file
            Set-Content -Confirm:$false -Path $exportPath -Value ($filesAllowed[$exportPath] + "`n   ]`n}")
            if ($PassThru) {Get-item $exportPath}
        }
    }
}

function Test-IsCrescendoCommand {
    [CmdletBinding()]
    param   (
        [Parameter(ValueFromPipeline=$true,Mandatory=$true,Position=0)]
        [object[]]$Command
    )
    process {
        # loop through the commands and determine whether it is a Crescendo Function
        foreach( $cmd in $Command) {
            $fInfo = $null
            if ($cmd -is [FunctionInfo]) {$fInfo = $cmd}
            elseif ($cmd -is [string]) {
                $fInfo = Get-Command -Name $cmd -CommandType Function -ErrorAction Ignore
            }
            if(-not $fInfo) {
                Write-Error -Message "'$cmd' is not a function" -TargetObject "$cmd" -RecommendedAction "Be sure that the command is a function"
                continue
            }
            #  check for the PowerShellFunctionAttribute and report on findings
            $crescendoAttribute = $fInfo.ScriptBlock.Attributes | Where-Object {$_.TypeId.Name -eq "PowerShellCustomFunctionAttribute"} | Select-Object -Last 1
            [CrescendoCommandInfo]::new($fInfo.Source, $fInfo.Name, $crescendoAttribute)
        }
    }
}

function Import-CommandConfiguration {
    [CmdletBinding()]
    param (
        [Parameter(Position=0,Mandatory=$true)]
        [Alias('File')]
        [string]$Path
    )
    # this dance is to support multiple configurations in a single file
    # The deserializer doesn't seem to support creating [command[]]
    $objects = Get-Content $Path -ErrorAction Stop | ConvertFrom-Json -depth 10
    if     ($objects.commands)                {$commands = $objects.commands }
    elseif ($objects.verb -and $objects.noun) {$commands = $objects}
    else   {throw "$Path does not appear to contain suitable JSON"}
    $options = [System.Text.Json.JsonSerializerOptions]::new()
    foreach ($c in $commands) {
        $jsonText      = $c | ConvertTo-Json -depth 10
        $errs          = $null
        $configuration = [System.Text.Json.JsonSerializer]::Deserialize($jsonText, [command], $options)
        if (-not (Test-Configuration -configuration $configuration -errors ([ref]$errs))) {
                $errs  | Foreach-Object { Write-Error -ErrorRecord $_ }
        }
        # emit the configuration even if there was an error
        $configuration
    }
}

function Test-Configuration {
    param (
        [Command]$Configuration,
        [ref]$errors
    )

    $configErrors     = @()
    $configurationOK  = $true

    # Validate the Platform types
    $allowedPlatforms = "Windows","Linux","MacOS"
    foreach($platform in $Configuration.Platform) {
        if ($allowedPlatforms -notcontains $platform) {
            $configurationOK = $false
            $configErrors   += [ErrorRecord]::new(
                [Exception]::new("Platform '$platform' is not allowed. Use 'Windows', 'Linux', or 'MacOS'"),
                "ParserError", "InvalidArgument", "Import-CommandConfiguration:Platform")
        }
    }

    # Validate the output handlers in the configuration
    foreach ( $handler in $configuration.OutputHandlers ) {
        $parserErrors = $null
        if ( -not (Test-Handler -Script $handler.Handler -ParserErrors ([ref]$parserErrors))) {
            $configurationOK  = $false
            $configErrors += [ErrorRecord]::new(
                ([Exception]::new("OutputHandler Error '$($parserErrors[0].Message)' in '$($configuration.FunctionName)' for ParameterSet '$($handler.ParameterSetName)'")),
                "Import-CommandConfiguration:OutputHandler","ParserError",$parserErrors)
        }
    }
    if ($configErrors.Count -gt 0) {$errors.Value = $configErrors}
    return $configurationOK

}

function Export-CrescendoModule {
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName='Files')]
    param   (
        [Parameter(Position=0,Mandatory=$true)]
        [alias('Name')]
        [string]$ModuleName,

        [Parameter(Position=1,ValueFromPipeline=$true,ParameterSetName='Files',Mandatory=$true)]
        [SupportsWildcards()]
        [string[]]$ConfigurationFile,

        [Parameter(ParameterSetName='CommandObjects',Mandatory=$true)]
        [Command[]]$Commands,
        [alias('PT')]
        [switch]$PassThru,
        [switch]$Force
    )
    #Import the parameters from New-ModuleManifest
    DynamicParam {
        $paramDictionary     =    New-Object -TypeName RuntimeDefinedParameterDictionary
        $attributeCollection =    New-Object -TypeName System.Collections.ObjectModel.Collection[System.Attribute]
        $attributeCollection.Add((New-Object -TypeName ParameterAttribute -Property @{ ParameterSetName = "__AllParameterSets" ;Mandatory = $false}))
        foreach ($P in (Get-Command -Name New-ModuleManifest).Parameters.values.where({$_.name -notmatch 'DSC|PassThru|Verbose|Debug|Action$|Variable$|OutBuffer|Confirm|Whatif|Path'}))  {
            $paramDictionary.Add($p.Name, (New-Object -TypeName RuntimeDefinedParameter -ArgumentList $p.name, $p.ParameterType, $attributeCollection ) )
        }
        return $paramDictionary
    }

    begin   {
        $crescendoCollection = @()
        if ($ModuleName    -match '\.psd1$')          { $ModuleName  = $ModuleName -replace '\.psd1$', '.psm1'}
        if ($ModuleName -notmatch '\.psm1$')          { $ModuleName += '.psm1'}
        if ((Test-Path $ModuleName) -and -not $Force) {throw "$ModuleName already exists"}
        if (-not ($Force -or $PSCmdlet.ShouldProcess($ModuleName,'Create Module'))) {
            $DontWrite = $true
        }
        else {  # Add the  static parts of the crescendo module
            Set-Content -Path $ModuleName -Value $script:ModuleStart -Confirm:$false
            $moduleBase = [System.IO.Path]::GetDirectoryName($ModuleName)
        }
    }
    process {
        if ($Commands) {$crescendoCollection = $Commands}
        else {
            #expand wildcards and report as file is processed
            $resolvedConfigurationPaths = (Resolve-Path $ConfigurationFile).Path
            foreach($file in $resolvedConfigurationPaths) {
                Write-Verbose "Adding $file to Crescendo collection"
                $crescendoCollection += Import-CommandConfiguration $file
            }
        }
    }
    end     {
        $psdPath                 = $ModuleName -Replace "psm1$","psd1"
        $ModuleManifestArguments = @{
                    Path              =  $psdPath
                    CmdletsToExport   = @()
                    VariablesToExport = @()
                    Tags              = @()
                    PrivateData       = @{}
        }
        if (Test-Path $psdPath)  {
            $existing = Import-PowerShellDataFile -Path $psdPath
            $existing.keys.where({$_ -in (Get-Command -Name New-ModuleManifest).Parameters.keys }).foreach({
                    $ModuleManifestArguments[$_] = $existing[$_]
            })
            if ($existing.PrivateData.PSData) {
                $existing.PrivateData.PSData.keys.where({$_ -in (Get-Command -Name New-ModuleManifest).Parameters.keys }).foreach({
                    $ModuleManifestArguments[$_] = $existing.PrivateData.PSData[$_]
                })
                [void]$ModuleManifestArguments.PrivateData.remove('PSData')
            }
        }
        #reset properties if they  were in an existing PSD1
        $ModuleManifestArguments['AliasesToExport']                = @() + $crescendoCollection.Aliases
        $ModuleManifestArguments['FunctionsToExport']              = @() + $crescendoCollection.FunctionName
        $ModuleManifestArguments['PowerShellVersion']              = "5.1.0"
        $ModuleManifestArguments['RootModule']                     = [System.io.path]::GetFileName(${ModuleName})
        $ModuleManifestArguments.PrivateData['CrescendoVersion']   = (Get-Module Microsoft.PowerShell.Crescendo).Version
        $ModuleManifestArguments.PrivateData['CrescendoGenerated'] =  Get-Date -Format 'o' # unambiguous format
        if ($ModuleManifestArguments.Tags -notcontains 'CrescendoBuilt' ) {
            $ModuleManifestArguments.Tags     +=     @('CrescendoBuilt')
        }

        #Extra functions and/or aliases can be passed via the cmdline.
        $psboundParameters.keys.where({$_ -notmatch 'Verbose|Debug|PassThru|Action$|Variable$|OutBuffer|Confirm|Whatif|Commands|ConfigurationFile|ModuleName|Force'}).foreach({
            $ModuleManifestArguments[$_] = $PSBoundParameters[$_]
        })
        if ($psboundParameters['WhatIf']) {
            $ModuleManifestArguments | Out-String |  Write-Verbose -Verbose
        }
        if ($DontWrite) {return}
        # insert the windows elevation helper if it is called
        if ($crescendoCollection.Elevation.Command -eq "Invoke-WindowsNativeAppWithElevation") {
            "function Invoke-WindowsNativeAppWithElevation {`n"  +
            $InvokeWindowsNativeAppWithElevationFunction + "`n}" >> $ModuleName
        }
        #Get the helper functions needed for everything in the collection, use a hash table to auto-deduplicate
        $helpers = [ordered]@{}
        foreach ($proxy in $crescendoCollection) {
            $proxyHelpers = $proxy.GetHelperFunctions()
            foreach ($k in $proxyHelpers.keys) {$helpers[$k] = $proxyHelpers[$k]}
        }
        #Output the helper functions first, then the functions we build with the Crescendo attribute and skipping their helpers
        foreach ($k in $helpers.keys) {$helpers[$k] + "`n" >> $ModuleName}
        foreach ($proxy in $crescendoCollection) {$proxy.ToString($true,$true) >> $ModuleName}
        #todo build filelist.
        New-ModuleManifest @ModuleManifestArguments
        if ($PassThru) {Get-item $ModuleManifestArguments.Path}
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
