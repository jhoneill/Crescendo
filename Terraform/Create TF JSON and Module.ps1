. .\tf_functions.ps1
$tfv                = New-crescendoCommand -OriginalName terraform  -OriginalCommandElements "version", "-json" -Verb Get       -Noun TerraformVersion  -Aliases "Get-TFVersion","tfVersion" -Usage "Gets the terraform version"
$tfv.OutputHandlers = New-OutputHandler    -HandlerType  Function   -StreamOutput tfVersionJsonToObject

$tfp                = New-crescendoCommand -OriginalName terraform  -OriginalCommandElements "plan",    "-json" -Verb New       -Noun TerraformPlan     -Aliases "New-TFPlan","tfPlan"       -Usage "Builds a new terraform plan from the current configuration" -Description "Calls terraform plan, optionally with -Destroy and -Out <file> options, returns planned steps as objects."
$tfp.OutputHandlers = New-OutputHandler    -HandlerType  Function   -StreamOutput tfPlanJsonToObject
$tfp.Parameters = @(
                      New-ParameterInfo    -OriginalName "-out"     -OriginalPosition 0  -ParameterType string  -Name OutFile   -Position 0
                      New-ParameterInfo    -OriginalName "-destroy" -OriginalPosition 1  -ParameterType switch  -Name Destroy
)
$tfg                = New-CrescendoCommand -OriginalName terraform  -OriginalCommandElements "graph"            -Verb New       -Noun TerraformGraph     -Aliases "New-TFGraph","tfGraph"    -Usage "Draws a graph of the resources in the current configuration" -Description "Calls terraform graph, if the PSGraphModule is present converts the graphviz output to something viewable"
$tfg.OutputHandlers = New-OutputHandler    -HandlerType  Function   -StreamOutput 'rendertfgraph -Path $Path -ShowGraph:$ShowGraph $input'
$tfg.parameters = @(
                      New-ParameterInfo    -OriginalName ""         -OriginalPosition -1 -ParameterType string  -Name Path      -Position 0
                      New-ParameterInfo    -OriginalName ""         -OriginalPosition -1 -ParameterType switch  -Name ShowGraph
)

# Export-CrescendoCommand $tfp,$tfv,$tfg -PassThru | Export-CrescendoModule -ModuleName TF -Force -ProjectUri "https://github.com/jhoneill/Crescendo/tree/James"
Export-CrescendoModule -Commands $tfp, $tfv, $tfg -ModuleName TF-AllInOne -Force -ProjectUri "https://github.com/jhoneill/Crescendo/tree/James" -PassThru | Import-Module -Verbose
