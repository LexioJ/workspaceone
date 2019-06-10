<#
.SYNOPSIS
  Workspace ONE Auto Tagging runs centrally, reads device informations via WS1 API and automatically create missing/required tags.
.DESCRIPTION
  This script tries to cover the missing capability of Workspace ONE UEM to create Smart/Assignment Groups based on Hardware Vendor or Chassis Type. 
  These Smart Groups are then used to deploy Vendor-specific tools (like Dell Command Suite) or Device type-specific Software (eg. VPN Software to all Laptops).
  I created and already used this script for different projects to solve this limitation. Please run it first with $allow_tagging = $false to check if everything 
  is working fine, then you can set $allow_tagging = $true to actually start Auto-Tagging. Create a Scheduled Task to run the script, for example, every 5 minutes 
  if you want to have permanent Auto-Tagging.
.PARAMETER <Parameter_Name>
    No parameters yet
.INPUTS
  None
.OUTPUTS
  Console output only, maybe create a log file in an upcoming version
.NOTES
  Version:        1.0
  Author:         Alexander Askin
  Creation Date:  10. June 2019
  Purpose/Change: Initial script development
  
.EXAMPLE
  WorkspaceONE_Auto_Tagging_v1.ps1
#>

Write-Host "  _      __         __                            ____  _  ______"
Write-Host " | | /| / /__  ____/ /__ ___ ___  ___ ________   / __ \/ |/ / __/"
Write-Host " | |/ |/ / _ \/ __/  '_/(_-</ _ \/ _  / __/ -_) / /_/ /    / _/  "
Write-Host " |__/|__/\___/_/ /_/\_\/___/ .__/\_,_/\__/\__/  \____/_/|_/___/  "
Write-Host "   ___       __          _/_/__               _                  "
Write-Host "  / _ |__ __/ /____  ___/_  __/__  ____ _____(_)__  ___ _        "
Write-Host " / __ / // / __/ _ \/___// / / _  / _  / _  / / _ \/ _  /        "
Write-Host "/_/ |_\_,_/\__/\___/    /_/  \_,_/\_, /\_, /_/_//_/\_, /         "
Write-Host "by Alexander Askin               /___//___/       /___/          "
Write-Host ""

#----------------------------------------------------------[Declarations]----------------------------------------------------------
# Read/Write Switch - set to $true if you want this scripte to add tags to your devices, 
# if set to $false the script will only show what it would do, but would not make any changes.
$allow_tagging = $false

# Workspace ONE Access variables
$WorkspaceONEServer = "" # https://cnxxx.awmdm.com
$WorkspaceONEAdmin = "" # APIAdmin
$WorkspaceONEAdminPW = "" # SuperSecretPW01*
$WorkspaceONEAPIKey = "" # your API Key
$WorkspaceONEOrganizationGroupName = "" # GroupIdName as used for device assignment
 
$URL = $WorkspaceONEServer + "/api"
# Base64 Encode Workspace ONE UEM Username and Password for API Access
$combined = $WorkspaceONEAdmin + ":" + $WorkspaceONEAdminPW
$encoding = [System.Text.Encoding]::ASCII.GetBytes($combined)
$cred = [Convert]::ToBase64String($encoding)
# Optional overwrite credential above by specify username:password and convert to base64 by using https://www.base64encode.org/
# $cred = "" #uncomment this line if you like to use base64 encoded string

# Define Vendors and their relations to HW-Types
$vendors = @{}
$vendors.Add("Latitude*", "Dell")
$vendors.Add("Optiplex*", "Dell")
$vendors.Add("Precision*", "Dell")
$vendors.Add("Proliant*", "HP")
$vendors.Add("HP EliteBook*", "HP")
$vendors.Add("HP ZBook*", "HP")
$vendors.Add("HP Elite*", "HP")
$vendors.Add("VMware*", "Virtual")

# Define Chassis and their relations to HW-Types
$devicetypes = @{}
$devicetypes.Add("Optiplex*", "Desktop")
$devicetypes.Add("Precision T*", "Desktop")
$devicetypes.Add("VMware*", "Desktop")
$devicetypes.Add("Proliant*", "Laptop")
$devicetypes.Add("Precision M*", "Laptop")
$devicetypes.Add("HP EliteBook*", "Laptop")
$devicetypes.Add("HP Elite X*", "2-in-1")
 
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
}

Function Get-OrgGroupIdbyName ($WorkspaceONEOrgGroupName) {
    Write-Host("Getting Group ID with Name: " + $WorkspaceONEOrgGroupName) -NoNewline -ForegroundColor Cyan
    $endpointURL = $URL + "/system/groups/search/?groupid=" + $WorkspaceONEOrgGroupName
    $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $header
    Write-Host(" - found: " + $webReturn.LocationGroups.Id.Value)
    return $webReturn
}
 
Function Get-Devices {
    Write-Host("Getting all Devices") -NoNewline -ForegroundColor Cyan
    $endpointURL = $URL + "/mdm/devices/search"
    $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $header
    Write-Host(" - found: " + $webReturn.Total)
    return $webReturn
}
 
Function Get-DeviceByID($WorkSpaceONEDeviceID) {
    Write-Host("Getting specific Device with ID: " + $WorkSpaceONEDeviceID)
    $endpointURL = $URL + "/mdm/devices/" + $WorkSpaceONEDeviceID
    $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $header
    return $webReturn
}
 
Function Get-TagIDByName($WorkSpaceONETagName) {
    Write-Host("Getting specific TagID by Name """ + $WorkSpaceONETagName + """") -NoNewline -ForegroundColor Cyan
    $endpointURL = $URL + "/mdm/tags/search/?name=" + $WorkSpaceONETagName + "&organizationgroupid=" + $WorkSpaceONEGroupID
    $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $header
    if($webReturn.Tags.Count -ge 1){
        Write-Host(" - found: " + $webReturn.Tags.Item(0).Id.Value)
        return $webReturn.Tags.Item(0)
    }else{
        Write-Host(" - not found -> please create this TAG manually in Workspace ONE Console") -ForegroundColor Yellow
    }
}
 
Function Check-TagAlreadyOnDevice($WorkSpaceONETagID, $WorkSpaceONEDeviceID) {
    $endpointURL = $URL + "/mdm/tags/" + $WorkSpaceONETagID + "/devices"
    $webReturn = Invoke-RestMethod -Method Get -Uri $endpointURL -Headers $header
    $webReturn.Device.ForEach({
        $taggeddevice = $_;
        if($taggeddevice.DeviceId -eq $WorkSpaceONEDeviceID) {
            return $true
        }
    })
    return $false
}
 
Function Add-TagToDevice($WorkSpaceONETagID, $WorkSpaceONEDeviceID) {
    if($allow_tagging -eq $true){
        $endpointURL = $URL + "/mdm/tags/" + $WorkSpaceONETagID + "/adddevices"
        $DeviceToAdd = @()
        $DeviceToAdd += $WorkSpaceONEDeviceID.ToString()
        $Values = @()
        $Values = [pscustomobject]@{
            'Value' = $DeviceToAdd;
        }
        $body = [pscustomobject]@{
            'BulkValues' = $Values;
        }
        $json = $body | ConvertTo-Json
        $webReturn = Invoke-RestMethod -Method Post -Uri $endpointURL -Headers $header -Body $json
        Write-Host("Returns: " + $webReturn)
    }else{
        Write-Host("-NO CHANGE-") -ForegroundColor Yellow -NoNewline
    }
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

if($allow_tagging -eq $false){
    Write-Host ("No Changes will be written as allow_tagging is set to $false") -ForegroundColor Yellow
}
Check-ConsoleVersion
$global:WorkSpaceONEGroupID = (Get-OrgGroupIdbyName($WorkspaceONEOrganizationGroupName)).LocationGroups.Id.Value

$WorkSpaceONEDeviceID = ""
$WorkSpaceONETagID = @{}
foreach($tag in $vendors.Values){
    if($WorkSpaceONETagID.ContainsKey($tag) -eq $false){
        $WorkSpaceONETagID.Add($tag, (Get-TagIDByName($tag)).Id.Value)
    }
}
foreach($tag in $devicetypes.Values){
    if($WorkSpaceONETagID.ContainsKey($tag) -eq $false){
        $WorkSpaceONETagID.Add($tag, (Get-TagIDByName($tag)).Id.Value)
    }
}

Write-Host "-------------- Start processing ... ------------------"
(Get-Devices).Devices.ForEach({
    $device = $_;
    $device_was_found = $false
    Write-Host($device.DeviceFriendlyName + "(ID:" + $device.Id.Value + ") is " + $device.Model) -NoNewline -ForegroundColor Yellow
    # Vendor Check
    if($vendors){
        foreach($vendor in $vendors.Keys){
            if ($device.Model -like $vendor){
                $device_was_found = $true
                $WorkSpaceONEDeviceID = $device.Id.Value
                If(Check-TagAlreadyOnDevice $WorkSpaceONETagID[$vendors[$vendor]] $WorkSpaceONEDeviceID){
                    Write-Host(" already tagged as " + $vendors[$vendor] + " - SKIPPED, ") -ForegroundColor Green -NoNewline
                }else{
                    Write-Host(" untagged """ + $vendors[$vendor] + """ - attempt to TAG it, ") -ForegroundColor Cyan -NoNewline
                    Add-TagToDevice $WorkSpaceONETagID[$vendors[$vendor]] $WorkSpaceONEDeviceID
                }
            }
        }
        if($device_was_found -eq $false){
            Write-Host (" no Vendor entry found - SKIPPED, ") -ForegroundColor Gray -NoNewline
        }
    }

    $device_was_found = $false
    # Chassis / DeviceType Check
    if($devicetypes){
        foreach($devicetype in $devicetypes.Keys){
            if ($device.Model -like $devicetype){
                $device_was_found = $true
                $WorkSpaceONEDeviceID = $device.Id.Value
                If(Check-TagAlreadyOnDevice $WorkSpaceONETagID[$devicetypes[$devicetype]] $WorkSpaceONEDeviceID){
                    Write-Host(" already tagged as " + $devicetypes[$devicetype] + " - SKIPPED") -ForegroundColor Green
                }else{
                    Write-Host(" untagged """ + $devicetypes[$devicetype] + """ - attempt to TAG it") -ForegroundColor Cyan
                    Add-TagToDevice $WorkSpaceONETagID[$devicetypes[$devicetype]] $WorkSpaceONEDeviceID
                }
            }
        }
        if($device_was_found -eq $false){
            Write-Host (" no DeviceType entry found - SKIPPED") -ForegroundColor Gray
        }
    }
})
