# PowerShell Crescendo

So what is my fork which isn't in the original?

## Changes to build process

- `Export-CrescendoCommand`  now exports JSON with a commands section as expected by `Import-CommandConfiguration` and `Import-CommandConfiguration` also reads single items
- `Export-CrescendoCommand`  will take a file path as well as directory; and will put multiple commands in the same commands block if given a file path. It continues to make individual one if no path or a directory is given.
- `Export-CrescendoModule`   Supports additional parameters for New-ModuleManifest and preserves entries in any existing PSD1 file
- `Export-CrescendoModule`   Can now export command objects without converting them to JSON first.
- `Export-CrescendoModule`   Also de-duplicates helper functions. This required an additional version of \[command\].ToString() with option to output *without* helper functions and new method \[command\].GetHelperFunctions() to return a hash-table of function-name = function-body
- Output Handlers now have a default parameter set of "Default" - blank sets caused problems  
- The build process now has the bulk of output in here-strings at the top of the file, and ALL the string builder line by line build-ups have been removed. They made it impossible to see the function structure, and made things slower. (String builder is a benefit when doing hundreds or thousands of string concatenate operations).
- Variable names, and layout have been made consistent (there was a mix of brace styles, and multiple variable naming conventions)

## Changes to output

- Help
  - Putting the multi-line output of `command -?` into synopsis has been removed, because (a) Synopsis should be a single line, and (b) it told people how to use a different command
  - Fixed Help not building correctly if synopsis was present without a description.
  - Help now appears at the start of a function, not the end.
- PreLaunch
  - Added support for "value-maps" e.g. `{"Reduced": "r", "None": "n", "Basic": "b", "Full": "f"}` creates
    `[ValidateSet('Basic', 'Reduced', 'None', 'Full')]`, and translates those to the initials in the map.
  - Added a check for the correct OS when a command is marked as Linux/Mac/Windows only
  - Moved the location of the test for presence of the command-to-be-launched to an earlier point.
  - Code to add arguments from parameters before and after fixed arguments has been cleaned up. Common parts have been moved to a helper function, and code is omitted when the definition has no "before" and/or no "after" items .
- Command launching
  - Fixed an error for non streamed output when the command returns nothing and runs `handler $result` with a null result
  - Modified process for functions so a handler can be `| function -param1 -param2 value` 
  - `if ($psCmdlet.shouldProcess ...` is now only included if if ShouldProcess is if specified for the command
  - `if ($verbose) {write-verbose-verbose  <whatever the command is> }` has been replaced with Write-Verbose when ShouldProcess is NOT present.
