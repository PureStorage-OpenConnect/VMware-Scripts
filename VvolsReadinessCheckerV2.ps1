<#
===========================================================================================================================================================
    Disclaimer

    The sample script and documentation are provided AS IS and are not supported by
    the author or the author's employer, unless otherwise agreed in writing. You bear
    all risk relating to the use or performance of the sample script and documentation.
    The author and the author's employer disclaim all express or implied warranties
    (including, without limitation, any warranties of merchantability, title, infringement
    or fitness for a particular purpose). In no event shall the author, the author's employer
    or anyone else involved in the creation, production, or delivery of the scripts be liable
    for any damages whatsoever arising out of the use or performance of the sample script and
    documentation (including, without limitation, damages for loss of business profits,
    business interruption, loss of business information, or other pecuniary loss), even if
    such person has been advised of the possibility of such damages.

Original Script: https://github.com/bdwill/vvolsreadinesschecker/blob/master/VVolsReadinessChecker.ps1
Original Author: Brandon Willmott (@bdwill)
 Updated Script: https://github.com/PureStorage-OpenConnect/VMware-Scripts/blob/master/vVolsReadinessCheckerV2.ps1
 Updated Script: David Stevens (@PSUStevens)
 Updated Date  : 1 October 2024
===========================================================================================================================================================

This script will:
--Check for VVols Readiness
--Check for Purity 6.5+
--Check for vCenter 7.0U3+ and ESXi 7.0U3+ (7.0 Update 3 is highly recommended)
--Check that FlashArray is accessible on TCP port 8084
--Check that a NTP server is set, valid, and daemon running on ESXi hosts and FlashArray

All information logged to a file.

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-FlashArray //X, //C, //XL
-vCenter 7.0U3 and later
-PowerCLI VMware PowerCLI 13.3 or later required
-Pure Storage PowerShell SDK2 v2.26 or later is required
-Pure Storage PowerShell Toolkit v3.0 or later is required

#>

# Borrowing Get-VAMIServiceAPI and Get-VAMITime from VMware's PowerCLI-Example-Scripts
# https://github.com/vmware/PowerCLI-Example-Scripts/blob/master/Modules/VAMI/VAMI.psm1

Function Get-VAMIServiceAPI {
    <#
        .NOTES
        ===========================================================================
         Inspired by:    William Lam
         Organization:  VMware
         Blog:          www.virtuallyghetto.com
         Twitter:       @lamw
         Created by:    Michael Dunsdon
         Twitter:      @MJDunsdon
         Date:         September 21, 2020
        ===========================================================================
        .SYNOPSIS
            This function returns the Service Api Based on a String of Service Name.
        .DESCRIPTION
            Function to find and get service api based on service name string
        .EXAMPLE
            Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
            Get-VAMIUser -NameFilter "accounts"
        .NOTES
            Script supports 6.5 and 6.7 VCSAs.
            Function Gets all Service Api Names and filters the list based on NameFilter
            If Multiple Serivces are returned it takes the Top one.
    #>
        param(
            [Parameter(Mandatory=$true)]
            [String]$NameFilter
        )
    
        $ServiceAPI = Get-CisService | Where-Object {$_.name -like "*$($NameFilter)*"}
        if (($ServiceAPI.count -gt 1) -and $NameFilter) {
            $ServiceAPI = ($ServiceAPI | Sort-Object -Property Name)[0]
        }
        return $ServiceAPI
    }
Function Get-VAMITime {
    <#
        .NOTES
        ===========================================================================
         Created by:    William Lam
         Organization:  VMware
         Blog:          www.virtuallyghetto.com
         Twitter:       @lamw
         Modifed by:    Michael Dunsdon
         Twitter:      @MJDunsdon
         Date:         September 16, 2020
        ===========================================================================
        .SYNOPSIS
            This function retrieves the time and NTP info from VAMI interface (5480)
            for a VCSA node which can be an Embedded VCSA, External PSC or External VCSA.
        .DESCRIPTION
            Function to return current Time and NTP information
        .EXAMPLE
            Connect-CisServer -Server 192.168.1.51 -User administrator@vsphere.local -Password VMware1!
            Get-VAMITime
        .NOTES
            Modified script to account for Newer VCSA. Script supports 7.0+ VCSAs
    #>
        $systemTimeAPI = ( Get-VAMIServiceAPI -NameFilter "system.time")
        $timeResults = $systemTimeAPI.get()
    
        $timeSyncMode = ( Get-VAMIServiceAPI -NameFilter "timesync").get()
        if ($timeSyncMode.mode) {
            $timeSyncMode = $timeSync.mode
        }
    
        $timeResult  = [pscustomobject] @{
            Timezone = $timeResults.timezone;
            Date = $timeResults.date;
            CurrentTime = $timeResults.time;
            Mode = $timeSyncMode;
            NTPServers = "N/A";
            NTPStatus = "N/A";
        }
    
        if($timeSyncMode -eq "NTP") {
            $ntpServers = ( Get-VAMIServiceAPI -NameFilter "ntp").get()
            if ($ntpServers.servers) {
                $timeResult.NTPServers = $ntpServers.servers
                $timeResult.NTPStatus = $ntpServers.status
            } else {
                $timeResult.NTPServers = $ntpServers
                $timeResult.NTPStatus = ( Get-VAMIServiceAPI -NameFilter "ntp").test(( Get-VAMIServiceAPI -NameFilter "ntp").get()).status
            }
        }
        $timeResult
    }


#Create log if non-existent
$Currentpath = split-path -parent $MyInvocation.MyCommand.Definition 
$Logfile = $Currentpath + '\PureStorage-vSphere-CheckvVolReadiness-' + (Get-Date -Format o |Foreach-Object {$_ -Replace ':', '.'}) + ".log"

add-content $logfile '             __________________________'
add-content $logfile '            /++++++++++++++++++++++++++\'
add-content $logfile '           /++++++++++++++++++++++++++++\'
add-content $logfile '          /++++++++++++++++++++++++++++++\'
add-content $logfile '         /++++++++++++++++++++++++++++++++\'
add-content $logfile '        /++++++++++++++++++++++++++++++++++\'
add-content $logfile '       /++++++++++++/----------\++++++++++++\'
add-content $logfile '      /++++++++++++/            \++++++++++++\'
add-content $logfile '     /++++++++++++/              \++++++++++++\'
add-content $logfile '    /++++++++++++/                \++++++++++++\'
add-content $logfile '   /++++++++++++/                  \++++++++++++\'
add-content $logfile '   \++++++++++++\                  /++++++++++++/'
add-content $logfile '    \++++++++++++\                /++++++++++++/'
add-content $logfile '     \++++++++++++\              /++++++++++++/'
add-content $logfile '      \++++++++++++\            /++++++++++++/'
add-content $logfile '       \++++++++++++\          /++++++++++++/'
add-content $logfile '        \++++++++++++\'
add-content $logfile '         \++++++++++++\'
add-content $logfile '          \++++++++++++\'
add-content $logfile '           \++++++++++++\'
add-content $logfile '            \------------\'
Add-Content $Logfile ' '
add-content $logfile '          Pure Storage FlashArray and VMware VVols Readiness Checker v3.0 (OCTOBER-2024)'
add-content $logfile '----------------------------------------------------------------------------------------------------'
Add-Content $Logfile ' '


# Get the Pure Storage SDK2 version
$PurePSSDKVersion = Get-Module -Name PureStoragePowerShellSDK2 -ListAvailable | Select-Object -Property Version

# If the Pure Storage SDK Version is not v2.26 or higher, recommend that the user install it or a higher version
If ($PurePSSDKVersion.Version.Major -ge "2") {
    if ($PurePSSDKVersion.Version.Minor -ge "26") {
        Write-Host "Pure Storage SDK version 2.26 or higher present, " -NoNewLine
        Write-Host "proceeding" -ForegroundColor Green 
    }
    
} else {
    Write-Host "The Pure Storage SDK version could not be determined or is less than version 2.26" -Foregroundcolor Red
    Write-Host "Please install the Pure Storage SDK version 2.26 or higher and rerun this script" -Foregroundcolor Yellow
    Write-Host " "
    exit
}

# Get the Pure Storage PowerShell Toolkit version
$PurePSToolkitVersion = Get-Module -Name PureStoragePowerShellToolkit -ListAvailable | Select-Object -Property Version

# If the Pure Storage SDK Version is not v3.0 or higher, recommend that the user install it or a higher version
If ($PurePSToolkitVersion.Version.Major -ge "3") {
    Write-Host "Pure Storage PowerShell Toolkit version 3.0 or higher present, " -NoNewLine
    Write-Host "proceeding" -ForegroundColor Green 
    
} else {
    Write-Host "The Pure Storage PowerShell Toolkit version could not be determined or is less than version 3.0" -Foregroundcolor Red
    Write-Host "Please install the Pure Storage Toolkit version 3.0 or higher and rerun this script" -Foregroundcolor Yellow
    Write-Host " "
    exit
}

# Get the PowerCLI Version
$PowerCLIVersion = Get-Module -Name VMware.PowerCLI -ListAvailable | Select-Object -Property Version

# If the PowerCLI Version is not v13 or higher, recommend that the user install PowerCLI 13 or higher
If ($PowerCLIVersion.Version.Major -ge "13") {
    if ($PowerCLIVersion.Version.Minor -ge "3") {
        Write-Host "PowerCLI version 13.3 or higher present, " -NoNewLine
        Write-Host "proceeding" -ForegroundColor Green 
    }
    
} else {
    Write-Host "PowerCLI version could not be determined or is less than version 13.3" -Foregroundcolor Red
    Write-Host "Please install PowerCLI 13.3 or higher and rerun this script" -Foregroundcolor Yellow
    Write-Host " "
    exit
}


# Set the PowerCLI configuration to ignore incd /self-signed certificates
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$False | Out-Null 

# Check to see if a current vCenter Server session is in place
If ($Global:DefaultVIServer) {
    Write-Host "Connected to " -NoNewline 
    Write-Host $Global:DefaultVIServer -ForegroundColor Green
    If ($Global:DefaultVIServer.Name -eq $Global:DefaultCisServers.Name) {
        Write-Host "Connected to " -NoNewline
        Write-Host $Global:DefaultCisServers.Name -ForegroundColor Green -NoNewline
        Write-Host " vSphere Automation SDK"
        $ConnectCiS = $False
    } else {
        $VICredentials = Get-Credential -Message "Enter vCenter server credentials"
        Connect-CisServer -Server $Global:DefaultVIServer -Credential $VICredentials
        $ConnectCiS = $true
    }
} else {
    Write-Host "Not connected to vCenter Server" -ForegroundColor Red
    $VIFQDN = Read-Host "Please enter the vCenter Server FQDN"  
    $VICredentials = Get-Credential -Message "Enter credentials for vCenter Server" 
    try {
        Connect-VIServer -Server $VIFQDN -Credential $VICredentials -ErrorAction Stop | Out-Null
        Write-Host "Connected to $VIFQDN" -ForegroundColor Green 
        $ConnectVc = $True
        If ($Global:DefaultVIServer.Name -eq $Global:DefaultCisServers.Name) {
            Write-Host "Connected to:  " -NoNewline
            Write-Host $Global:DefaultCisServers.Name -ForegroundColor Green -NoNewline
            Write-Host " vSphere Automation SDK"
        } else {
            Connect-CisServer -Server $Global:DefaultVIServer -Credential $VICredentials
            $ConnectCiS = $true
        }
    }
    catch {
        Write-Host "Failed to connect to $VIFQDN" -BackgroundColor Red
        Write-Host $Error
        Write-Host "Terminating the script " -BackgroundColor Red
        $ConnectVc = $False
        return
    }
}

# Denote where the log is being written to
Write-Host ""
Write-Host "Script result log can be found at $Logfile" -ForegroundColor Green
Write-Host ""
Add-Content $Logfile "Connected to vCenter: $($Global:DefaultVIServer)"

# Choose to run the script against all hosts connected to a vCenter Server, or a single cluster
Do{ $vSphereClusterChoice = Read-Host "Would you prefer to limit this to hosts in a specific cluster? (y/n)" }
Until($vSphereClusterChoice -eq "Y" -or $vSphereClusterChoice -eq "N")

# Choose a single cluster
if ($vSphereClusterChoice -match "[yY]") {
    # Retrieve the vSphere clusters & sort them alphabetically 
    $vSphereClusters = Get-Cluster | Sort-Object Name

    # If no vSphere Clusters are found, exit the script
    if ($vSphereClusters.count -lt 1)
    {
        Add-Content $Logfile "Terminating Script. No VMware cluster(s) found."  
        Write-Host "No VMware cluster(s) found. Terminating Script" -BackgroundColor Red
        exit
    }

    # Select the Cluster
    Write-Host "1 or more VMware Clusters were found. Please choose a cluster:"
    Write-Host ""

    # Enumerate the cluster(s)
    1..$vSphereClusters.Length | Foreach-Object { Write-Host $($_)":"$vSphereClusters[$_-1]}

    # Wait until a valid cluster is picked
    Do
    {
        Write-Host # empty line
        $Global:ans = (Read-Host 'Please select a cluster') -as [int]
    
    } While ((-not $ans) -or (0 -gt $ans) -or ($vSphereClusters.Length+1 -lt $ans))

    # Assign the $vSphereCluster variable to the Cluster picked
    $vSphereCluster = $vSphereClusters[($ans-1)]

    # Log/Enumerate which cluser was selected
    Add-Content $Logfile "Selected cluster is: $($vSphereCluster)"
    Add-Content $Logfile ""
    Write-Host "Selected cluster is " -NoNewline 
    Write-Host $vSphereCluster -ForegroundColor Green
    Write-Host ""

    # Assign all of the ESX hosts in $vSphereCluster to the $ESXHosts variable, and sort the list alphabetically
    $ESXHosts = $vSphereCluster | Get-VMHost | Sort-Object Name

}  else {

    # Because individual vSphereClusters were not selected
    # Assign all of the ESX hosts vCenter manages into the $ESXHosts variable & sort them alphabetically
    $ESXHosts = Get-VMHost | Sort-Object Name 
}

If ($DefaultFlashArray.ArrayName) {
    Write-Host "Defaulting to FlashArray: $($DefaultFlashArray.ArrayName) "
    Add-Content $Logfile "Defaulting to FlashArray: $($DefaultFlashArray.ArrayName)"
    $ConnectFA = $True
} else {
    #connect to FlashArray
    $FaEndPoint = Read-Host "Please enter a FlashArray IP or FQDN"
    try
    {
        $FaCredentials = Get-Credential -Message "Please enter the FlashArray Credentials for $($FaEndPoint)"
        $DefaultFlashArray = Connect-Pfa2Array -EndPoint $FaEndPoint -Credential $FaCredentials -ErrorAction Stop -IgnoreCertificateError
        $ConnectFA = $True
    }
    catch
    {
        write-host "Failed to connect to FlashArray" -BackgroundColor Red
        write-host $Error
        write-host "Terminating Script" -BackgroundColor Red
        add-content $logfile "**********  Failed to connect to FlashArray  **********"
        add-content $logfile $Error
        add-content $logfile "**********  Terminating Script  **********"
        $ConnectFA = $False

        return
    }

}

#$errorHosts = @()
write-host "Executing..."

# Check vCenter version
add-content $logfile ""
add-content $logfile "***********************************************************************************************"
add-content $logfile ""
add-content $logfile "Working on the following vCenter: $($global:DefaultVIServers.Name), version $($Global:DefaultVIServers.Version)"
add-content $logfile ""
add-content $logfile "***********************************************************************************************"
add-content $logfile "             Checking vCenter Version"
add-content $logfile "-------------------------------------------------------"
if ($global:DefaultVIServers.version -le [Version]"6.5")
{
    add-content $logfile "[****NEEDS ATTENTION****] vCenter 6.5 or later is required for VMware VVols."
}
else
{
    add-content $logfile "Installed vCenter version, $($global:DefaultVIServers.version) supports VVols."
}


$vCenterTime = Get-VamiTime 


If ($vCenterTime.Mode -Like "NTP") {
    add-content $logfile "-----------------------------------------------------------------------------------------------"
    add-content $logfile "                     vCSA NTP "
    add-content $logfile "-------------------------------------------------------"
    If ($vCenterTime.NTPStatus -eq "SERVER_REACHABLE") {
        add-content $logfile "NTP server set to $($vCenterTime.NTPServers) and is REACHABLE from vCenter"
    } else {
        add-content $logfile "-------------------------------------------------------"
        add-content $logfile "[****NEEDS ATTENTION****] NTP settings aren't checkable from the vCenter Appliance."
        add-content $logfile "Check VMware KB for manual process: https://knowledge.broadcom.com/external/article?articleNumber=313945"        
    }

} else {
    add-content $logfile "*-------------------------------------------------------"
    add-content $logfile "[****NEEDS ATTENTION****] NTP settings aren't checkable from the vCenter Appliance."
    add-content $logfile "Check VMware KB for manual process: https://knowledge.broadcom.com/external/article?articleNumber=313945."        
}


# Iterating through each ESX host in the vCenter
add-content $logfile ""
add-content $logfile "Iterating through all ESXi hosts in the cluster $clusterName..."
$ESXHosts | out-string | add-content $logfile
foreach ($esx in $ESXHosts)
{
    add-content $logfile ""
    add-content $logfile "***********************************************************************************************"
    add-content $logfile ""
    add-content $logfile "   Working on the following ESXi host: $($esx.Name), version $($esx.Version)"
    add-content $logfile ""
    add-content $logfile "***********************************************************************************************"
    add-content $logfile "                Checking ESXi Version"
    add-content $logfile "-------------------------------------------------------"
    # Check for ESXi version
    if ($esx.version -le [Version]"7.0")
    {
        add-content $logfile "[****NEEDS ATTENTION****] ESXi 7.0U3 or later is required for this script to assess VMware VVols readiness."
    }
    else
    {
        add-content $logfile "Installed ESXi version, $($esx.version) supports VVols."
    }
    add-content $logfile ""
    add-content $logfile "-------------------------------------------------------"
    add-content $logfile "               Checking NTP settings"
    add-content $logfile "-------------------------------------------------------"

    # Check for NTP server configuration
    $ntpServer = Get-VMHostNtpServer -VMHost $esx
# Check for NTP server configuration
$ntpServer = Get-VMHostNtpServer -VMHost $esx
if ($ntpServer -eq $null)
{
   Add-Content $logfile "[****NEEDS ATTENTION****] NTP server for this ESXi host is empty. Configure an NTP server before proceeding with VVols."
}
else
{
    Add-Content $logfile "   NTP server set to $($ntpServer)"
    If ($PSEdition -eq "Core") {
        $testNetConnection = Test-Connection -TargetName $ntpserver 
    } else {
        $testNetConnection = Test-NetConnection -ComputerName $ntpServer -InformationLevel Quiet
    }


    if (!$testNetConnection)
    {
        Add-Content $logfile "[****NEEDS ATTENTION****] Could not communicate with the NTP server from this console. Check that it is valid and accessible."
    }
    else
    {
        Add-Content $logfile "   NTP server is valid and accessible."
    }
}


    # Check for NTP daemon running and enabled
    $ntpSettings = $esx | Get-VMHostService | Where-Object {$_.key -eq "ntpd"} | Select-Object vmhost, policy, running

    if ($ntpSettings."policy" -contains "off")
    {
        Add-Content $logfile "[****NEEDS ATTENTION****] NTP daemon is not enabled. Enable the service in the ESXi host configuration."
    }
    else
    {
     Add-Content $logfile "   NTP daemon is enabled."
    }

    if ($ntpSettings."running" -contains "true")
    {
        Add-Content $logfile "   NTP daemon is running."
    }
    else
    {
        Add-Content $logfile "[****NEEDS ATTENTION****] NTP daemon is not running."
    }
}

<#
# Capture all of the storage providers of the current vCenter

$storageProviders = Get-StorageProvider

# Output the details of each storage provider
foreach ($provider in $storageProviders) {
    [PSCustomObject]@{
        Name              = $provider.Name
        Description       = $provider.Description
        Type              = $provider.Type
        Uri               = $provider.Uri
        Status            = $provider.Status
        ProviderCategory  = $provider.ProviderCategory
    }

    Add-Content $logfile ""
    Add-Content $logfile 
}
#>

# Check FlashArray's NTP Settings
$FlashArray = get-pfa2array -array $DefaultFlashArray
add-content $logfile ""
add-content $logfile "***********************************************************************************************"
add-content $logfile ""
add-content $logfile "   Working on the following FlashArray: $($Flasharray.Name), Purity version $($Flasharray.Version)"
add-content $logfile ""
add-content $logfile "***********************************************************************************************"
add-content $logfile ""
add-content $logfile "-------------------------------------------------------"
add-content $logfile "                Checking NTP Setting"
add-content $logfile "-------------------------------------------------------"
$FlashArrayNTP = get-pfa2ArrayNtpTest -Array $DefaultFlashArray
if (!$flashArrayNTP.Enabled) 
{
    Add-Content $logfile "[****NEEDS ATTENTION****] FlashArray does not have an NTP server configured."
}
else
{
    # Iterate through both controllers to confirm they can reach the configured NTP servers
    Add-Content $logfile "FlashArray has the following NTP server(s) configured: $($FlashArray.NtpServers)"
    
    if (!$flashArrayNTP.Success)
    {
        Add-Content $logfile "[****NEEDS ATTENTION****] Could not communicate with an NTP server from this FlashArray. Check that it is valid and accessible."

    }
    else
    {
        Add-Content $logfile "NTP server(s) are valid and accessible."
    }
}
# Check Purity version
add-content $logfile ""
add-content $logfile "-------------------------------------------------------"
add-content $logfile "                Checking Purity Version"
add-content $logfile "-------------------------------------------------------"

if ($Flasharray.Version -ge [Version]"6.5")
{
    Add-Content $logfile "Purity version supports VVols."
}
else
{
    Add-Content $logfile "[****NEEDS ATTENTION****] Purity version not recommended for VVols. Contact Pure Storage support to upgrade to Purity version 5.3.6 or later."
}

# Check TCP port 8084 reachability
add-content $logfile ""
add-content $logfile "-------------------------------------------------------"
add-content $logfile "   Checking FlashArray Reachability on TCP port 8084"
add-content $logfile "-------------------------------------------------------"

$Interfaces = Get-Pfa2NetworkInterface -array $DefaultFlashArray | Where-Object {$_.services -Like "management"} | Where-Object {$_.name -Like "ct*"} | Where-Object {$_.enabled -eq "True"}
$i = 0
foreach ($interface in $interfaces)
{

    If ($PSEdition -eq "Core") {
        $testNetConnection = Test-Connection -TargetName $interfaces[$i].eth.address -TcpPort 8084 
    } else {
        $testNetConnection = Test-NetConnection -ComputerName $interfaces[$i].eth.address -Port 8084 -InformationLevel Quiet
    }

    if (!$testNetConnection)
    {
        add-content $logfile "[****NEEDS ATTENTION****] Could not reach FlashArray management port $($interface.name), IP: $($interfaces[$i].eth.address) on TCP port 8084."

    }
    else
    {
        add-content $logfile "FlashArray management port $($interface.name) is reachable on TCP port 8084."
    }
    $i += 1
}

# Check for existance of Pure Storage hosts and Pure Storage host groups
add-content $logfile ""
add-content $logfile "-------------------------------------------------------"
add-content $logfile "    Checking for Pure Storage Hosts and Host Groups"
add-content $logfile "-------------------------------------------------------"

$PureHostGroups = Get-Pfa2HostGroup -array $DefaultFlashArray
$PureHosts = 0

# Sum up the total number of Pure hosts in all of the Pure Host Groups
for ($x=0; $x -lt $PureHostGroups.count; $x++)
{
    $PureHosts += $PureHostGroups.hostcount[$x]
}

if ($PureHostGroups.count -gt 0 -or $PureHosts -gt 0)
{
        Add-Content $logfile "FlashArray has $($PureHosts) Pure Host Objects set."
        Add-Content $logfile "FlashArray has $($PureHostGroups.count) Pure Host Groups set."
        add-content $logfile "***********************************************************************************************"
        Add-Content $logfile ""
}
else
{
    Add-Content $logfile "[****NEEDS ATTENTION****] FlashArray does not have any Pure Host Objects or Pure Host Groups configured."
}
<#
# Check for replication
add-content $logfile ""
add-content $logfile "-------------------------------------------------------"
add-content $logfile "Checking for Replication"
add-content $logfile "-------------------------------------------------------"

#$PGroups = New-PfaRestOperation -ResourceType pgroup  -RestOperationType GET  -Flasharray $DefaultFlashArray -SkipCertificateCheck | Where-Object {$_.targets.count -ge 1}
$PurePGroups = Get-Pfa2ProtectionGroup -Array $DefaultFlashArray 
if ($PurePGroups.count -eq $null)
{
    Add-Content $logfile "Ok, no replicated protection groups found."
}

else
{
    foreach ($PurePGroup in $PurePGroups)
    {
        Add-Content $logfile "[****NEEDS ATTENTION****] Protection Group $($PurePGroup.Name) replicates to $($PurePGroup.targets.name). Run this script on the remote side before proceeding with VVols."
    }
}
#>
If ($ConnectFA -eq $true) {
    Disconnect-Pfa2Array -Array $DefaultFlashArray
    Add-Content $Logfile ""
    Add-Content $Logfile "Disconnected from FlashArray:  $($Flasharray.Name)"
}

If ($ConnectVc -eq $true) {
    Disconnect-VIserver -Server $VIFQDN -confirm:$false
    Add-Content $Logfile ""
    Add-Content $Logfile "Disconnected from vCenter:  $($Global:DefaultCisServers.Name)"
}
