<#
.SYNOPSIS
  Workspace ONE Check Add Remove Programs, reads Win32 conditions and properties from the registry, updates registry if deviation found.
.DESCRIPTION
  This script tries to cover the missing capability of Workspace ONE UEM to regualary check if Win32 Applications have been uninstalled by users/admins. 
  It is going through all records within HKLM:\SOFTWARE\AirWatchMDM\AppDeploymentAgent\AppManifests and reads the DETECT conditions as well as associated
  properties. It resolve all properties to either True or False (eg. Registry Key match Value X) and concludes by re-building the condition chain.
  (eg. Property1 AND Property2 OR Propery3). If this is done the script then checks the IsInstalled value HKLM:\SOFTWARE\AirWatchMDM\AppDeploymentAgent\S-1-5-18\$($AppId)
  and updates the value to the detected state. There is a $run_as_sensor variable which basically suppress all outputs except on at the end in order
  to run this script as Workspace ONE Sensor on Trigger or Schedule.
.PARAMETER <Parameter_Name>
    No parameters yet
.INPUTS
  None
.OUTPUTS
  Console output only, maybe create a log file in an upcoming version
.NOTES
  Version:        1.0
  Author:         Alexander Askin
  Creation Date:  25. May 2020
  Purpose/Change: Initial Release
  
.EXAMPLE
  WorkspaceONE_Check_Add_Remove_Programs_v1.ps1
#>

$xml = New-Object System.Xml.XmlDocument
$run_as_sensor = $false
if($run_as_sensor){
    $ras=$true
}else{
    $ras=$false
}
$script:corrections_made = 0

#removed WMI call as it is way too slow
#$msipackages = Get-WmiObject -Class win32_product

#getting all MSI packages from registry
$msipackages = @()
Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall | ForEach-Object {$msipackages += $_.PSChildName}
Get-ChildItem HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall | ForEach-Object {$msipackages += $_.PSChildName}

function Check-Registry ($Key, $SubKey, $ValueName, $ValueType, $Win64="true")  {
    $testresult = $false
    if($Win64){
        $FullPath = Join-Path -Path $($Key + ":") -ChildPath $SubKey
    }else{
        $FullPath = Join-Path -Path $($Key + ":") -ChildPath $SubKey.Replace("\SOFTWARE\","\SOFTWARE\WOW6432Node\")
    }

    if (Test-Path -Path $FullPath){
        $testresult = $true
        if((Get-ItemProperty -Path $FullPath).$ValueName){
            $testresult = (Get-ItemProperty -Path $FullPath).$ValueName
        }else{
            $testresult = $false
        }
    }
    return $testresult
}

function Check-File ($Path, $File, $MaxVersion="", $MinVersion="", $MinDate="1970-01-01T00:00:00") {
    $testresult = $false
    $FullPath = Join-Path $Path $File
    if (Test-Path -Path $FullPath){
        $testresult = $true
        if($MaxVersion){
            if((Get-Item $FullPath).VersionInfo.FileVersionRaw -gt $MaxVersion){
                $testresult = $false
            }
        }
        if($MinVersion){
            if((Get-Item $FullPath).VersionInfo.FileVersionRaw -lt $MinVersion){
                $testresult = $false
            }
        }
        if($MinVersion -eq $MaxVersion -and $MinVersion -and $MaxVersion){
            if((Get-Item $FullPath).VersionInfo.FileVersionRaw -eq $MinVersion){
                $testresult = $true
            }else{
                $testresult = $false
            }
        }
        if($MinDate){
            if((Get-Item $FullPath).CreationTime -lt $MinDate){
                $testresult = $false
            }
        }
    }
    return $testresult
}

function Check-MSIProduct ($MSIProductCode){
    return $msipackages.Contains($MSIProductCode)
}

function Get-AppProperties ($xml){
    $returnvalue = @{}
    foreach ($property in $xml.DeploymentManifest.Properties.Property){
        switch -Wildcard($property.Id.ToString()){
            "PRODUCTCODE" {
                if(!$ras){Write-Host $property.Id.ToString() -ForegroundColor Cyan}
                if(!$ras){write-host "  PRODUCTCODE:"$property.MSIQuery.Productcode}
                $returnvalue += @{$property.Id.ToString() = Check-MSIProduct $property.MSIQuery.Productcode}
                if(!$ras){Write-Host "->PRODUCTCODE-RESULT:"$returnvalue[$property.Id] -ForegroundColor Yellow}
                break
            }
            "Property*" {
                if(!$ras){Write-Host $property.Id.ToString() -ForegroundColor Cyan}
                switch($property.ChildNodes.ToString()){
                    "DirectoryQuery" {
                        if(!$ras){write-host "  DirectoryQuery-Path:"$property.DirectoryQuery.Path}
                        if(!$ras){write-host "  DirectoryQuery-Name:"$property.DirectoryQuery.FileQuery.Name}
                        if(!$ras){write-host "  DirectoryQuery-MaxVersion:"$property.DirectoryQuery.FileQuery.MaxVersion}
                        if(!$ras){write-host "  DirectoryQuery-MinVersion:"$property.DirectoryQuery.FileQuery.MinVersion}
                        if(!$ras){write-host "  DirectoryQuery-MinDate:"$property.DirectoryQuery.FileQuery.MinDate}
                        $returnvalue += @{$property.Id.ToString() = Check-File $property.DirectoryQuery.Path $property.DirectoryQuery.FileQuery.Name $property.DirectoryQuery.FileQuery.MaxVersion $property.DirectoryQuery.FileQuery.MinVersion $property.DirectoryQuery.FileQuery.MinDate}
                        if(!$ras){Write-Host "->DirectoryQuery-RESULT:"$returnvalue[$property.Id] -ForegroundColor Yellow}
                        break
                    }
                    "RegistryQuery" {
                        if(!$ras){write-host "  RegistryQuery-Key:"$property.RegistryQuery.Key}
                        if(!$ras){write-host "  RegistryQuery-SubKey:"$property.RegistryQuery.SubKey}
                        if(!$ras){write-host "  RegistryQuery-ValueName:"$property.RegistryQuery.ValueName}
                        if(!$ras){write-host "  RegistryQuery-ValueType:"$property.RegistryQuery.ValueType}
                        if(!$ras){write-host "  RegistryQuery-Win64:"$property.RegistryQuery.Win64}
                        $returnvalue += @{$property.Id.ToString() = Check-Registry $property.RegistryQuery.Key $property.RegistryQuery.SubKey $property.RegistryQuery.ValueName $property.RegistryQuery.ValueType $property.RegistryQuery.Win64}
                        if(!$ras){Write-Host "->RegistryQuery-RESULT:"$returnvalue[$property.Id] -ForegroundColor Yellow}
                        break
                    }
                    "MSIQuery" {
                        if(!$ras){write-host "  PRODUCTCODE:"$property.MSIQuery.Productcode}
                        $returnvalue += @{$property.Id.ToString() = Check-MSIProduct $property.MSIQuery.Productcode}
                        if(!$ras){Write-Host "->PRODUCTCODE-RESULT:"$returnvalue[$property.Id] -ForegroundColor Yellow}
                        break
                    }
                }
            }
        }
    }
    return $returnvalue
}

function Update-AppStatus ($AppId, $IsInstalled){
    if(Test-Path HKLM:\SOFTWARE\AirWatchMDM\AppDeploymentAgent\S-1-5-18\$($AppId.ToUpper())){
        $FullPath = Join-Path -Path "HKLM:\SOFTWARE\AirWatchMDM\AppDeploymentAgent\S-1-5-18\" -ChildPath $($AppId.ToUpper())
    }else{
        if(!$ras){Write-Host "Could not find: HKLM:\SOFTWARE\AirWatchMDM\AppDeploymentAgent\S-1-5-18\$($AppId.ToUpper()) - User-Installed App - SKIPPED" -ForegroundColor Red}
    }
    if($FullPath){
        $registry_value = [System.Convert]::ToBoolean((Get-ItemProperty $FullPath).IsInstalled)
        if($IsInstalled -eq $registry_value){
            if(!$ras){Write-Host "Registry is already correctly set to:"$registry_value -ForegroundColor Green}
        }else{
            if(!$ras){Write-Host "Registry $FullPath Update needed set from $registry_value to: " -NoNewline}
            if(!$ras){Write-Host $IsInstalled.ToString().ToLower() -ForegroundColor Cyan}
            Set-ItemProperty -Path $FullPath -Name "IsInstalled" -Value $IsInstalled.ToString().ToLower() -Force
            $registry_value = [System.Convert]::ToBoolean((Get-ItemProperty $FullPath).IsInstalled)
            if($IsInstalled -eq $registry_value){
                if(!$ras){Write-Host "Registry successfully corrected" -ForegroundColor Green}
                $script:corrections_made++
            }else{
                if(!$ras){Write-Host "Error while updating the Registry" -ForegroundColor Red}
            }
        }
    }
}

#Get-ChildItem HKLM:\SOFTWARE\AirWatchMDM\AppDeploymentAgent\AppManifests | Out-GridView -PassThru | ForEach-Object { #USE THIS FOR DEBUG, COMMENT NEXT LINE IF USED
Get-ChildItem HKLM:\SOFTWARE\AirWatchMDM\AppDeploymentAgent\AppManifests | ForEach-Object {

    $xml.LoadXML((Get-ItemProperty $_.PSPath).DeploymentManifestXML)
    if(!$ras){Write-Host Application:($xml.DeploymentManifest.Identity.Name) Version:($xml.DeploymentManifest.Identity.Version) Revision:($xml.DeploymentManifest.Identity.Revision) -ForegroundColor Yellow}
    foreach ($method in $xml.DeploymentManifest.Deploy.Method){
        if ($method.Id -eq "detect"){ # Looking for detect method
            $conditions = $method.Condition
            if(!$ras){Write-Host "CONDITION(s) XML: $conditions"}
            $appproperties = Get-AppProperties $xml
            $appproperties.GetEnumerator() | ForEach-Object {
                $conditions = $conditions.Replace($_.Name, $_.Value)
            }
            if(!$ras){Write-Host "CONDITION(s) TRANS:"($conditions)}
            $condition_parts = $conditions -Split " (AND) " -Split " (OR) "
            $finalresult = $false #Set the Final Restult to FALSE
            $prev_result = "" #Clear Previous RESULT from last for-loop
            $prev_operator = ""  #Clear Previous OPERATOR from last for-loop
            if(!$ras){Write-Host "CONDITION(s) CHAIN: " -NoNewline}
            foreach ($part in $condition_parts){
                $part = $part.Replace('(','') #remove all (
                $part = $part.Replace(')','') #remove all )
                if($part.Contains(" = ")){
                    $part = $part.Replace('"','') #remove all "
                    $subpart = $part -Split " = "
                    $addnot = "" #Clear NOT variable to save outcome
                    if($subpart[0].Contains("NOT")){
                        $subpart[0] = $subpart[0].Replace("NOT ","")
                        $addnot = "NOT " #restore the NOT information
                    }
                    if($subpart[0] -eq $subpart[1]){
                        $part = $($addnot) + $("True")
                    }else{
                        $part = $($addnot) + $("False")
                    }
                }

                if($part.Contains("NOT")){ #Flip True to False and False to True if NOT is given
                    $part = $part.Replace('NOT','')
                    $part = $part.Replace(' ','')
                    if($part -eq "True"){
                        $part = "False"
                    }elseif($part -eq "False"){
                        $part = "True"
                    }
                }

                if($part -eq "1"){$part = "True"} #Workspace ONE older rules just set 1 as True

                if($part -eq "AND" -or $part -eq "OR"){ #Take Logical Operator
                    $prev_operator = $part
                    if(!$ras){Write-Host $part" " -ForegroundColor Yellow -NoNewline}
                }elseif($part -eq "True"){ #When this is True asume that overall the condition is true
                    if(!$ras){Write-Host $part" " -ForegroundColor DarkCyan -NoNewline}
                    if($prev_operator -eq "AND" -and $prev_result -eq "False"){ 
                        $finalresult = $false
                        break #attemp to break, which does not work
                    }else{
                        $finalresult = $true
                    }
                    $prev_result = "True"
                }elseif($part -eq "False"){
                    if(!$ras){ Write-Host $part" " -ForegroundColor DarkCyan -NoNewline}
                    if($prev_result -eq "False"){
                        $finalresult = $false
                        break
                    }
                    if($prev_operator -eq "AND"){
                        $finalresult = $false
                        break
                    }
                    if($prev_operator -eq $null){
                        $finalresult = $false
                    }
                    $prev_result = "False"
                }else{
                    if(!$ras){Write-Host $part" " -ForegroundColor Yellow -NoNewline}
                }
            }
            if(!$ras){Write-Host " <- enough infos for decision are given" -ForegroundColor Gray}
            if($finalresult){
                if(!$ras){Write-Host ($xml.DeploymentManifest.Identity.Name) "Installed: True" -ForegroundColor Green}
                Update-AppStatus $xml.DeploymentManifest.Identity.Id -IsInstalled $true
            }else{
               if(!$ras){Write-Host ($xml.DeploymentManifest.Identity.Name) "Installed: False" -ForegroundColor Red}
               Update-AppStatus $xml.DeploymentManifest.Identity.Id -IsInstalled $false
            }
            if(!$ras){Write-Host ""}
        }
    }
}
Write-Output $("LastRun:" + (get-date).toString() + "|Corrected:" + $script:corrections_made)
