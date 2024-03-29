﻿# Source https://faultbucket.ca/2020/12/migrate-azure-managed-disk-between-regions/
# Needs AzCopy on the same path
# AzCopy Download https://docs.microsoft.com/en-us/azure/storage/common/storage-use-azcopy-v10#download-and-install-azcopy

# Name of the Managed Disk you are starting with
$sourceDiskName = "ph01_disk1_082be397340d421f8c660ff1a04d8380"
# Name of the resource group the source disk resides in
$sourceRG = "NVidia"
# Name you want the destination disk to have
$targetDiskName = "ph01_disk1_082be397340d421f8c660ff1a04d8380_copied"
# Name of the resource group to create the destination disk in
$targetRG = "NVidia"
# Azure region the target disk will be in
$targetLocate = "EastUS2"

# Gather properties of the source disk
$sourceDisk = Get-AzDisk -ResourceGroupName $sourceRG -DiskName $sourceDiskName

# Create the target disk config, adding the sizeInBytes with the 512 offset, and the -Upload flag
# If this is an OS disk, add this property: -OsType $sourceDisk.OsType
$targetDiskconfig = New-AzDiskConfig -SkuName 'Standard_LRS'-OsType $sourceDisk.OsType -UploadSizeInBytes $($sourceDisk.DiskSizeBytes+512) -Location $targetLocate -CreateOption 'Upload'

# Create the target disk (empty)
$targetDisk = New-AzDisk -ResourceGroupName $targetRG -DiskName $targetDiskName -Disk $targetDiskconfig

# Get a SAS token for the source disk, so that AzCopy can read it
$sourceDiskSas = Grant-AzDiskAccess -ResourceGroupName $sourceRG -DiskName $sourceDiskName -DurationInSecond 86400 -Access 'Read'

# Get a SAS token for the target disk, so that AzCopy can write to it
$targetDiskSas = Grant-AzDiskAccess -ResourceGroupName $targetRG -DiskName $targetDiskName -DurationInSecond 86400 -Access 'Write'

# Begin the copy!
.\azcopy copy $sourceDiskSas.AccessSAS $targetDiskSas.AccessSAS --blob-type PageBlob

# Revoke the SAS so that the disk can be used by a VM
Revoke-AzDiskAccess -ResourceGroupName $sourceRG -DiskName $sourceDiskName

# Revoke the SAS so that the disk can be used by a VM
Revoke-AzDiskAccess -ResourceGroupName $targetRG -DiskName $targetDiskName