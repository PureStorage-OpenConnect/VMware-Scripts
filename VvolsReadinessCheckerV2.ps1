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
--Check for replication, remote side needs to meet above criteria too!

All information logged to a file.

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-FlashArray //X, //C, //XL
-vCenter 7.0U3 and later
-PowerCLI VMware PowerCLI 13.3 or later required

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
$Logfile = $Currentpath + '\PureStorage-vSphere-' + (Get-Date -Format o |Foreach-Object {$_ -Replace ':', '.'}) + "-checkbestvvolreadiness.log"

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
add-content $logfile 'Pure Storage FlashArray VMware VVols Readiness Checker v3.0 (OCTOBER-2024)'
add-content $logfile '----------------------------------------------------------------------------------------------------'

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
        Write-Host $Global:DefaultCisServers -ForegroundColor Green -NoNewline
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
            Write-Host "Connected to " -NoNewline
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
Add-Content $Logfile "Connected to vCenter at $($Global:DefaultVIServer)"
Add-Content $Logfile '----------------------------------------------------------------------------------------------------'

# Choose to run the script against all hosts connected to a vCenter Server, or a single cluster
Do{ $clusterChoice = Read-Host "Would you prefer to limit this to hosts in a specific cluster? (y/n)" }
Until($clusterChoice -eq "Y" -or $clusterChoice -eq "N")

# Choose a single cluster
if ($clusterChoice -match "[yY]") {
    # Retrieve the clusters & sort them alphabetically 
    $clusters = Get-Cluster | Sort-Object Name

    # If no clusters are found, exit the script
    if ($clusters.count -lt 1)
    {
        Add-Content $Logfile "Terminating Script. No VMware cluster(s) found."  
        Write-Host "No VMware cluster(s) found. Terminating Script" -BackgroundColor Red
        exit
    }

    # Select the Cluster
    Write-Host "1 or more clusters were found. Please choose a cluster:"
    Write-Host ""

    # Enumerate the cluster(s)
    1..$Clusters.Length | Foreach-Object { Write-Host $($_)":"$Clusters[$_-1]}

    # Wait until a valid cluster is picked
    Do
    {
        Write-Host # empty line
        $Global:ans = (Read-Host 'Please select a cluster') -as [int]
    
    } While ((-not $ans) -or (0 -gt $ans) -or ($Clusters.Length+1 -lt $ans))

    # Assign the $Cluster variable to the Cluster picked
    $Cluster = $clusters[($ans-1)]

    # Log/Enumerate which cluser was selected
    Add-Content $Logfile "Selected cluster is $($Cluster)"
    Add-Content $Logfile ""
    Write-Host "Selected cluster is " -NoNewline 
    Write-Host $Cluster -ForegroundColor Green
    Write-Host ""

    # Assign all of the hosts in $Cluster to the $Hosts variable, and sort the list alphabetically
    $Hosts = $Cluster | Get-VMHost | Sort-Object Name

}  else {

    # Because individual clusters were not selected
    # Assign all of the hosts vCenter manages into the $Hosts variable & sort them alphabetically
    $Hosts = Get-VMHost | Sort-Object Name 
}

If ($DefaultFlashArray) {
    Write-Host "Defaulting to FlashArray: $($DefaultFlashArray.Endpoint) "
    Add-Content $Logfile "Defaulting to FlashArray: $($DefaultFlashArray.Endpoint)"
    $ConnectFA = $False
} else {
    #connect to FlashArray
    $FaEndPoint = Read-Host "Please enter a FlashArray IP or FQDN"
    try
    {
        $FaCredentials = Get-Credential -Message "Please enter the FlashArray Credentials for $($FaEndPoint)"
        $FlashArray = New-PfaConnection -EndPoint $FaEndpoint -Credentials $FaCredentials -ErrorAction Stop -IgnoreCertificateError -DefaultArray
        $ConnectFA = $True
    }
    catch
    {
        write-host "Failed to connect to FlashArray" -BackgroundColor Red
        write-host $Error
        write-host "Terminating Script" -BackgroundColor Red
        add-content $logfile "Failed to connect to FlashArray"
        add-content $logfile $Error
        add-content $logfile "Terminating Script"
        $ConnectFA = $False

        return
    }

}


$errorHosts = @()
write-host "Executing..."

# Check vCenter version
add-content $logfile "Working on the following vCenter: $($global:DefaultVIServers.name), version $($Global:DefaultVIServers.Version)"
add-content $logfile "-----------------------------------------------------------------------------------------------"
add-content $logfile "Checking vCenter Version"
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
    add-content $logfile "vCSA NTP "
    add-content $logfile "-------------------------------------------------------"
    If ($vCenterTime.NTPStatus -eq "SERVER_REACHABLE") {
        add-content $logfile "NTP server set to $($vCenterTime.NTPServers) and is REACHABLE from vCenter"
    } else {
        add-content $logfile "-------------------------------------------------------"
        add-content $logfile "[****NEEDS ATTENTION****] vCSA's NTP settings aren't checkable."
        add-content $logfile "Check VMware KB for manual process: https://knowledge.broadcom.com/external/article?articleNumber=313945"        
    }

} else {
    add-content $logfile "*-------------------------------------------------------"
    add-content $logfile "[****NEEDS ATTENTION****] vCSA's NTP settings aren't checkable."
    add-content $logfile "Check VMware KB for manual process: https://knowledge.broadcom.com/external/article?articleNumber=313945."        
}


# Iterating through each host in the vCenter
add-content $logfile ""
add-content $logfile "Iterating through all ESXi hosts in cluster $clusterName..."
$hosts | out-string | add-content $logfile
foreach ($esx in $hosts)
{
    add-content $logfile ""
    add-content $logfile "***********************************************************************************************"
    add-content $logfile "**********************************NEXT ESXi HOST***********************************************"
    add-content $logfile "-----------------------------------------------------------------------------------------------"
    add-content $logfile "Working on the following ESXi host: $($esx.Name), version $($esx.Version)"
    add-content $logfile "-----------------------------------------------------------------------------------------------"
    add-content $logfile "Checking ESXi Version"
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
    add-content $logfile "Checking NTP settings"
    add-content $logfile "-------------------------------------------------------"

    # Check for NTP server configuration
    $ntpServer = Get-VMHostNtpServer -VMHost $esx
# Check for NTP server configuration
$ntpServer = Get-VMHostNtpServer -VMHost $esx
if ($ntpServer -eq $null)
{
   Add-Content $logfile "[****NEEDS ATTENTION****] NTP server for this host is null. Configure an NTP server before proceeding with VVols."
}
else
{
    Add-Content $logfile "NTP server set to $($ntpServer)"
    If ($PSEdition -eq "Core") {
        $testNetConnection = Test-Connection -TargetName $ntpserver 
    } else {
        $testNetConnection = Test-NetConnection -ComputerName $ntpServer -InformationLevel Quiet
    }


    if (!$testNetConnection)
    {
        Add-Content $logfile "[****NEEDS ATTENTION****] Could not communicate with NTP server from this console. Check that it is valid and accessible."
    }
    else
    {
        Add-Content $logfile "NTP server is valid and accessible."
    }
}


    # Check for NTP daemon running and enabled
    $ntpSettings = $esx | Get-VMHostService | Where-Object {$_.key -eq "ntpd"} | select vmhost, policy, running

    if ($ntpSettings."policy" -contains "off")
    {
        Add-Content $logfile "[****NEEDS ATTENTION****] NTP daemon not enabled. Enable service in host configuration."
    }
    else
    {
     Add-Content $logfile "NTP daemon is enabled."
    }

    if ($ntpSettings."running" -contains "true")
    {
        Add-Content $logfile "NTP daemon is running."
    }
    else
    {
        Add-Content $logfile "[****NEEDS ATTENTION****] NTP daemon is not running."
    }
}

# Check FlashArray's NTP Settings
$ArrayId = New-PfaRestOperation -ResourceType array -RestOperationType GET -Flasharray $DefaultFlashArray -SkipCertificateCheck
add-content $logfile ""
add-content $logfile "***********************************************************************************************"
add-content $logfile "**********************************FLASHARRAY***************************************************"
add-content $logfile "-----------------------------------------------------------------------------------------------"
add-content $logfile "Working on the following FlashArray: $($DefaultFlasharray.EndPoint), Purity version $($ArrayId.version)"
add-content $logfile "-----------------------------------------------------------------------------------------------"
add-content $logfile ""
add-content $logfile "-------------------------------------------------------"
add-content $logfile "Checking NTP Setting"
add-content $logfile "-------------------------------------------------------"
$FlashArrayNTP = New-PfaRestOperation -ResourceType array  -RestOperationType GET -queryFilter "?ntpserver=true" -Flasharray $DefaultFlashArray -SkipCertificateCheck
if (!$flashArrayNTP.ntpserver)
{
    Add-Content $logfile "[****NEEDS ATTENTION****] FlashArray does not have an NTP server configured."
}
else
{
    Add-Content $logfile "FlashArray has the following NTP server configured: $($flasharrayNTP.ntpserver)"
    If ($PSEdition -eq "Core") {
        $testNetConnection = Test-Connection -TargetName $FlashArrayNTP.ntpserver
    } else {
        $testNetConnection = Test-NetConnection -ComputerName $FlashArrayNTP.$ntpServer -InformationLevel Quiet
    }

    if (!$testNetConnection)
    {
        Add-Content $logfile "[****NEEDS ATTENTION****] Could not communicate with NTP server from this console. Check that it is valid and accessible."

    }
    else
    {
        Add-Content $logfile "NTP server is valid and accessible."
    }
}
# Check Purity version
add-content $logfile ""
add-content $logfile "-------------------------------------------------------"
add-content $logfile "Checking Purity Version"
add-content $logfile "-------------------------------------------------------"

if ($arrayid.version -ge [Version]"6.5")
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
add-content $logfile "Checking FlashArray Reachability on TCP port 8084"
add-content $logfile "-------------------------------------------------------"

#$interfaces = get-pfanetworkinterfaces -array $DefaultFlashArray | Where-Object { $_.services -like "management" }  | where-object {$_.name -like "ct*"}
$Interfaces = New-PfaRestOperation -ResourceType network  -RestOperationType GET  -Flasharray $DefaultFlashArray -SkipCertificateCheck | Where-Object {$_.services -Like "management"} | Where-Object {$_.name -Like "ct*"} | Where-Object {$_.enabled -eq "True"}
$i = 0
foreach ($interface in $interfaces)
{

    If ($PSEdition -eq "Core") {
        $testNetConnection = Test-Connection -TargetName $interfaces[$i].address -TcpPort 8084 
    } else {
        $testNetConnection = Test-NetConnection -ComputerName $interfaces[$i].address -Port 8084 -InformationLevel Quiet
    }

    if (!$testNetConnection)
    {
        add-content $logfile "[****NEEDS ATTENTION****] Could not reach FlashArray management port $($interface.name), IP: $($interfaces[$i].address) on TCP port 8084."

    }
    else
    {
        add-content $logfile "FlashArray management port $($interface.name) is reachable on TCP port 8084."
    }
    $i += 1
}

# Check for existance of hosts and host groups
add-content $logfile ""
add-content $logfile "-------------------------------------------------------"
add-content $logfile "Checking for Hosts and Host Groups"
add-content $logfile "-------------------------------------------------------"
$HostGroups = New-PfaRestOperation -ResourceType hgroup  -RestOperationType GET  -Flasharray $DefaultFlashArray -SkipCertificateCheck
if ($hostGroups.count -gt 0 -or $hostGroups.hosts.count -gt 0)
{
    Add-Content $logfile "FlashArray has host groups set."
    Add-Content $logfile "FlashArray has hosts set."
}
else
{
    Add-Content $logfile "[****NEEDS ATTENTION****] FlashArray does not have any host or host groups configured."
}

# Check for replication
add-content $logfile ""
add-content $logfile "-------------------------------------------------------"
add-content $logfile "Checking for Replication"
add-content $logfile "-------------------------------------------------------"
#$pgroups = Get-PfaProtectionGroups -Array $DefaultFlashArray | where-object {$_.targets.count -ge 1}
$PGroups = New-PfaRestOperation -ResourceType pgroup  -RestOperationType GET  -Flasharray $DefaultFlashArray -SkipCertificateCheck | Where-Object {$_.targets.count -ge 1}
if ($pgroups -eq $null)
{
    Add-Content $logfile "Ok, no replicated protection groups found."
}

else
{
    foreach ($pgroup in $pgroups)
    {
        Add-Content $logfile "[****NEEDS ATTENTION****] Protection Group $($pgroup.name) replicates to $($pgroup.targets.name). Run this script on the remote side before proceeding with VVols."
    }
}

If ($ConnectFA -eq $true) {
    Disconnect-PfaArray -Array $DefaultFlashArray
    Add-Content $Logfile "Disconnected from FlashArray connection"
}

If ($ConnectVc -eq $true) {
    Disconnect-VIserver -Server $VIFQDN -confirm:$false
    Add-Content $Logfile "Disconnected from vCenter connection"
}
