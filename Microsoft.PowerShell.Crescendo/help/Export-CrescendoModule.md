---
external help file: Microsoft.PowerShell.Crescendo-help.xml
Module Name: Microsoft.PowerShell.Crescendo
ms.date: 03/16/2021
online version: https://docs.microsoft.com/powershell/module/microsoft.powershell.crescendo/export-crescendomodule?view=ps-modules.1&WT.mc_id=ps-gethelp
schema: 2.0.0
---

# Export-CrescendoModule

## SYNOPSIS
Creates a module from PowerShell Crescendo JSON configuration files

## SYNTAX

```
Export-CrescendoModule [-ModuleName] <String>  [-ConfigurationFile] <String[]> [-Force] [-PassThru]
                       [-WhatIf] [-Confirm]  [<CommonParameters>][<CommonParameters>]
                       [-AliasesToExport <string[]>] [-Author <string>] [-ClrVersion <version>] [-CmdletsToExport <string[]>]
                       [-CompatiblePSEditions <string[]>] [-CompanyName <string>] [-Copyright <string>] 
                       [-DefaultCommandPrefix <string>]  [-Description <string>] [-DotNetFrameworkVersion <version>]
                       [-ExternalModuleDependencies <string[]>] [-FileList <string[]>] [-FormatsToProcess <string[]>]
                       [-FunctionsToExport <string[]>] [-Guid <guid>] [-HelpInfoUri <string>]  [-IconUri <uri>]
                       [-LicenseUri <uri>] [-ModuleList <Object[]>] [-ModuleVersion <version>] [-NestedModules <Object[]>]  
                       [-ProcessorArchitecture {None | MSIL | X86 | IA64 | Amd64 | Arm}] [-PowerShellHostName <string>]
                       [-PowerShellHostVersion <version>] [-PowerShellVersion <version>] [-Prerelease <string>] 
                       [-PrivateData <Object>] [-Tags <string[]>] [-ProjectUri <uri>]  [-ReleaseNotes <string>] 
                       [-RequiredAssemblies <string[]>]   [-RequireLicenseAcceptance]  [-RequiredModules <Object[]>] 
                       [-TypesToProcess <string[]>]  [-ScriptsToProcess <string[]>]  [-VariablesToExport <string[]>]  

```

## DESCRIPTION

This cmdlet creates a module manifest (PSD1) and a root file (PSM1) from a JSON file which describes one
or more functions that proxy requests to a platform specific command. 
The resultant module should be executable down to version 5.1 of PowerShell.

## EXAMPLES

### EXAMPLE 1

```
PS> Export-CrescendoModule -ModuleName netsh -ConfigurationFile netsh*.json
PS> Import-Module ./netsh.psm1

Creates a new module named "netsh" using JSON files with names beginning "netsh", and imports the new module.  
```

### EXAMPLE 2

```
PS> Export-CrescendoModule netsh netsh*.json -force

Rebuilds the previous module. Unless -Force is specified the module will **not** be overwritten 
```

### EXAMPLE 3

```
PS>  Export-CrescendoModule -Commands $getWidget, $setWidget -ModuleName widget -ProjectUri "https://contoso.com/widgets" -PassThru  | Import-Module 

Creates a module using two command objects, sets an extra value in the module manifest (the project URI) and outputs the module file, directly into the module, loading it. 
```


## PARAMETERS

### -ConfigurationFile

This is a list of files which contain JSON representations of the proxy-commands to include in the module

```yaml
Type: System.String[]
Parameter Sets: (All)
Aliases:

Required: True
Position: 2
Default value: None
Accept pipeline input: True (ByPropertyName)
Accept wildcard characters: True
```

### -Force

By default, `Export-CrescendoModule` will not overwrite a pre-existing Module. Use the **Force**
parameter to overwrite the existing file, or remove it prior to running `Export-CrescendoModule`.

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ModuleName

The name of the module file you wish to create. You can omit the trailing `.psm1`/`.psd1`

```yaml
Type: System.String
Parameter Sets: (All)
Aliases:

Required: True
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -Confirm

Prompts you for confirmation before running the cmdlet.

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -PassThru

If specified returns the file for the newly created module.

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -WhatIf

Shows what would normally happen if the cmdlet runs. No files are altered if -WhatIf is specified.

```yaml
Type: System.Management.Automation.SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

### -AliasesToExport

The module manifest automatically contains the list of aliases defined for the proxy functions.
If specified as a parameter this will add extra aliases to the list.

### -FunctionsToExport

The module manifest automatically contains the list of  proxy functions.
If specified as a parameter this will add extra functions to the list

### -PowerShellVersion

By default the module manifest requires a minimum of PowerShell 5.1; specifying it as a parameter will override this.

### -PrivateData

The command adds the crescendo version and build date to the Manifest's "Private Data" section. 
This parameter allows additional entries to be specified as a hash table

### -Author

Inherited from New-Module Manifest

### -ClrVersion

Inherited from New-Module Manifest

### -CmdletsToExport

Inherited from New-Module Manifest

### -CompatiblePSEditions

Inherited from New-Module Manifest

### -CompanyName

Inherited from New-Module Manifest

### -Copyright

Inherited from New-Module Manifest

### -DefaultCommandPrefix

Inherited from New-Module Manifest

### -Description

Inherited from New-Module Manifest

### -DotNetFrameworkVersion

Inherited from New-Module Manifest

### -ExternalModuleDependencies

Inherited from New-Module Manifest

### -FileList

Inherited from New-Module Manifest

### -FormatsToProcess

Inherited from New-Module Manifest

### -Guid

Inherited from New-Module Manifest

### -HelpInfoUri

Inherited from New-Module Manifest

### -IconUri

Inherited from New-Module Manifest

### -LicenseUri

Inherited from New-Module Manifest

### -ModuleList

Inherited from New-Module Manifest

### -ModuleVersion

Inherited from New-Module Manifest

### -NestedModules

Inherited from New-Module Manifest

### -ProcessorArchitecture

Inherited from New-Module Manifest

### -PowerShellHostName

Inherited from New-Module Manifest

### -PowerShellHostVersion

Inherited from New-Module Manifest

### -Prerelease

Inherited from New-Module Manifest

### -ProjectUri

Inherited from New-Module Manifest

### -ReleaseNotes

Inherited from New-Module Manifest

### -RequiredAssemblies

Inherited from New-Module Manifest

### -RequireLicenseAcceptance

Inherited from New-Module Manifest

### -RequiredModules

Inherited from New-Module Manifest

### -TypesToProcess

Inherited from New-Module Manifest

### -ScriptsToProcess

Inherited from New-Module Manifest

### -VariablesToExport

Inherited from New-Module Manifest


### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutVariable, -OutBuffer, -PipelineVariable, -Verbose,
-WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](http://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### None

## NOTES

Internally, this command calls `Import-CommandConfiguration`, which returns command objects
created from the JSON files provided in the **ConfigurationFile** parameter.
Each of these object is translated into the PowerShell script to implement the individual functions
which act as proxies for the native command. This script, any "helper" code is  written to
a .PSM1 file. Finally the command creates a module manifest which loads the PSM1, and exports 
commands and their aliases.

## RELATED LINKS

[Import-CommandConfiguration](Import-CommandConfiguration.md)
New-ModuleManifest
