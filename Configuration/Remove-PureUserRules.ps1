<#==========================================================================
Script Name: Remove-PureUserRules.ps1
Created on: 12/20/2021
Updated on:  2/08/2021
Created by: Jase McCarty
Github: http://www.github.com/jasemccarty
Twitter: @jasemccarty
Website: http://www.jasemccarty.com
===========================================================================
#>
# Get the PowerCLI Version
$PowerCLIVersion = Get-Module -Name VMware.PowerCLI -ListAvailable | Select-Object -Property Version

# If the PowerCLI Version is not v12 or higher, recommend that the user install PowerCLI 12 or higher
If ($PowerCLIVersion.Version.Major -ge "12") {
    Write-Host "PowerCLI version 12 or higher present, " -NoNewLine
    Write-Host "proceeding" -ForegroundColor Green 
} else {
    Write-Host "PowerCLI version could not be determined or is less than version 12" -Foregroundcolor Red
    Write-Host "Please install PowerCLI 12 or higher and rerun this script" -Foregroundcolor Yellow
    Write-Host " "
    exit
}
    
############################################################################################################
# Function to remove User Rules associated with Pre-vSphere 6.0EP5/6.5U1 installations                     #
############################################################################################################
Function Remove-PfaVmHostUserRule
{
    <#
    .SYNOPSIS
        Remove any User Rules configured for Pure Storage FlashArray
    .DESCRIPTION
        Enumerate any hosts passed and remove any User Rules configured for Pure Storage FlashArray
    .INPUTS
        (Required) A vSphere Host or Hosts Object returned from the Get-VMhost PowerCLI cmdlet
    .OUTPUTS
        Host, Number of User Rules Found, & if they are removed or not.
    .EXAMPLE
        PS C:\ Remove-VmHostUserRule -EsxiHost (Get-VMhost -Name "esxihost.fqdn") 
        
        Returns the Host info & recommendations for ESXi Host named 'esxihost.fqdn'
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(ValueFromPipeline,Mandatory)]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl[]]$EsxiHost
    )

   BEGIN
    {}
    PROCESS
    {

        # Loop through the EsxiHosts passed
        $EsxiHost | Foreach-Object {

            # Create our EsxCli context for the current host
            $EsxCli = Get-EsxCli -VMHost $_ -V2

            Write-Host "Current VMhost is " -NoNewLine
            Write-Host "$($_): " -ForegroundColor Green -NoNewline

            # Retrieve any User storage Rules for Pure Storage
            Write-Host "Retrieving User Rules" -NoNewline
            $SatpUserRules = $esxcli.storage.nmp.satp.rule.list.Invoke()| Where-Object {($_.RuleGroup -eq "user") -and ({$_.Model -Like "FlashArray"})}

            # IF we have 1 or more rules, 
            if ($SatpUserRules.Count -ge "1") {
                Write-Host "Found " -NoNewLine 
                Write-Host "$($SatpUserRules.Count) " -ForegroundColor Yellow -NoNewline
                Write-Host "user rules. " -NoNewLine

                # Loop through each User rule and remove it.
                $SatpUserRules | Foreach-Object {

                    # Create an object to assign our arguments to
                    $SatpArgs = $esxcli.storage.nmp.satp.rule.remove.CreateArgs()

                    # Populate the argument object with the current User rule's properties
                    $SatpArgs.model       = $_.Model
                    $SatpArgs.pspoption   = $_.PSPOptions
                    $SatpArgs.vendor      = $_.Vendor
                    $SatpArgs.description = $_.Description
                    $SatpArgs.psp         = $_.DefaultPSP
                    $SatpArgs.satp        = $_.Name
                    
                    # Remove the User rule
                    Write-Host "Removing the current User rule for Pure Storage"
                    $esxcli.storage.nmp.satp.rule.remove.invoke($SatpArgs)    
                }
            } else {
                Write-Host "No User rules were found on " -NoNewLine 
                Write-Host "$($_)" -ForegroundColor Green
            }
        }
    }
    END
    {}
} #END Function Remove-PfaVmHostUserRule

$VMhosts = Get-VMhost | Sort-Object Name 

Remove-PfaVmHostUserRule -EsxiHost $VMhosts
