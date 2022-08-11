<#==========================================================================
Script Name: Copy-VmfsDatastoreFromFlashArraySnapshot.ps1
Created on: 9/20/2021
Created by: Jase McCarty
Github: http://www.github.com/jasemccarty
Twitter: @jasemccarty
Website: http://www.jasemccarty.com
===========================================================================
.DESCRIPTION
Restore a VMFS Datastore from a Snapshot on a FlashArray
Powershell Core supported - Requires PowerCLI, PureStorage.FlashArray.VMware, & PureStoragePowerShellSDK (v1) modules.

.SYNTAX
Copy-VmfsDatastoreFromFlashArraySnapshot.ps1 -TargetvCenter <VCENTER> -TargetFlashArray <FlashArray> -TargetCluster <CusterName> -TargetVmFolder <VmFolder> -SourceVolumeName <SourceVolumeName> -LocalSnapshot <$true/$false> -SourceSnapCount <int> -RegisterVms <$true/$false> -TargetVmFolder <vm folder>
#>

# Set our Parameters
[CmdletBinding()]Param(
  [Parameter(Mandatory=$False)][string]$TargetVcenter,
  [Parameter(Mandatory = $False)][String]$TargetFlashArray,
  [Parameter(Mandatory = $False)][String]$TargetCluster,
  [Parameter(Mandatory = $False)][String]$SourceVolumeName,
  [Parameter(Mandatory = $False)][Boolean]$LocalSnapshot,
  [Parameter(Mandatory = $False)][ValidateRange(1,30)][int] $SourceSnapCount,
  [Parameter(Mandatory = $False)][Boolean]$RegisterVms,
  [Parameter(Mandatory = $False)][String]$TargetVmFolder
)

# Variables Section
# Target Variables - Replace any of these as defaults if parameters are not passed
if (-Not $TargetVcenter)    { $TargetVcenter    = 'vc03.fsa.lab' }                              # Target vCenter
if (-Not $TargetFlashArray) { $TargetFlashArray = 'sn1-m70r2-f07-27.puretec.purestorage.com' }  # Target FlashArray
if (-Not $TargetCluster)    { $TargetCluster    = 'cluster-dr' }                                # Target Cluster
if (-Not $SourceVolumeName) { $SourceVolumeName = 'sn1-m70-f06-33-vc02-jm01'}                   # Source Volume
if (-Not $LocalSnapshot)    { $LocalSnapshot    = $false }                                      # Local or Remote Snapshot
if (-Not $SourceSnapCount)  { $SourceSnapCount  = '1' }                                         # Default to the latest snapshot
if (-Not $TargetVmFolder)   { $TargetVmFolder   = 'Discovered virtual machine' }                # Target VM Folder for snapped VM's
if (-Not $RegisterVms)      { $RegisterVms      = $false }                                      # By default don't register the VM's from the snapshotted datastore

###########################################################
# It should not be necessary to make any changes below    #
###########################################################

###########################################################
# Check for proper PowerShell modules installation        #
###########################################################

# Get the PowerCLI Version
$PowerCLIVersion = Get-Module -Name VMware.PowerCLI -ListAvailable | Select-Object -Property Version

# If the PowerCLI Version is not v10 or higher, recommend that the user install PowerCLI 12 or higher
If ($PowerCLIVersion.Version.Major -ge "12") {
    Write-Host "PowerCLI version 12 or higher present, " -NoNewLine
    Write-Host "proceeding" -ForegroundColor Green 
} else {
    Write-Host "PowerCLI version could not be determined or is less than version 12" -Foregroundcolor Red
    Write-Host "Please install PowerCLI 12 or higher and rerun this script" -Foregroundcolor Yellow
    Write-Host " "
    exit
}
# Check for Pure Storage PowerShell SDK (v1) installation, required to facilitate some FlashArray tasks
If (-Not (Get-Module -ListAvailable -Name "PureStoragePowerShellSDK")) {
    Write-Host "Please install the Pure Storage PowerShell SDK (v1) Module and rerun this script to proceed" -ForegroundColor Yellow
    Write-Host "It can be installed using " -NoNewLine 
    Write-Host "'Install-Module -Name PureStoragePowerShellSDK'" -ForegroundColor Green
    Write-Host 
    exit
}
# Check for Pure Storage FlashArray Module for VMware installation, required to facilitate some VMware-based FlashArray tasks
If (-Not (Get-Module -ListAvailable -Name "PureStorage.FlashArray.VMware")) {
    Write-Host "Please install the Pure Storage FlashArray Module for VMware and rerun this script to proceed" -ForegroundColor Yellow
    Write-Host "It can be installed using " -NoNewLine 
    Write-Host "'Install-Module -Name PureStorage.FlashArray.VMware'" -ForegroundColor Green
    Write-Host 
    exit
}

############################################################
# Check to see if we're connected to the Target FlashArray,#
# if not, prompt for Credentials to connect to it.         #
############################################################

If ($DefaultFlashArray) {
    Write-Host "Target FlashArray: $($DefaultFlashArray.Endpoint) "
    $ConnectFA = $False
} else {
    #connect to Target FlashArray
    try
    {
        $FaCredentials = Get-Credential -Message "Please enter the Target FlashArray Credentials for $($TargetFlashArray)"                            
        New-PfaConnection -EndPoint $TargetFlashArray -Credentials $FaCredentials -ErrorAction Stop -IgnoreCertificateError -DefaultArray
        $ConnectFA = $True
    }
    catch
    {
        write-host "Failed to connect to the Target FlashArray" -BackgroundColor Red
        write-host $Error
        write-host "Terminating Script" -BackgroundColor Red
        $ConnectFA = $False

        return
    }
}

############################################################
# Check to see if we're connected to the Target vCenter,   #
# if not, prompt for Credentials to connect to it.         #
############################################################

# Check to see if a current vCenter Server session is in place
If ($Global:DefaultVIServer.Name -eq $TargetVcenter) {
    Write-Host "Connected to " -NoNewline 
    Write-Host $Global:DefaultVIServer -ForegroundColor Green
} else {
    # If not connected to vCenter Server make a connection
    Write-Host "Not connected to vCenter Server" -ForegroundColor Red
    # Prompt for credentials using the native PowerShell Get-Credential cmdlet
    $VICredentials = Get-Credential -Message "Enter credentials for vCenter Server: $($TargetVcenter)" 
    try {
        # Attempt to connect to the vCenter Server 
        Connect-VIServer -Server $TargetVcenter -Credential $VICredentials -ErrorAction Stop | Out-Null
        Write-Host "Connected to $TargetVcenter" -ForegroundColor Green 
        # Note that we connected to vCenter so we can disconnect upon termination
        $ConnectTargetVc = $True
    }
    catch {
        # If we could not connect to vCenter report that and exit the script
        Write-Host "Failed to connect to $TargetVcenter" -BackgroundColor Red
        Write-Host $Error
        Write-Host "Terminating the script " -BackgroundColor Red
        # Note that we did not connect to vCenter Server
        $ConnectTargetVc = $False
        return
    }
}

# If $LocalSnapshot is True, then don't look for replicated snaps
If ($LocalSnapshot -eq $true) {
    $SourceVolume = $SourceVolumeName
} else {
    $SourceVolume = "*:"+$SourceVolumeName
}

# Get the Protection Group & Volumes 
$ProtectionGroup = New-PfaRestOperation -ResourceType pgroup -RestOperationType GET -Flasharray $DefaultFlashArray -SkipCertificateCheck | Where-Object {$_.volumes -Like $SourceVolume}

# If the number of snapshots isn't specified, return the latest snapshot, otherwise allow the choice of a snapshot to be selected
If ($SourceSnapCount -le "1") {
    # Get the $SourceSnapCount latest snapshots from the protection group
    $LatestSnap = New-PfaRestOperation -ResourceType volume -RestOperationType GET -Flasharray $DefaultFlashArray -SkipCertificateCheck -QueryFilter "?snap=true&pgrouplist=$($ProtectionGroup.name)" | Where-Object {$_.name -Like "*"+$SourceVolumeName} | Sort-Object Created -Descending | Select-Object -First 1
    # Get the name of the latest snapshot 
    $LatestSnapName = $LatestSnap.name
} else {
    # Get the latest snapshot from the protection group
    $LatestSnap = New-PfaRestOperation -ResourceType volume -RestOperationType GET -Flasharray $DefaultFlashArray -SkipCertificateCheck -QueryFilter "?snap=true&pgrouplist=$($ProtectionGroup.name)" | Where-Object {$_.name -Like "*"+$SourceVolumeName} | Sort-Object Created -Descending | Select-Object -First $SourceSnapCount

            # Retrieve the snaps & sort them by their created date

            $LatestSnaps = $LatestSnap | Sort-Object Created

            # If no clusters are found, exit the script
            if ($LatestSnaps.count -lt 1)
            {
                Write-Host "No snaps found. Terminating Script" -BackgroundColor Red
                exit
            }

            # Select the Snapsnot
            Write-Host "1 or more snaps were found. Please choose a snapshot:"
            Write-Host ""

            # Enumerate the cluster(s)
            1..$LatestSnaps.Length | Foreach-Object { 
                $SnapName = $LatestSnaps[$_-1].name.Split(".")[1]+"."+$LatestSnaps[$_-1].name.Split(".")[2]
                $SnapDate = $LatestSnaps[$_-1].created
                Write-Host $($_)"- Name: $($SnapName) - Created:$($SnapDate)"
            }

            # Wait until a valid snapshot is picked
            Do
            {
                Write-Host # empty line
                $Global:ans = (Read-Host 'Please select a snapshot') -as [int]
            
            } While ((-not $ans) -or (0 -gt $ans) -or ($LatestSnaps.Length+1 -lt $ans))

            # Assign the $LatestSnapshot variable to the Snapshot picked
            $LatestSnapShot = $LatestSnaps[($ans-1)]

            # Return the selected snapshot
            Write-Host "Selected snapshot is " -NoNewline 
            Write-Host $LatestSnaps[($ans-1)].name -ForegroundColor Green
            Write-Host ""
            # Set the Latest Snapshot Name
            $LatestSnapName = $LatestSnaps[($ans-1)].name    
}

# Get the suffix of the snapshot (will be appended to the datastore)
$Suffix = $LatestSnapName.split(".")[1]

# Create the new volume name (includes the suffix)
$NewVolumeName = $SourceVolumeName + "-" + $Suffix

# Create a new volume from the latest snapshot, overwrite if necessary
New-PfaRestOperation -ResourceType volume/$($NewVolumeName) -RestOperationType POST -Flasharray $DefaultFlashArray -SkipCertificateCheck -jsonBody "{`"source`":`"$($LatestSnapName)`",`"overwrite`":`"$true`"}"

# Pause for a few seconds for the snap to take place
Start-Sleep -Seconds 5

# Get the host group of the Target Cluster on the Target FlashArray
$TargetHostGroup = Get-PfaHostGroupfromVcCluster -Cluster (Get-Cluster -Name $TargetCluster) -Flasharray $DefaultFlashArray

# Attach the snapped volume to the Target vCenter Cluster
New-PfaRestOperation -ResourceType hgroup/$($TargetHostGroup.name)/volume/$($NewVolumeName) -RestOperationType POST -Flasharray $DefaultFlashArray -SkipCertificateCheck  

# Select 1 host in the Target vCenter Cluster
$VMHost = Get-Cluster -Name $TargetCluster | Get-VMhost | Select-Object -First 1

# Rescan the HBA's on the current host to both see the snapped volume (present as a snap) and put the datastores into an array variable
Get-VMHostStorage -RescanAllHba -RescanVmfs -VMHost $VMhost | Out-Null

# Put all datastores attached to the host in an array variable
$PreSnapDatastores = $VMhost | Get-Datastore

# Configure an esxcli instance so we can see snaps presented to the host
$EsxCli = Get-EsxCli -VMHost $VMhost -V2
# Return a snapshot list & put it in a variable
$Snaps = $esxcli.storage.vmfs.snapshot.list.invoke()

# if the snap volume count is >0 then proceed
if ($Snaps.Count -gt 0) {
    Foreach ($Snap in $Snaps) {
        # Mount the snapshot volume & resignature it
        $esxcli.storage.vmfs.snapshot.resignature.invoke(@{volumelabel=$($Snap.VolumeName)})
    }
} else {
    # Exit the script, as no snapshots were found
    Write-Host "No Snapshot volumes found" -ForegroundColor Red
    exit
}

# Rescan the HBAs to ensure that the datastore is visible and may be used
Get-VMHostStorage -RescanAllHba -RescanVmfs -VMHost $VMhost | Out-Null

# Pause for a few seconds
Start-Sleep -Seconds 5

# Get a list of all of the datastores on the host (including the new snapped datastore)
$PostSnapDatastores = $VMhost | Get-Datastore

# Compare the pre/post datastore array variables to gather the name of the newly added datastore
# This datastore will have a name like snap-32a052-old-volume-name
$SnappedDatastore = (Compare-Object -ReferenceObject $PreSnapDatastores -DifferenceObject $PostSnapDatastores).InputObject

# Query the FlashArray to get the Snapped datastore's volume name
$NewDatastoreVolume = Get-PfaVmfsVol -Datastore $SnappedDatastore -Flasharray $DefaultFlashArray

# Pause 
Start-Sleep -Seconds 5

# Retrieve the Target VM Folder Object
$VMFolder  = Get-Folder -Type VM -Name $TargetVmFolder

# Rename the datastore
Set-Datastore -Datastore $SnappedDatastore -Name $($NewDatastoreVolume.Name)

# Register any .vmx found on the datastore in vSphere
if ($RegisterVms -eq $true) {

    # Search for .VMX Files in datastore
    $ds = Get-Datastore -Name $NewDatastoreVolume.Name | %{Get-View $_.Id}
    $SearchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
    $SearchSpec.matchpattern = "*.vmx"
    $dsBrowser = Get-View $ds.browser
    $DatastorePath = "[" + $ds.Summary.Name + "]"
        
    # Find all .VMX file paths in Datastore variable and filters out .snapshot
    $SearchResults = $dsBrowser.SearchDatastoreSubFolders($DatastorePath,$SearchSpec) | Where-Object {$_.FolderPath -notmatch ".snapshot"} | %{$_.FolderPath + $_.File.Path} 

    # Register all .VMX files with vCenter
    foreach($SearchResult in $SearchResults) {
        New-VM -VMFilePath $SearchResult -VMHost $VMHost -Location $VMFolder -RunAsync -ErrorAction SilentlyContinue
    }
}

# If we had to connect to vCenter, disconnect
if ($ConnectTargetVc -eq $true) {
    # Disconnect from the Target vCenter Server and any others 
    Disconnect-VIserver -Server $TargetVcenter -Confirm:$false
}

# If we had to connect to FlashArray, disconnect
if ($ConnectFA -eq $true) {
    # Disconnect from the Target FlashArray
    Disconnect-PfaArray -Array $DefaultFlashArray
}
