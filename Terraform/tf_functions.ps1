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

        $result = $text =  | ConvertFrom-Json
        $result.values.root_module | expandTfModule -tfVersion $result.terraform_version | Where-Object -Property address -Like $Address
    }
}