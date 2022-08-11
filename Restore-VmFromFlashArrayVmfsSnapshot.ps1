##############################################################################################################################
# Restore a VM from a Snapshot on an alternate FlashArray & move it to another datastore                                     #
# Assuming that this is restoring in an alternate datacenter                                                                 #
# Powershell Core supported - Requires PowerCLI, PureStorage.FlashArray.VMware, & PureStoragePowerShellSDK (v1) modules.     #
#                                                                                                                            #
# Authored by   : Jase McCarty                                                                                               #
# Twitter       : @jasemccarty                                                                                               #
# Date Published: 23 AUG 2021                                                                                                #
#                                                                                                                            #
##############################################################################################################################

# Variables Section
# Source Variables
$SourceVcenter    = 'vc02.fsa.lab'                              # Source vCenter
$SourceFlashArray = 'sn1-m70-f06-33.puretec.purestorage.com'    # Source FlashArray
$SourceVM         = 'JVRO'

# Target Variables
$TargetVcenter    = 'vc03.fsa.lab'                             # Target vCenter
$TargetFlashArray = 'sn1-m70r2-f07-27.puretec.purestorage.com' # Target FlashArray
$TargetDatastore  = 'sn1-m70-f06-33-vc03-ds01'                 # Target Datastore to move VM to
$TargetCluster    = 'cluster-dr'                               # Target Cluster for snapped VM
$TargetNetwork    = 'mgmt-untagged'                            # Target Network for snapped VM
$TargetVmFolder   = 'Discovered virtual machine'               # Target VM Folder for snapped VM

###########################################################
# It should not be necessary to make any changes below    #
###########################################################

###########################################################
# Check for proper PowerShell modules installation        #
###########################################################

# Get the PowerCLI Version
$PowerCLIVersion = Get-Module -Name VMware.PowerCLI -ListAvailable | Select-Object -Property Version

# If the PowerCLI Version is not v10 or higher, recommend that the user install PowerCLI 10 or higher
If ($PowerCLIVersion.Version.Major -ge "12") {
    Write-Host "PowerCLI version 12 or higher present, " -NoNewLine
    Write-Host "proceeding" -ForegroundColor Green 
} else {
    Write-Host "PowerCLI version could not be determined or is less than version 10" -Foregroundcolor Red
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
# Check to see if we're connected to the Source FlashArray,#
# if not, prompt for Credentials to connect to it.         #
############################################################

If ($SourceArray) {
    Write-Host "Source FlashArray: $($SourceArray.Endpoint) "
    $ConnectSourceFA = $False
} else {
    #connect to Source FlashArray
    try
    {
        $FaCredentials = Get-Credential -Message "Please enter the Source FlashArray Credentials for $($SourceFlashArrayt)"
        $SourceArray = New-PfaConnection -EndPoint $SourceFlashArray -Credentials $FaCredentials -ErrorAction Stop -IgnoreCertificateError -NonDefaultArray
        $ConnectSourceFA = $True
    }
    catch
    {
        write-host "Failed to connect to the Source FlashArray" -BackgroundColor Red
        write-host $Error
        write-host "Terminating Script" -BackgroundColor Red
        $ConnectSourceFA = $False
        return
    }
}

############################################################
# Check to see if we're connected to the Target FlashArray,#
# if not, prompt for Credentials to connect to it.         #
############################################################

If ($TargetArray) {
    Write-Host "Target FlashArray: $($TargetArray.Endpoint) "
    $ConnectTargetFA = $False
} else {
    #connect to Target FlashArray
    try
    {
        if ($FaCredentials) {
            # If just logged into source array, opt to use the same credentials
            Do{ $SameFaCreds = Read-Host "Would you like to use the same credentials used for the Source Array on the Target Array? (Y/N)" }
            Until($SameFaCreds -eq "Y" -or $SameFaCreds -eq "N")

            if ($SameFaCreds -match "[nN]") {
                $FaCredentials = Get-Credential -Message "Please enter the Target FlashArray Credentials for $($TargetFlashArray)"                
            }
        } else {
            $FaCredentials = Get-Credential -Message "Please enter the Target FlashArray Credentials for $($TargetFlashArray)"                            
        }
        $TargetArray = New-PfaConnection -EndPoint $TargetFlashArray -Credentials $FaCredentials -ErrorAction Stop -IgnoreCertificateError -NonDefaultArray
        $ConnectTargetFA = $True
    }
    catch
    {
        write-host "Failed to connect to the Target FlashArray" -BackgroundColor Red
        write-host $Error
        write-host "Terminating Script" -BackgroundColor Red
        $ConnectTargetFA = $False
        return
    }
}

############################################################
# Check to see if we're connected to the Source vCenter,   #
# if not, prompt for Credentials to connect to it.         #
############################################################

# Check to see if a current vCenter Server session is in place
If ($Global:DefaultVIServer.Name -eq $SourceVcenter) {
    Write-Host "Connected to " -NoNewline 
    Write-Host $Global:DefaultVIServer -ForegroundColor Green
} else {
    # If not connected to vCenter Server make a connection
    Write-Host "Not connected to vCenter Server" -ForegroundColor Red
    # Prompt for credentials using the native PowerShell Get-Credential cmdlet
    $VICredentials = Get-Credential -Message "Enter credentials for vCenter Server: $($SourceVcenter)" 
    try {
        # Attempt to connect to the vCenter Server 
        Connect-VIServer -Server $SourceVcenter -Credential $VICredentials -ErrorAction Stop | Out-Null
        Write-Host "Connected to $SourceVcenter" -ForegroundColor Green 
        # Note that we connected to vCenter so we can disconnect upon termination
        $ConnectSourceVc = $True
    }
    catch {
        # If we could not connect to vCenter report that and exit the script
        Write-Host "Failed to connect to $SourceVcenter" -BackgroundColor Red
        Write-Host $Error
        Write-Host "Terminating the script " -BackgroundColor Red
        # Note that we did not connect to vCenter Server
        $ConnectSourceVc = $False
        return
    }
}

############################################################
# Proceed with getting the VM's information so it can be   #
# Made available on the target environment                 #
############################################################

# Get a Random Number so we can (mostly) guarantee a unique snapshot/VM name
$Random = Get-Random -Maximum 10000

# Get the VM, its .vmx file, Source Datastore, & Source FlashArray Volume
$VM = Get-VM -Name $SourceVM
$VMX = $VM.ExtensionData.Config.Files.VmPathName.Split("/")[1]
$SourceDatastore = $VM | Get-Datastore
$SourceVolume = Get-PfaVolfromvmfs -Datastore $SourceDatastore -FlashArray $SourceArray

# Create a snap name for the VM
$VMSnapName = $VM.Name + "-" + $Random

############################################################
# Protection Group Logic                                   #
# Get the source PG and target PG                          #
############################################################

# Get the Protection Group Associated with the Volume
$ProtectionGroup = New-PfaRestOperation -ResourceType pgroup -RestOperationType GET -Flasharray $SourceArray -SkipCertificateCheck | Where-Object {$_.volumes -contains $SourceVolume.Name}

# Determine if the SourceFlashArray is an IP or a FQDN
try { 
    $SourceName = [IPADDRESS] $SourceFlashArray
}
catch { 
    # If SourceFlashArray is a FQDN, use only the host (array) name
    $SourceName = $SourceFlashArray.Split(".")[0]
}

# Form the Snapshot source for the target array
$PGroupName = $SourceName + ":" + $ProtectionGroup.name

# Retrieve the ProtectionGroup on the Target Array
$TargetPG = New-PfaRestOperation -ResourceType pgroup/$($PGroupName) -RestOperationType GET -Flasharray $TargetArray -SkipCertificateCheck  

############################################################
# Get the latest snapshot of the source datastore          #
# and create a new volume from that snapshot.              #
############################################################

# Get the latest snapshot from the Source Array that contains the Source Volume
$LatestSnap = New-PfaRestOperation -ResourceType volume -RestOperationType GET -Flasharray $TargetArray -SkipCertificateCheck -QueryFilter "?snap=true&pgrouplist=$($PGroupName)" | Where-Object {$_.source.split(":")[1] -in $SourceVolume.name} | Sort-Object Created -Descending | Select-Object -First 1

# Create the new volume name
$NewVolumeName = $SourceVolume.name + "-snap-" + $Random

# Create a new volume from the latest snapshot, overwrite if necessary
New-PfaRestOperation -ResourceType volume/$($NewVolumeName) -RestOperationType POST -Flasharray $TargetArray -SkipCertificateCheck -jsonBody "{`"source`":`"$($LatestSnap.name)`",`"overwrite`":`"$true`"}"

# Pause for a few seconds for the snap to take place
Start-Sleep -Seconds 5

# Disconnect from the Source vCenter Server
Disconnect-VIserver $Global:DefaultVIServer -Confirm:$false

##################################################################
# Connected to the Target vCenter, prompt to use the same if the #
# Source was logged into,  or new Credentials to connect to it.  #
##################################################################

# Log into the Target vCenter Server
If ($VICredentials) {
    Do{ $SameViCreds = Read-Host "Would you like to use the same credentials used for the Source vCenter? (Y/N)" }
    Until($SameViCreds -eq "Y" -or $SameViCreds -eq "N")
    
    if ($SameViCreds -match "[nN]") {
        $VICredentials = Get-Credential -Message "Enter credentials for vCenter Server: $($TargetVcenter)"                
    } 
} else {
    $VICredentials = Get-Credential -Message "Enter credentials for vCenter Server: $($TargetVcenter)"            
}

    try {
        # Attempt to connect to the vCenter Server 
        Connect-VIServer -Server $TargetVcenter -Credential $VICredentials -ErrorAction Stop | Out-Null
        Write-Host "Connected to $TargetVcenter" -ForegroundColor Green 
        # Note that we connected to vCenter so we can disconnect upon termination
        $ConnectTargetVc = $True
    }
    catch {
        # If we could not connect to vCenter report that and exit the script
        Write-Host "Failed to connect to $SourceVcenter" -BackgroundColor Red
        Write-Host $Error
        Write-Host "Terminating the script " -BackgroundColor Red
        # Note that we did not connect to vCenter Server
        $ConnectTargetVc = $False
        return
    }

# To ensure the VM can be SvMotioned, force a network adapter, and remove any CD-ROMs
# Get the network object & handle network & CD-ROM later
$NetworkPortGroup = Get-VirtualPortGroup -Name $TargetNetwork

# Get the host group of the Target Cluster on the Target FlashArray
$TargetHostGroup = Get-PfaHostGroupfromVcCluster -Cluster (Get-Cluster -Name $TargetCluster) -Flasharray $TargetArray

# Attach the snapped volume to the Target vCenter Cluster
New-PfaRestOperation -ResourceType hgroup/$($TargetHostGroup.name)/volume/$($NewVolumeName) -RestOperationType POST -Flasharray $TargetArray -SkipCertificateCheck  

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
$NewDatastoreVolume = Get-PfaVmfsVol -Datastore $SnappedDatastore -Flasharray $TargetArray
 
# Pause 
Start-Sleep -Seconds 5

# Retrieve the Target VM Folder Object
$VMFolder  = Get-Folder -Type VM -Name $TargetVmFolder

# Search for .VMX Files in datastore variable
# Get the Datastore View so the filesystem can be searched
$ds = Get-Datastore -Name $SnappedDatastore.name | %{Get-View $_.Id}
# Create a search specification
$SearchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
$SearchSpec.matchpattern = "*"+ $VMX

# Get the datastore browswer view so the datastore path can be found
$dsBrowser = Get-View $ds.browser
$DatastorePath = "[" + $ds.Summary.Name + "]"
    
# Find the .VMX file path in Datastore variable and filters out .snapshot
$SearchResults = $dsBrowser.SearchDatastoreSubFolders($DatastorePath,$SearchSpec) | Where-Object {$_.FolderPath -notmatch ".snapshot"} | %{$_.FolderPath + $_.File.Path} 

# Get the Target Datastore, where we'll Storage vMotion the VM to.
$TargetDS = Get-Datastore -Name $TargetDatastore

# Register the .VMX file with vCenter
$SearchResults | Foreach-Object {
    # Register the snappshotted VM
    $NewVM = New-VM -VMFilePath $_ -VMHost $VMHost -Location $VMFolder -Name $VMSnapName -RunAsync -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 10
    # Get any VM's on the snapshotted datastore
    $NewVM = Get-Datastore -Name $SnappedDatastore | Get-VM

    Write-Host $NewVM

    Write-Host $SnappedDatastore

    Start-Sleep -Seconds 2

    Write-Host "starting loop"
    # Move each VM registered on the snappshotted datastore to the Target Datastore
    $NewVM | Foreach-Object {
        Write-Host "Remove any attached CD-ROM"
        # Remove any CD-ROM drives attached
        $_ | Get-CDDrive | Set-CDDrive -NoMedia -Confirm:$false | Out-Null

        Write-Host "Updating Network"
        # Attach a specific network - Often networks are disconnected upon registration if previously connected to a VDS
        $_ | Get-NetworkAdapter | Set-NetworkAdapter -Portgroup $NetworkPortGroup -Confirm:$false | Out-Null 

        # Storage vMotion the VM to the new datastore
        $_ | Move-VM -Datastore $TargetDS
        # Wait until the VM has been moved to the target datastore
        Do {
            $VMItem = Get-Datastore  -Name $TargetDS | Get-VM -Name $_ -ErrorAction SilentlyContinue
        } While (-not $VMItem)

        Start-Sleep -Seconds 5
    }
}

# Remove the snapshotted datastore
Remove-Datastore -Datastore $SnappedDatastore -VMHost (Get-VMhost) -Confirm:$false -Verbose

# Disconnect the Host Group from the snapshotted volume so the snap volume can be deleted 
New-PfaRestOperation -ResourceType hgroup/$($TargetHostGroup.name)/volume/$($NewVolumeName) -RestOperationType DELETE -Flasharray $TargetArray -SkipCertificateCheck  

# Delete the snapshotted volume
New-PfaRestOperation -ResourceType volume/$($NewVolumeName) -RestOperationType DELETE -Flasharray $TargetArray -SkipCertificateCheck # -jsonBody "{`"eradicate`":`"$true`"}"

# Disconnect from the Target vCenter Server and any others 
Disconnect-VIserver * -Confirm:$false

# Disconnect from the Source & Target FlashArray
Disconnect-PfaArray -Array $SourceArray
Disconnect-PfaArray -Array $TargetArray
