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

function tfVersionJsonToObject {
  $tfver = $input | ConvertFrom-Json -AsHashtable
  $providers =  $tfver.provider_selections.Keys | ForEach-Object { [pscustomObject]@{Provider=$_;Version=$tfver.provider_selections[$_]}}
  [Pscustomobject][ordered]@{
                    Platform  = $tfver.platform
                    Version   = $tfver.terraform_version
                    OutDated  = $tfver.terraform_outdated
                    Providers = $Providers }    | Add-Member -TypeName TerraformVersion -PassThru
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