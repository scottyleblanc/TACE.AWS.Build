
$orphans = Get-TaceOrphanedElasticIps

$orphans.Data | ForEach-Object {
    Write-Host "Orphaned Elastic IP: $($_.PublicIp) (Allocation ID: $($_.AllocationId))"
    Remove-TaceElasticIp -AllocationId $_.AllocationId -PublicIp $_.PublicIp
}
