<#
*******Disclaimer:**************************************************************
This scripts are offered "as is" with no warranty.  While this script is tested 
and working in my environment, it is recommended that you test this script in a 
test lab before using in a production environment. Everyone can use the scripts/
commands provided here without any written permission, I, Cody Hosterman, and  
Pure Storage, will not be liable for any damage or loss to the system. This 
is not an intrusive script, and wil make no changes to a vSphere environment
************************************************************************

This script will:
-Check for a SATP rule for Pure Storage FlashArrays
-Report correct and incorrect FlashArray rules
-Check for individual devices that are not configured properly

All information logged to a file. 

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-FlashArray 400 Series, //m, //x, & //c
-vCenter 6.5 and later
-PowerCLI 10 or later required
-PowerShell Core supported

Notes:
-iSCSI Configurations where Port Binding is not used will throw an error, but are still supported
 Please consult VMware KB article https://kb.vmware.com/s/article/2038869 

For info, refer to https://www.jasemccarty.com/blog/updated-purestorage-fa-bp-checker-for-vsphere/
#>

$iopsvalue = 1
$minpaths = 4


#Create log if non-existent
$Currentpath = split-path -parent $MyInvocation.MyCommand.Definition 
$Logfile = $Currentpath + '\PureStorage-vSphere-' + (Get-Date -Format o |Foreach-Object {$_ -Replace ':', '.'}) + "-checkbestpractices.log"

Add-Content $Logfile '             __________________________'
Add-Content $Logfile '            /++++++++++++++++++++++++++\'           
Add-Content $Logfile '           /++++++++++++++++++++++++++++\'           
Add-Content $Logfile '          /++++++++++++++++++++++++++++++\'         
Add-Content $Logfile '         /++++++++++++++++++++++++++++++++\'        
Add-Content $Logfile '        /++++++++++++++++++++++++++++++++++\'       
Add-Content $Logfile '       /++++++++++++/----------\++++++++++++\'     
Add-Content $Logfile '      /++++++++++++/            \++++++++++++\'    
Add-Content $Logfile '     /++++++++++++/              \++++++++++++\'   
Add-Content $Logfile '    /++++++++++++/                \++++++++++++\'  
Add-Content $Logfile '   /++++++++++++/                  \++++++++++++\' 
Add-Content $Logfile '   \++++++++++++\                  /++++++++++++/' 
Add-Content $Logfile '    \++++++++++++\                /++++++++++++/' 
Add-Content $Logfile '     \++++++++++++\              /++++++++++++/'  
Add-Content $Logfile '      \++++++++++++\            /++++++++++++/'    
Add-Content $Logfile '       \++++++++++++\          /++++++++++++/'     
Add-Content $Logfile '        \++++++++++++\'                   
Add-Content $Logfile '         \++++++++++++\'                           
Add-Content $Logfile '          \++++++++++++\'                          
Add-Content $Logfile '           \++++++++++++\'                         
Add-Content $Logfile '            \------------\'
Add-Content $Logfile 'Pure Storage FlashArray VMware ESXi Best Practices Checker Script v5.0 (FEBRUARY-2021)'
Add-Content $Logfile '----------------------------------------------------------------------------------------------------'

# Get the PowerCLI Version
$PowerCLIVersion = Get-Module -Name VMware.PowerCLI -ListAvailable | Select-Object -Property Version

# If the PowerCLI Version is not v10 or higher, recommend that the user install PowerCLI 10 or higher
If ($PowerCLIVersion.Version.Major -ge "10") {
    Write-Host "PowerCLI version 10 or higher present, " -NoNewLine
    Write-Host "proceeding" -ForegroundColor Green 
} else {
    Write-Host "PowerCLI version could not be determined or is less than version 10" -Foregroundcolor Red
    Write-Host "Please install PowerCLI 10 or higher and rerun this script" -Foregroundcolor Yellow
    Write-Host " "
    exit
}

# Set the PowerCLI configuration to ignore incd /self-signed certificates
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$False | Out-Null 

# Check to see if a current vCenter Server session is in place
If ($Global:DefaultVIServer) {
    Write-Host "Connected to " -NoNewline 
    Write-Host $Global:DefaultVIServer -ForegroundColor Green
} else {
    # If not connected to vCenter Server make a connection
    Write-Host "Not connected to vCenter Server" -ForegroundColor Red
    $VIFQDN = Read-Host "Please enter the vCenter Server FQDN"  
    # Prompt for credentials using the native PowerShell Get-Credential cmdlet
    $VICredentials = Get-Credential -Message "Enter credentials for vCenter Server" 
    try {
        # Attempt to connect to the vCenter Server 
        Connect-VIServer -Server $VIFQDN -Credential $VICredentials -ErrorAction Stop | Out-Null
        Write-Host "Connected to $VIFQDN" -ForegroundColor Green 
        # Note that we connected to vCenter so we can disconnect upon termination
        $ConnectVc = $True
    }
    catch {
        # If we could not connect to vCenter report that and exit the script
        Write-Host "Failed to connect to $VIFQDN" -BackgroundColor Red
        Write-Host $Error
        Write-Host "Terminating the script " -BackgroundColor Red
        # Note that we did not connect to vCenter Server
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

# Begin the main execution of the script
$errorHosts = @()
Write-Host "Executing..."
Add-Content $Logfile "Iterating through all ESXi hosts..."
$Hosts | Out-String | Add-Content $Logfile

Add-Content $Logfile "***********************************************************************************************"

#Iterating through each host in the vCenter
Foreach ($Esx in $Hosts) 
{

    # Only perform these actions on hosts are available
    If ((Get-VMhost -Name $Esx.Name).ConnectionState -ne "NotResponding") {

        $EsxError = $false

        # Connect to the EsxCli instance for the current host
        $EsxCli = Get-EsxCli -VMHost $Esx -V2

        # Retrieve the current vSphere Host Version/Release/Profile
        # This is neccessary because SATP rules & Disk MaxIO Size 
        # are different for different builds of vSphere 
        $HostVersionMajor = $Esx.Version.Split(".")[0]
        $HostVersionMinor = $Esx.Version.Split(".")[1]
        $HostProfileName  = $EsxCli.software.profile.get.Invoke().name.Split("-")[2]

        # vSphere 6.x requires IOPS=1 & vSphere 7.0 uses the Latency policy
        # DiskMaxIO is 4MB for older versions of vSphere & the default of 32MB for more recent versions
        Switch ($HostVersionMajor) {
            "7" { $MaxIORecommended = "32767";$PspOptions="policy=latency";$SatpType="latency"}
            "5" { $MaxIORecommended = "4096";$PspOptions="iops=1";$SatpType="iops"}
            default {
                Switch ($HostVersionMinor) {
                    "7" { If ($esxcli.system.version.get.invoke().update -ge "1") {$MaxIORecommended = "32767"};$PspOptions="iops=1"}
                    "5" { If ($HostProfileName -ge "201810002") { $MaxIORecommended = "32767"} else {$MaxIORecommended = "4096"};$PspOptions="iops=1"}
                    "0" { If ($HostProfileName -ge "201909001") { $MaxIORecommended = "32767"} else {$MaxIORecommended = "4096"};$PspOptions="iops=1"}
                }
            }
        }

        Add-Content $Logfile "***********************************************************************************************"
        Add-Content $Logfile " Started check on ESXi host: $($Esx.NetworkInfo.hostname), version $($Esx.Version)"
        Add-Content $Logfile "-----------------------------------------------------------------------------------------------"
        Add-Content $Logfile "  Checking Disk.DiskMaxIoSize setting.    "

        # Get and check the Max Disk IO Size
        $maxiosize = $Esx | Get-AdvancedSetting -Name Disk.DiskMaxIOSize
        if ($maxiosize.value -gt $MaxIORecommended) {
            $EsxError = $true
            Add-Content $Logfile "    FAIL - Disk.DiskMaxIOSize too high ($($maxiosize.value) KB) - Recommended $MaxIORecommended KB"
        }
        else {
            Add-Content $Logfile "    PASS - Disk.DiskMaxIOSize is set properly."
        }
        Add-Content $Logfile "  -------------------------------------------------------"


        # Check VAAI Settings
        Add-Content $Logfile "  Checking host-wide settings for VAAI.     " 
        $vaaiIssues = $false

        # Check Xcopy
        $Xcopy = $Esx | Get-AdvancedSetting -Name DataMover.HardwareAcceleratedMove
        if ($Xcopy.value -eq 0)
        {
            $EsxError = $true
            Add-Content $Logfile "    FAIL - The VAAI XCOPY (Full Copy) feature is not enabled on this host, it should be enabled."
            $vaaiIssues = $true
        }

        # Check writesame
        $writesame = $Esx | Get-AdvancedSetting -Name DataMover.HardwareAcceleratedInit
        if ($writesame.value -eq 0)
        {
            $EsxError = $true
            Add-Content $Logfile "    FAIL - The VAAI WRITESAME (Block Zero) feature is not enabled on this host, it should be enabled."
            $vaaiIssues = $true
        }

        # Check atslocking
        $atslocking = $Esx | Get-AdvancedSetting -Name VMFS3.HardwareAcceleratedLocking
        if ($atslocking.value -eq 0)
        {
            $EsxError = $true
            Add-Content $Logfile "    FAIL - The VAAI ATOMIC TEST & SET (Assisted Locking) feature is not enabled on this host, it should be enabled."
            $vaaiIssues = $true
        }

        # CHeck Use ATS for Heartbeat on VMFS5
        if (($datastore -ne $null) -and ($HostVersionMajor -ge "6"))
        { 
            $atsheartbeat = $Esx | Get-AdvancedSetting -Name VMFS3.useATSForHBOnVMFS5
            if ($atsheartbeat.value -eq 0)
            {
                $EsxError = $true
                Add-Content $Logfile "    FAIL - Datastore Heartbeating is not configured to use the VAAI ATOMIC TEST & SET (Assisted Locking) feature, it should be enabled."
                $vaaiIssues = $true
            }
        }
        if ($vaaiIssues -eq $false)
        {
            Add-Content $Logfile "    PASS - No issues with VAAI configuration found on this host"
        }
    
        # Check for iSCSI targets 
        Add-Content $Logfile "  -------------------------------------------------------------------------------------------------------------------------------------------"
        Add-Content $Logfile "  Checking for FlashArray iSCSI targets and verify their configuration on the host. Only misconfigured iSCSI targets will be reported."
        $iscsitofix = @()
        $flasharrayiSCSI = $false

        # Get a list of all of the Pure Storage iSCSI Targets (if any)
        $targets = $esxcli.iscsi.adapter.target.portal.list.Invoke().where{$_.Target -Like "*purestorage*"}

        # Store the iSCSI Software Adaper in a variable
        $iscsihba = $Esx | Get-VMHostHba |Where-Object{$_.Model -eq "iSCSI Software Adapter"}

        # Store any Static targets 
        $statictgts = $iscsihba | Get-IScsiHbaTarget -type static

        # Enumerate through all iSCSI targets
        Foreach ($target in $targets) {
            if ($target) {
                $flasharrayiSCSI = $true

                # Check for DelayedACK = False and LoginTimeout = 30
                Foreach ($statictgt in $statictgts) {
                    if ($target.IP -eq $statictgt.Address) {
                        $iscsioptions = $statictgt.ExtensionData.AdvancedOptions
                        Foreach ($iscsioption in $iscsioptions) {
                            if ($iscsioption.key -eq "DelayedAck")    {$iscsiack = $iscsioption.value}
                            if ($iscsioption.key -eq "LoginTimeout")  {$iscsitimeout = $iscsioption.value}
                        }
                        if (($iscsiack -eq $true) -or ($iscsitimeout -ne 30)) {
                            if ($iscsiack -eq $true) {$iscsiack = "Enabled"}
                            else {$iscsiack = "Disabled"}
                            # Create an object to better report iSCSI targets
                            $iscsitgttofix = new-object psobject -Property @{
                                TargetIP = $target.IP
                                TargetIQN = $target.Target
                                DelayedAck = $iscsiack 
                                LoginTimeout  = $iscsitimeout
                                }
                            $iscsitofix += $iscsitgttofix
                        }
                    }
                }
            }
        }
        # If there are any iSCSI targets with issues, report them here
        if ($iscsitofix.count -ge 1)
        {
            $EsxError = $true
            Add-Content $Logfile ("    FAIL - A total of " + ($iscsitofix | select-object -unique).count + " FlashArray iSCSI targets have one or more errors.")
            Add-Content $Logfile  "    Each target listed has an issue with at least one of the following configurations:"
            Add-Content $Logfile ("    --The target does not have DelayedAck disabled")
            Add-Content $Logfile ("    --The target does not have the iSCSI Login Timeout set to 30")
            $tableofiscsi = @(
                            'TargetIP'
                                @{Label = '    TargetIQN'; Expression = {$_.TargetIQN}; Alignment = 'Left'} 
                                @{Label = '    DelayedAck'; Expression = {$_.DelayedAck}; Alignment = 'Left'}
                                @{Label = '    LoginTimeout'; Expression = {$_.LoginTimeout}; Alignment = 'Left'}
                            )
            $iscsitofix | Format-Table -Property $tableofiscsi -AutoSize| Out-String | Add-Content $Logfile
        }
        else
        {
            Add-Content $Logfile "     PASS - No FlashArray iSCSI targets were found with configuration issues."
        }
    
        Add-Content $Logfile "  -------------------------------------------------------------------------------------------------------------------------------------------"
        Add-Content $Logfile "  Checking for Software iSCSI Network Port Bindings."

        # Check for network port binding configuration
        if ($flasharrayiSCSI -eq $true)
        {
            $iSCSInics = $Esxcli.iscsi.networkportal.list.invoke()
            $goodnics = @()
            $badnics = @()
            if ($iSCSInics.Count -gt 0)
            {
                Foreach ($iSCSInic in $iSCSInics)
                {
                    if (($iSCSInic.CompliantStatus -eq "compliant") -and (($iSCSInic.PathStatus -eq "active") -or ($iSCSInic.PathStatus -eq "unused")))
                    {
                        $goodnics += $iSCSInic
                    }
                    else
                    {
                        $badnics += $iSCSInic
                    }
                }
            
                if ($goodnics.Count -lt 2)
                {
                    Add-Content $Logfile ("    Found " + $goodnics.Count + " COMPLIANT AND ACTIVE NICs out of a total of " + $iSCSInics.Count + "NICs bound to this adapter")
                    $nicstofix = @()
                    $EsxError = $true
                    Add-Content $Logfile "      FAIL - There are less than two COMPLIANT and ACTIVE NICs bound to the iSCSI software adapter. It is recommended to have two or more."
                    if ($badnics.count -ge 1)
                    {
                        Foreach ($badnic in $badnics)
                        {
                            $nictofix = new-object psobject -Property @{
                                        vmkName = $badnic.Vmknic
                                        CompliantStatus = $badnic.CompliantStatus
                                        PathStatus = $badnic.PathStatus 
                                        vSwitch  = $badnic.Vswitch
                                        }
                            $nicstofix += $nictofix
                        }
                        $tableofbadnics = @(
                                        'vmkName'
                                            @{Label = '    ComplianceStatus'; Expression = {$_.CompliantStatus}; Alignment = 'Left'} 
                                            @{Label = '    PathStatus'; Expression = {$_.PathStatus}; Alignment = 'Left'}
                                            @{Label = '    vSwitch'; Expression = {$_.vSwitch}; Alignment = 'Left'}
                                        )
                        Add-Content $Logfile "    The following are NICs that are bound to the iSCSI Adapter but are either NON-COMPLIANT, INACTIVE or both. Or there is less than 2."
                        $nicstofix | Format-Table -property $tableofbadnics -autosize| out-string | Add-Content $Logfile
                    }
                }
                else 
                {
                    Add-Content $Logfile ("      Found " + $goodnics.Count + " NICs that are bound to the iSCSI Adapter and are COMPLIANT and ACTIVE. No action needed.")
                }
            }
            else
            {
                $EsxError = $true
                Add-Content $Logfile "   FAIL - There are ZERO NICs bound to the software iSCSI adapter. This is strongly discouraged. Please bind two or more NICs"
            }
        }
        if ($flasharrayiSCSI -eq $false)
        {
            Add-Content $Logfile "    No FlashArray iSCSI targets found on this host"
        }


        # Check the NMP rules

        Add-Content $Logfile "  -------------------------------------------------------------------------------------------------------------------------------------------"
        Add-Content $Logfile "  Checking VMware NMP Multipathing configuration for FlashArray devices."
        $rules = $Esxcli.storage.nmp.satp.rule.list.invoke() | Where-Object {$_.Vendor -eq "PURE"}
        $correctrule = 0

        # If vSphere 7, default to Latency, otherwise use IOPS=1
        Switch ($HostVersionMajor) {
            "7" { $SatpOption = "policy";$SatpType="latency"}
            default { $SatpOption = "iops";$SatpType="iops"}
        }

        $iopsoption = "iops=" + $iopsvalue
    
        if ($rules.Count -ge 1)
        {
            Add-Content $Logfile ("   Found " + $rules.Count + " existing Pure Storage SATP rule(s)")
            if ($rules.Count -gt 1)
            {
                $EsxError = $true
                Add-Content $Logfile "    CAUTION - There is more than one rule. The last rule found will be the one in use. Ensure this is intentional."
            }
            Foreach ($rule in $rules)
            {
                Add-Content $Logfile "   -----------------------------------------------"
                Add-Content $Logfile ""
                Add-Content $Logfile "      Checking the following existing rule:"
                ($rule | out-string).TrimEnd() | Add-Content $Logfile
                Add-Content $Logfile ""
                $issuecount = 0

                # Path Selection Policy Check - This should be Round Robin for vSphere 6.5/6.7/7.0
                if ($rule.DefaultPSP -ne "VMW_PSP_RR") 
                {
                    $EsxError = $true
                    Add-Content $Logfile "      FAIL - This Pure Storage FlashArray rule is NOT configured with the correct Path Selection Policy: $($rule.DefaultPSP)"
                    Add-Content $Logfile "      The rule should be configured to Round Robin (VMW_PSP_RR)"
                    $issuecount = 1
                }

                # SATP Rule Check 
                Switch ($HostVersionMajor) {
                    "7" {
                        if ($rule.PSPOptions -ne "policy=latency") {
                            $EsxError = $true
                            Add-Content $Logfile "      FAIL - This Pure Storage FlashArray rule is NOT configured with the correct Policy = Latency: $($rule.PSPOptions)"
                            Add-Content $Logfile "      The rule should be configured to Policy of Latency"
                            $issuecount = $issuecount + 1
                            }
                        } 
                    default {
                        if ($rule.PSPOptions -ne $iopsoption) 
                        {
                            $EsxError = $true
                            Add-Content $Logfile "      FAIL - This Pure Storage FlashArray rule is NOT configured with the correct IO Operations Limit: $($rule.PSPOptions)"
                            Add-Content $Logfile "      The rule should be configured to an IO Operations Limit of $($iopsvalue)"
                            $issuecount = $issuecount + 1
                        } 
                    }
        
                    }
                
                if ($rule.Model -ne "FlashArray") 
                {
                    $EsxError = $true
                    Add-Content $Logfile "      FAIL - This Pure Storage FlashArray rule is NOT configured with the correct model: $($rule.Model)"
                    Add-Content $Logfile "      The rule should be configured with the model of FlashArray"
                    $issuecount = $issuecount + 1
                } 
                if ($issuecount -ge 1)
                {
                    $EsxError = $true
                    Add-Content $Logfile "      FAIL - This rule is incorrect and should be removed."
                }
                else
                {
                    Add-Content $Logfile "      This rule is correct."
                    $correctrule = 1
                }
            }
        }
        if ($correctrule -eq 0)
        { 
            $EsxError = $true 
            Add-Content $Logfile "      FAIL - No correct SATP rule for the Pure Storage FlashArray is found"
            Add-Content $LogFile "      A new rule should be created that is set Round Robin" -NoNewline
            Switch ($HostVersionMajor) {
                "7" { Add-Content $LogFile " using the Latency policy"}
                default { Add-Content $LogFile " and an IO Opeations limit of $($iopsvalue)"}
            }
        }

        $devices = $Esx |Get-ScsiLun -CanonicalName "naa.624a9370*"
        if ($devices.count -ge 1) 
        {
            Add-Content $Logfile "   -------------------------------------------------------------------------------------------------------------------------------------------"
            Add-Content $Logfile "   Checking for existing Pure Storage FlashArray devices and their multipathing configuration."
            Add-Content $Logfile ("      Found " + $devices.count + " existing Pure Storage volumes on this host.")
            Add-Content $Logfile "      Checking their configuration now. Only listing devices with issues."
            Add-Content $Logfile "      Checking for Path Selection Policy, Path Count, Storage Array Type Plugin Rules, and AutoUnmap Settings"
            Add-Content $Logfile ""
            $devstofix = @()
            Foreach ($device in $devices)
            {
                $devpsp = $false
                $deviops = $false
                $devpaths = $false
                $devATS = $false
                $datastore = $null
                $autoUnmap = $false
                if ($device.MultipathPolicy -ne "RoundRobin")
                {
                    $devpsp = $true
                    $psp = $device.MultipathPolicy
                    $psp = "$psp" + "*"
                }
                else
                {
                    $psp = $device.MultipathPolicy
                }
                $deviceargs = $Esxcli.storage.nmp.psp.roundrobin.deviceconfig.get.createargs()
                $deviceargs.device = $device.CanonicalName

                Switch ($device.MultipathPolicy) {
                    "RoundRobin" {
                        $deviceconfig = $Esxcli.storage.nmp.psp.roundrobin.deviceconfig.get.invoke($deviceargs)

                        Switch ($HostVersionMajor) {
                            "7" {
                                if ($deviceconfig.LimitType -ne "Latency")
                                {
                                    $deviops = $true
                                    $iops = $deviceconfig.LimitType
                                    $iops = $iops + "*"
                                }
                                else
                                { $iops = $deviceconfig.LimitType }
                            }
                            default {
                                if ($deviceconfig.IOOperationLimit -ne $iopsvalue)
                                {
                                    $deviops = $true
                                    $iops = $deviceconfig.IOOperationLimit
                                    $iops = $iops + "*"
                                }
                                else
                                { $iops = $deviceconfig.IOOperationLimit }
                            }
                        }
                    }
                    default {
                        $iops = "Not Available"
                    }
                }


                if ($device.MultipathPolicy -eq "RoundRobin")
                {

                }
                if (($device |get-scsilunpath).count -lt $minpaths)
                {
                    $devpaths = $true
                    $paths = ($device |get-scsilunpath).count
                    $paths = "$paths" + "*"
                }
                else
                {
                    $paths = ($device |get-scsilunpath).count
                }
                $datastore = $Esx |Get-Datastore | Where-Object { $_.ExtensionData.Info.Vmfs.Extent.DiskName -eq $device.CanonicalName }
                if (($datastore -ne $null) -and ($Esx.version -like ("6.*")))
                {
                    $vmfsargs = $Esxcli.storage.vmfs.lockmode.list.CreateArgs()
                    $vmfsargs.volumelabel = $datastore.name
                    try {
                        $vmfsconfig = $Esxcli.storage.vmfs.lockmode.list.invoke($vmfsargs)
    
                        if ($vmfsconfig.LockingMode -ne "ATS")
                        {
                            $devATS = $true
                            $ATS = $vmfsconfig.LockingMode
                            $ATS = $ATS + "*" 
                        }
                        else
                        {
                            $ATS = $vmfsconfig.LockingMode
                        }
                    } 
                    catch {
                        $ATS = "Not Available"
                    }
    
    
                    if ($datastore.ExtensionData.info.vmfs.version -like "6.*")
                    {
                        $unmapargs = $Esxcli.storage.vmfs.reclaim.config.get.createargs()
                        $unmapargs.volumelabel = $datastore.name
    #####
                        try {
                            $unmapresult = $Esxcli.storage.vmfs.reclaim.config.get.invoke($unmapargs)
                            if ($unmapresult.ReclaimPriority -ne "low")
                            {
                                $autoUnmap = $true
                                $autoUnmapPriority = "$($unmapresult.ReclaimPriority)*"
                            }
                            elseif ($unmapresult.ReclaimPriority -eq "low")
                            {
                                $autoUnmapPriority = "$($unmapresult.ReclaimPriority)"
                            }
    
                            $autoUnmap = $False
                            $autoUnmapPriority = "$($unmapresult)"
                        }
                        catch {
                            $autoUnmap = $False
                            $autoUnmapPriority = "Not Available"
                        }
                    }
                    else 
                    {
                        
                    }
                }
                if ($deviops -or $devpsp -or $devpaths -or $devATS -or $autoUnmap)
                {
                     $devtofix = new-object psobject -Property @{
                        NAA = $device.CanonicalName
                        PSP = $psp 
                        SATP = $iops
                        PathCount  = $paths
                        DatastoreName = if ($datastore -ne $null) {$datastore.Name}else{"N/A"}
                        VMFSVersion = if ($datastore -ne $null) {$datastore.ExtensionData.info.vmfs.version}else{"N/A"}
                        ATSMode = if (($datastore -ne $null) -and ($Esx.version -like ("6.*"))) {$ATS}else{"N/A"}
                        AutoUNMAP = if (($datastore -ne $null) -and ($datastore.ExtensionData.info.vmfs.version -like "6.*")) {$autoUnmapPriority}else{"N/A"}
                       }
                    $devstofix += $devtofix
                }
            }
            if ($devstofix.count -ge 1)
            {
                $EsxError = $true
                Add-Content $Logfile ("      FAIL - A total of " + $devstofix.count + " FlashArray devices have one or more errors.")
                Add-Content $Logfile  ""
                Add-Content $Logfile  "       Each device listed has an issue with at least one of the following configurations:"
                Add-Content $Logfile  "       --Path Selection Policy is not set to Round Robin (VMW_PSP_RR)"
                Add-Content $Logfile ("       --IO Operations Limit (IOPS) is not set to the recommended value (" + $iopsvalue + ")")
                Add-Content $Logfile ("       --The device has less than the minimum recommended logical paths (" + $minpaths + ")")
                Add-Content $Logfile ("       --The VMFS on this device does not have ATSonly mode enabled.")
                Add-Content $Logfile ("       --The VMFS-6 datastore on this device does not have Automatic UNMAP enabled. It should be set to low.")
                Add-Content $Logfile  ""
                Add-Content $Logfile "        Settings that need to be fixed are marked with an asterisk (*)"
    
                $tableofdevs = @(
                                'NAA' 
                                    @{Label = 'PSP'; Expression = {$_.PSP}; Alignment = 'Left'}
                                    @{Label = 'PathCount'; Expression = {$_.PathCount}; Alignment = 'Left'}
                                    @{Label = 'Storage Rule'; Expression = {$_.SATP}; Alignment = 'Left'}
                                    @{Label = 'DatastoreName'; Expression = {$_.DatastoreName}; Alignment = 'Left'}
                                    @{Label = 'VMFSVersion'; Expression = {$_.VMFSVersion}; Alignment = 'Left'}
                                    @{Label = 'ATSMode'; Expression = {$_.ATSMode}; Alignment = 'Left'}
                                    @{Label = 'AutoUNMAP'; Expression = {$_.AutoUNMAP}; Alignment = 'Left'}
                                )
                ($devstofix | Format-Table -property $tableofdevs -autosize| out-string).TrimEnd() | Add-Content $Logfile
            }
            else
            {
                Add-Content $Logfile "      PASS - No devices were found with configuration issues."
            }
        }
        else
        {
            Add-Content $Logfile "      No existing Pure Storage volumes found on this host."
        }


        Add-Content $Logfile ""
        Add-Content $Logfile " Completed check on ESXi host: $($Esx.NetworkInfo.hostname)"
        Add-Content $Logfile "***********************************************************************************************"
        if ($EsxError -eq $true)
        {
            $errorHosts += $Esx
        }

    } # End of Hosts that are online
    else {
        $EsxError = $true
        $errorHosts += $Esx
    }
} # End of Enumerating $Hosts
if ($errorHosts.count -gt 0)
{
    $tempText = Get-Content $Logfile
    "The following hosts have errors. Search for ****NEEDS ATTENTION**** for details" |Out-File $Logfile
    Add-Content $Logfile $errorHosts
    Add-Content $Logfile $tempText
    Add-Content $Logfile ""
    Add-Content $Logfile ""
}
    If ($ConnectVc -eq $true) {
        Disconnect-VIserver -Server $VIFQDN -confirm:$false
        Add-Content $Logfile "Disconnected vCenter connection"
    }

 Write-Host "Check complete."
 Write-Host ""
 if ($errorHosts.count -gt 0)
 {
    Write-Host "Errors on the following hosts were found:"
    Write-Host "==========================================="
    Write-Host $errorHosts
 }
 else 
 {
    Write-Host "No errors were found."    
 }
 Write-Host ""
 Write-Host "Refer to log file for detailed results." -ForegroundColor Green
 
