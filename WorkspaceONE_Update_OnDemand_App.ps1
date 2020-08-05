<#
.SYNOPSIS
  Workspace ONE Update OnDemand App, let you select current installed devices for a specific version of an application and push a newer version to a selection of these devices.
.DESCRIPTION
  This script tries to cover the missing capability of Workspace ONE UEM to push updates to devices which have manually installed an older version but need to be updated.
  Especially for security relevant updates (eg. Adobe Reader, Firefox, etc.) this was an important but missing function in one of my recent projects. 
  1. Update the [Declarations] Section to match your environment
  2. If you run this script you will be prompted 4 times
    2.1 Select the current installed version to identify targeted devices
    2.2 Select the target version of the application, it will be filtered to the same BundleId
    2.3 Select one or more devices (eg. for testing before send the command to all devices)
    2.4 Final confirmation if you really want to initate the PUSH INSTALL to your selected devices
.PARAMETER <Parameter_Name>
    No parameters yet
.INPUTS
  None
.OUTPUTS
  Console output only, maybe create a log file in an upcoming version
.NOTES
  Version:        1.0
  Author:         Alexander Askin
  Creation Date:  06. August 2020
  Purpose/Change: Initial Development
  
.EXAMPLE
  WorkspaceONE_Update_OnDemand_App.ps1
#>


Write-Host "  _      __         __                            ____  _  ______  __  ________  ___       "
Write-Host " | | /| / /__  ____/ /__ ___ ___  ___ ________   / __ \/ |/ / __/ / / / / __/  |/  /       "
Write-Host " | |/ |/ / _ \/ __/  '_/(_-</ _ \/ _ '/ __/ -_) / /_/ /    / _/  / /_/ / _// /|_/ /        "
Write-Host " |__/|__/\___/_/ /_/\_\/___/ .__/\_,_/\__/\__/  \____/_/|_/___/  \____/___/_/  /_/         "
Write-Host "   __  __        __     __ /_/    ____       ___                         __  ___           "
Write-Host "  / / / /__  ___/ /__ _/ /____   / __ \___  / _ \___ __ _  ___ ____  ___/ / / _ | ___  ___ "
Write-Host " / /_/ / _ \/ _  / _ '/ __/ -_) / /_/ / _ \/ // / -_)  ' \/ _ '/ _ \/ _  / / __ |/ _ \/ _ \"
Write-Host " \____/ .__/\_,_/\_,_/\__/\__/  \____/_//_/____/\__/_/_/_/\_,_/_//_/\_,_/ /_/ |_/ .__/ .__/"
Write-Host "     /_/  by Alexander Askin                                                   /_/  /_/    "

#----------------------------------------------------------[Declarations]----------------------------------------------------------
# Workspace ONE UEM variables
$WorkspaceONEServer  = "" # https://cnxxx.awmdm.com
$WorkspaceONEAdmin   = "" # APIAdmin
$WorkspaceONEAdminPW = "" # SuperSecretPW01*
$WorkspaceONEAPIKey  = "" # your API Key
$WorkspaceONEOrganizationGroupName = "" # GroupIdName as used for device assignment
 
$URL = $WorkspaceONEServer + "/api"
# Base64 Encode Workspace ONE UEM Username and Password for API Access
$combined = $WorkspaceONEAdmin + ":" + $WorkspaceONEAdminPW
$encoding = [System.Text.Encoding]::ASCII.GetBytes($combined)
$cred = [Convert]::ToBase64String($encoding)
# Optional overwrite credential above by specify username:password and convert to base64 by using https://www.base64encode.org/
# $cred = "" #uncomment this line if you like to use base64 encoded string

 
# Contruct REST HEADER
$header = @{
"Authorization"  = "Basic $cred";
"aw-tenant-code" = $WorkspaceONEAPIKey;
"Accept" = "application/json";
"Content-Type"   = "application/json;version=2";}

#-----------------------------------------------------------[Functions]------------------------------------------------------------

# Returns Workspace ONE UEM Console Version
Function Check-ConsoleVersion {
    $endpointURL = $URL + "/system/info"
    $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $header
    $ProductVersion = $webReturn.ProductVersion
    $Version = $ProductVersion -replace '[\.]'
    $Version = [int]$Version
    Write-Host("Console Version: ") -ForegroundColor Cyan -NoNewline
    Write-Host $ProductVersion
    return $ProductVersion
}

# Returns Group ID
Function Get-OrgGroupIdbyName ($WorkspaceONEOrgGroupName) {
    Write-Host("Getting Group ID with Name: " + $WorkspaceONEOrgGroupName) -NoNewline -ForegroundColor Cyan
    $endpointURL = $URL + "/system/groups/search/?groupid=" + $WorkspaceONEOrgGroupName
    $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $header
    Write-Host(" - found: " + $webReturn.LocationGroups.Id.Value)
    return $webReturn
}
 
# Returns all devices limit by 5000; increase if needed
Function Get-Devices {
    Write-Host("Getting all Devices") -NoNewline -ForegroundColor Cyan
    $endpointURL = $URL + "/mdm/devices/search?pagesize=5000"
    $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $header
    Write-Host(" - found: " + $webReturn.Total)
    return $webReturn
}

# Returns all applications filtered by Windows Apps which are Active; look at https://<yourWS1URL>/API/help/#!/Apps/Apps_Search for more details on filters
Function Get-Applications {
    Write-Host("Getting all Applications") -NoNewline -ForegroundColor Cyan
    $endpointURL = $URL + "/mam/apps/search?status=Active&platform=WinRT"
    $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $header
    Write-Host(" - found: " + $webReturn.Total)
    return $webReturn
}

# Return all devices which have a specific application version installed
Function Get-DeviceIDsByInstalledApplicationID($WorkSpaceONEApplicationID, $WorkSpaceONEApplicationName) {
    Write-Host("Getting all Devices having " + $WorkSpaceONEApplicationName + " installed") -NoNewline -ForegroundColor Cyan
    $endpointURL = $URL + "/mam/apps/internal/" + $WorkSpaceONEApplicationID + "/devices?status=installed&pagesize=5000"
    $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $header
    Write-Host(" - found: " + $webReturn.Total)
    return $webReturn
}

# Invoke uninstallation of an application on a spefic device; not used in this script - kept it as reference
Function Remove-ApplicationByDeviceID ($WorkSpaceONEApplicationID, $WorkSpaceONEDeviceID){
    $endpointURL = $URL + "apps/internal/" + $WorkSpaceONEApplicationID + "/uninstall"
    $body = @()
    $body = [pscustomobject]@{
        'DeviceID: ' = $WorkSpaceONEDeviceID;
    }
    $json = $body | ConvertTo-Json
    $webReturn = Invoke-RestMethod -Method Post -Uri $endpointURL -Headers $header -Body $json
    return $webReturn
}

# Invoke installation of an application on a spefic device
Function Install-ApplicationByDeviceID ($WorkSpaceONEApplicationID, $WorkSpaceONEDeviceID){
    $endpointURL = $URL + "apps/internal/" + $WorkSpaceONEApplicationID + "/install"
    $body = @()
    $body = [pscustomobject]@{
        'DeviceId: ' = $WorkSpaceONEDeviceID;
    }
    $json = $body | ConvertTo-Json
    $webReturn = Invoke-RestMethod -Method Post -Uri $endpointURL -Headers $header -Body $json
    return $webReturn
}
 

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Write-Host ""

if(Check-ConsoleVersion){
    # Get all available Win32 Apps which are Active
    $AllApplications = (Get-Applications).Application
    # Select Source and Target Version
    $SelectedSourceApplication = $AllApplications | Select-Object -Property ApplicationName,AppVersion,AssignmentStatus,AssignedDeviceCount,InstalledDeviceCount,NotInstalledDeviceCount,SmartGroups,BundleId,Id  | Out-GridView -Title "Select the Current Application which needs to be updated; InstalledDeviceCount is not always accurade" -OutputMode Single
    $SelectedTargetApplication = $AllApplications | Select-Object -Property ApplicationName,AppVersion,AssignmentStatus,AssignedDeviceCount,InstalledDeviceCount,NotInstalledDeviceCount,SmartGroups,BundleId,Id | Where-Object BundleId -eq $SelectedSourceApplication.BundleId |Sort-Object -Property AppVersion -Descending  | Out-GridView -Title "Select the Target Application you like to update to" -OutputMode Single
    # Get all devices having the old version installed
    $DeviceIDsApplicationCurrentlyInstalled = (Get-DeviceIDsByInstalledApplicationID $SelectedSourceApplication.Id.Value $SelectedSourceApplication.ApplicationName).DeviceId
    # Get all devices to have DeviceFriendlyName,SerialNumber,Model,LastSeen available
    $AllDevices = (Get-Devices).Devices
    # Filter the current list
    $DeviceList = @()
    Write-Host $DeviceIDsApplicationCurrentlyInstalled
    foreach ($Device in $AllDevices){
        if($DeviceIDsApplicationCurrentlyInstalled.Contains($Device.Id.Value)){
            Write-Host $Device.Id.Value
             $DeviceList += $Device
        }
    }
    # Select one or more devices
    $SelectedDevices = $DeviceList | Select-Object -Property DeviceFriendlyName,SerialNumber,Model,LastSeen,Id | Out-GridView -Title "Select one or more devices you like to push install $($SelectedTargetApplication.ApplicationName) $($SelectedTargetApplication.AppVersion), use CRT+A to select them all" -PassThru | Select-Object -ExpandProperty Id

    # Ask for confirmation
    Write-Host  -ForegroundColor Yellow -NoNewline
    $wscriptShell = New-Object -ComObject Wscript.Shell 
    $Confirmation = $wscriptShell.PopUp("Are you sure you want to update $($SelectedDevices.Count) device(s)`nfrom $($SelectedSourceApplication.ApplicationName) $($SelectedSourceApplication.AppVersion) to $($SelectedTargetApplication.ApplicationName) $($SelectedTargetApplication.AppVersion)", 0,"Final Confirmation",4 + 32)

    # And Action
    if($Confirmation -eq "6"){
        foreach ($Device in $SelectedDevices){
          Write-Host "Initiate Install-ApplicationByDeviceID $($SelectedTargetApplication.Id.Value) $($Device.Value)" -ForegroundColor Yellow
          Install-ApplicationByDeviceID $SelectedTargetApplication.Id.Value $Device.Value
        }
    } else{
        Write-Host "Aborted."
    }
}
