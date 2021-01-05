# PowerCLI Script for retrieving iSCSI Path Status from ESXi Hosts
# @davidstamen
# https://davidstamen.com

$vcname = "vc.lab.local"
$vcuser = "administrator@vsphere.local"
$vcpass = "Password1!"
$clustername = "Cluster01"

$VC = Connect-VIServer $vcname -User $vcuser -Password $vcpass -WarningAction SilentlyContinue
$VMHosts = Get-Cluster $clustername -Server $VC | Get-VMHost  | Where-Object { $_.ConnectionState -eq "Connected" } | Sort-Object -Property Name 

$results= @()

foreach ($VMHost in $VMHosts) {
[ARRAY]$HBAs = $VMHost | Get-VMHostHba -Type "IScsi"

    foreach ($HBA in $HBAs) {
    $pathState = $HBA | Get-ScsiLun | Get-ScsiLunPath | Group-Object -Property state
    $pathStateActive = $pathState | Where-Object { $_.Name -eq "Active"}
    $pathStateDead = $pathState | Where-Object { $_.Name -eq "Dead"}
    $pathStateStandby = $pathState | Where-Object { $_.Name -eq "Standby"}
    $results += "{0},{1},{2},{3},{4},{5}" -f $VMHost.Name, $HBA.Device, $VMHost.Parent, [INT]$pathStateActive.Count, [INT]$pathStateDead.Count, [INT]$pathStateStandby.Count
    }

}
ConvertFrom-Csv -Header "VMHost","HBA","Cluster","Active","Dead","Standby" -InputObject $results | Format-Table -AutoSize
