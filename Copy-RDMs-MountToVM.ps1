<#==========================================================================
Script Name: Copy-RDMs-MountToVM.ps1
Created on: 12/08/2021
Created by: Jase McCarty
Github: http://www.github.com/jasemccarty
Twitter: @jasemccarty
===========================================================================
.DESCRIPTION
Copy RDMs and mount them to a new VM
Powershell Core supported - Requires PowerCLI, PureStorage.FlashArray.VMware, & PureStoragePowerShellSDK (v1) modules.
.SYNTAX
Copy-RDMs-MountToVM.ps1 -vCenter <VCENTER> -FlashArray <FlashArray> -VM <VM> -SourceVolumes <SourceRDMs>
.EXAMPLE
Copy-RDMs-MountToVM.ps1 -vCenter vc02.fsa.lab -FlashArray sn1-m70-f06-33.puretec.purestorage.com -VM SQLVM -SourceVolumes 'RDMD','RDME','RDMF'
#>

# Set our Parameters
[CmdletBinding()]Param(
  [Parameter(Mandatory=  $False)][string]$Vcenter,
  [Parameter(Mandatory = $False)][String]$FlashArray,
  [Parameter(Mandatory = $False)][String]$VM,
  [Parameter(Mandatory = $False)][Array]$SourceVolumes
)

# Variables Section
# Target Variables - Replace any of these as defaults if parameters are not passed
if (-Not $Vcenter)       { $Vcenter       = 'vc02.fsa.lab' }                              # vCenter
if (-Not $FlashArray)    { $FlashArray    = 'sn1-m70-f06-33.puretec.purestorage.com' }    # FlashArray
if (-Not $VM)            { $VM            = 'SQLVM' }                                     # VM
if (-Not $SourceVolumes) { $sourcevolumes = @('RDMD','RDME','RDMF') }                     # Source Volumes

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

###################################################################################################
# Check to see if we're connected to the vCenter, if not, prompt for Credentials to connect to it.#
###################################################################################################

# Check to see if a current vCenter Server session is in place
If ($Global:DefaultVIServer.Name -eq $Vcenter) {
    Write-Host "Connected to " -NoNewline 
    Write-Host $Global:DefaultVIServer -ForegroundColor Green
} else {
    # If not connected to vCenter Server make a connection
    Write-Host "Not connected to vCenter Server" -ForegroundColor Red
    # Prompt for credentials using the native PowerShell Get-Credential cmdlet
    $VICredentials = Get-Credential -Message "Enter credentials for vCenter Server: $($Vcenter)" 
    try {
        # Attempt to connect to the vCenter Server 
        Connect-VIServer -Server $Vcenter -Credential $VICredentials -ErrorAction Stop | Out-Null
        Write-Host "Connected to $Vcenter" -ForegroundColor Green 
        # Note that we connected to vCenter so we can disconnect upon termination
        $ConnectVc = $True
    }
    catch {
        # If we could not connect to vCenter report that and exit the script
        Write-Host "Failed to connect to $Vcenter" -BackgroundColor Red
        Write-Host $Error
        Write-Host "Terminating the script " -BackgroundColor Red
        # Note that we did not connect to vCenter Server
        $ConnectVc = $False
        exit
        return
    }
}

#############################################################################################################
# Check to see if we're connected to the Target FlashArray, if not, prompt for Credentials to connect to it.#
#############################################################################################################

If ($DefaultFlashArray.EndPoint -eq $FlashArray) {
    # Connect to specified FlashArray
    $TargetFlashArray = $DefaultFlashArray
} else {
    try {
    $FaCredentials = Get-Credential -Message "Please enter the FlashArray Credentials for $($FlashArray)"                            
    $TargetFlashArray = New-PfaConnection -EndPoint $FlashArray -Credentials $FaCredentials -ErrorAction Stop -IgnoreCertificateError -DefaultArray
    $ConnectFA = $True
    }
    catch {
    write-host "Failed to connect to the FlashArray" -BackgroundColor Red
    write-host $Error
    write-host "Terminating Script" -BackgroundColor Red
    $ConnectFA = $False
    exit
    return
    }
}
# Bulk of operations start here now that the PowerShell Modules have been confirmed loaded & we've connected to vCenter & FlashArray

# Informational
Write-Host "Performing prep work"
Write-Host "*********************************************************"
Write-Host

# Denote & Get the VM object and put it in $WorkingVM
Write-Host "Retrieving VM: " -NoNewline
Write-Host $VM -ForegroundColor Green
$WorkingVM = Get-VM -Name $VM

# Denote & Get the current datastore the VM is on so the RDM pointers will be placed in the same location
Write-Host "Getting the current datastore for $($VM) to ensure the RDM pointers are place on the same datastore"
$Datastore = $WorkingVM | Get-Datastore

# Denote & Get a random number between 00000-99999 to ensure we create unique volumes
Write-Host "Generating a random number to ensure unique volume names"
$Random = Get-Random -Maximum 99999

# Informational
Write-Host "*********************************************************"
Write-Host

# Loop through each of the Source RDM volumes and create a new RDM that corresponds with each
Foreach ($SourceVolume in $SourceVolumes) {
    # Denote the current RDM we're working with
    Write-Host "Retrieving Volume $($SourceVolume) " -NoNewLine

    # Retrieve the current RDM Volume Details
    $CurrentVolume = New-PfaRestOperation -ResourceType volume/$($SourceVolume) -RestOperationType Get -Flasharray $TargetFlashArray -SkipCertificateCheck

    # Create the new volume based on the naming RDM-VMNAME-SOURCERDMNAME-RANDOM
    $NewVolumeName = "RDM-$($WorkingVM)-$($CurrentVolume.Name)-$($Random)"

    # Retrieve the current RDM volume size so we can overwrite appropriately (Source & New volumes must be the same size)
    $CurrentVolumeSize = $CurrentVolume.size/1GB

    # Denote the Current RDM volume we're working with
    Write-Host "Current Volume: $($CurrentVolume.name)" -ForegroundColor Yellow
    Write-Host

    # Denote that we're creating a new EMPTY RDM and attaching it to the VM
    Write-Host "Creating RDM Volume $($NewVolumeName) that is the same capacity ($($CurrentVolumeSize) GB) as $($CurrentVolume.Name) and attaching it to $($WorkingVM)"

    # Create the new EMPTY RDM that is the same size as the source RDM
    New-PfaRdm -Flasharray $TargetFlashArray -VM $WorkingVM -Datastore $Datastore -SizeinGB $CurrentVolumeSize -Volname $NewVolumeName | Out-Null

    # Denote we're overwriting the newly created EMPTY RDM with the contents of the Source RDM
    Write-Host "Overwriting $($NewVolumeName) with the contents of $($CurrentVolume.Name)" -ForegroundColor Yellow

    # Overwrite the newly created EMPTY RDM with the contents of the source RDM
    New-PfaRestOperation -ResourceType volume/$($NewVolumeName) -RestOperationType POST -Flasharray $TargetFlashArray -SkipCertificateCheck -jsonBody "{`"overwrite`":true,`"source`":`"$($CurrentVolume.Name)`"}" | Out-Null

    # Informational
    Write-Host 
}

# Informational
Write-Host "*********************************************************"
Write-Host "Complete" -ForegroundColor Green

# Disconnect From FlashArray if we had to log into it
If ($ConnectFA -eq $true) {
    Disconnect-PfaArray -Array $TargetFlashArray
    # Informational
    Write-Host "*********************************************************"
    Write-Host "Disconnecting from $($FlashArray)"
}

# Disconnect from vCenter if we had to log into it
If ($ConnectVc -eq $true) {
    Disconnect-VIserver -Server $Vcenter -Confirm:$False
    # Informational
    Write-Host "*********************************************************"
    Write-Host "Disconnecting from $($Vcenter)"
}
