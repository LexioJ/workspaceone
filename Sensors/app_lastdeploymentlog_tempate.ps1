# Author: Alexander Askin
# Collect Last Deployment Log for a specific Application
# Return Type: String -> needed to add a trimmer as String is limited to 1024 characters
# Execution Context: System
# Name: app_lastdeploymentlog_7zip
# Application: 7-Zip v16.4.0 -> specify the AppId from Workspace ONE UEM Console, "Apps & Books > Native > YOUR_WIN32_APPLICATION > Application ID" 
$AppId = "{23170F69-40C1-2702-1604-000001000000}"

$AppRegHive = "HKLM:\SOFTWARE\AirWatchMDM\AppDeploymentAgent\S-1-5-18\"

function Check-Registry ($Key, $SubKey, $ValueName, $ValueType, $Win64="true")  {
    if($Win64){
        $FullPath = Join-Path -Path $($Key) -ChildPath $SubKey
    }else{
        $FullPath = Join-Path -Path $($Key) -ChildPath $SubKey.Replace("\SOFTWARE\","\SOFTWARE\WOW6432Node\")
    }
    if (Test-Path -Path $FullPath){
        if((Get-ItemProperty -Path $FullPath).$ValueName){
            $result = (Get-ItemProperty -Path $FullPath).$ValueName
        }else{
            $result = "$ValueName for Application not found"
        }
    }else{
        $result = "Application not found: $($Key)$($AppId.ToUpper())"
    }
    return $result
}
$returnstring = (Check-Registry $AppRegHive $AppId "LastDeploymentLog" "REG_SZ" $true)
if($returnstring.Length -gt 1024){
    # Remove additional 17 (1024 - 17 = 1007) chars to include the "- TRIM TO 1024 -" info
    Write-Output "- TRIM TO 1024 -`n$($returnstring.Substring($returnstring.Length-1007,1007))"
}else{
    Write-Output $returnstring
}
