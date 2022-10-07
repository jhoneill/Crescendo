# PowerShell Crescendo

So what is my fork which isn't in the original?

## Changes to build process

- `Export-CrescendoCommand` now exports JSON with a `commands` section as expected by `Import-CommandConfiguration` and `Import-CommandConfiguration` also reads json with single items (without a `commands` section)
- `Export-CrescendoCommand` will take a file-path as well as directory, and will put multiple commands in the same `commands` block if given a file path. It continues to make individual files if no path or a directory is given.
- `Export-CrescendoModule ` supports additional parameters for `New-ModuleManifest` and preserves entries in any existing PSD1 file, for example:    
  `Export-CrescendoModule .\terraform.crescendo.json -ModuleName Terrorfarm  -ModuleVersion 0.0.2 -Tags terraform -Force`    
  will update an existing module version to 0.0.2, keep the company and similar settings from the existing psd file, and give it the tags "terraform" and "CrescendoBuilt"
- `Export-CrescendoModule ` Can now export command objects without converting them to JSON first.
- `Export-CrescendoModule ` Also de-duplicates helper functions. This required an additional version of \[command\].ToString() with option to output *without* helper functions and new method \[command\].GetHelperFunctions() to return a hash-table of function-name = function-body
- Output Handlers now have a default ParameterSet of "Default" - blank sets caused problems  
- The build process now has the bulk of the code to be output in here-strings at the top of the file, and ALL the string builder line-by-line build-ups have been removed. They made it impossible to see the function structure. String builder is a benefit when building very large strings in hundreds or thousands of parts. The number and size operations here don't benefit from it and in fact this version is faster (100ms vs 589 to build the set of 6 commands I'm using as a test).
- Variable names, and layout have been made consistent (there was a mix of brace styles, and multiple variable naming conventions)

## Changes to output

The following are functional changes to the output, rather than changes of case, spacing, renaming variables, adding `#region` and other comment changes or other tidying up. 
- Help
  - Putting the multi-line output of `command -?` into synopsis has been removed, because (a) Synopsis should be a single line, and (b) it told people how to use a different command
  - Fixed Help not building correctly if synopsis was present without a description.
  - Help now appears at the start of a function, not the end.
- PreLaunch
  - Added a method of saying "this parameter is only used in the PowerShell wrapper don't send it to the command" for now this is done by giving the original position as a negative number. 
  - Added support for "value-maps" e.g. `{"Reduced": "r", "None": "n", "Basic": "b", "Full": "f"}` creates
    `[ValidateSet('Basic', 'Reduced', 'None', 'Full')]`, and translates those fullnames to the initials in the map.
  - Added a check for the correct OS when a command is marked as Linux/Mac/Windows only
  - Moved the location of the test for presence of the command-to-be-launched to an earlier point.
  - Code to add arguments from parameters before and after fixed arguments has been cleaned up. Common parts have been moved to a helper function, and code is omitted when the definition has no "before" and/or no "after" items .
  - `Wait-Debugger` is only invoked once. 
- Command launching
  - Modified process for handler functions to allow `| function -param1 -param2 value $input`; this will be wrapped in `& {}` so the function needs to support input as a parameter. Combined with the use of wrapper-only parameters this allows `value` to be passed as a parameter.  
  - `if ($psCmdlet.shouldProcess ...` is now only included if if ShouldProcess is if specified for the command
  - `if ($verbose) {write-verbose-verbose  <whatever the command is> }` has been replaced with Write-Verbose when ShouldProcess is NOT present.
