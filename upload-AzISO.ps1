#
# Upload a .vhd'fied bootable ISO to Azure
#
# Prerequisites:
#    - VMware Photon OS 3.0
#    - Powershell + Azure Powershell ( + Azure CLI) release installed
#    - Run as root
#
# History
# 0.1  04.11.2019   dcasota  UNFINISHED! WORK IN PROGRESS!


# Location setting
$LocationName = "westus"

# Resourcegroup setting
$ResourceGroupName = "photonos-lab-rg"

# network setting
$NetworkName = "photonos-lab-network"

# Base Image
$StorageAccountName="vhdfiedbootableiso"
$ContainerName="disks"
$filename="isobootdisk.vhd"
$BlobName=$filename
$LocalFilePath="/tmp"

# Environment
tdnf update -y
tdnf install wget unzip bzip2 curl -y

# Input parameter
$tenant=Read-Host -Prompt "Enter your Azure tenant id"
$ISOurl=Read-Host -Prompt "Enter your ISO download url"
$ISOfilename= split-path $ISOurl -leaf


cd /root

# Install AzCopy & Login
wget -O azcopy.tar.gz https://aka.ms/downloadazcopy-v10-linux
tar -xf azcopy.tar.gz
./azcopy_linux_amd64_10.3.2/azcopy login --tenant-id $tenant

# Verify Login
if( -not $(Get-AzContext) ) { return }

Set-AzContext -Tenant $tenant

# install vbox
wget https://download.virtualbox.org/virtualbox/6.0.14/VirtualBox-6.0.14-133895-Linux_amd64.run
chmod a+x VirtualBox-6.0.14-133895-Linux_amd64.run
./VirtualBox-6.0.14-133895-Linux_amd64.run
# TODO
# There were problems setting up VirtualBox.  To re-start the set-up process, run
#   /sbin/vboxconfig
# as root.  If your system is using EFI Secure Boot you may need to sign the
# kernel modules (vboxdrv, vboxnetflt, vboxnetadp, vboxpci) before you can load
# them. Please see your Linux system's documentation for more information.
# 
# VirtualBox has been installed successfully.

cd $LocalFilePath

# convert
curl -O -J -L $ISOurl
vboxmanage convertfromraw $ISOfilename $filename
# TODO
# WARNING: The vboxdrv kernel module is not loaded. Either there is no module
#          available for the current kernel (4.19.82-1.ph3) or it failed to
#          load. Please recompile the kernel module and install it by
# 
#            sudo /sbin/vboxconfig
# 
#          You will not be able to start VMs until this problem is fixed.


# Prepare upload
$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (([string]::IsNullOrEmpty($storageaccount)))
{
    New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $LocationName -Kind Storage -SkuName Premium_LRS -ErrorAction SilentlyContinue
}
$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)

$destinationContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey[0].value

$containerSASURI = New-AzStorageContainerSASToken -Context $destinationContext -ExpiryTime(get-date).AddSeconds(86400) -FullUri -Name $ContainerName -Permission rw
# This is the containerSASURI
$containerSASURI

# FAIL #1 : Upload using Set-AzStorageBlobContent
# -----------------------------------------------
# command(s):
# New-AzStorageContainer -Name $containerName -Context $destinationContext -Permission blob
# Set-AzStorageBlobContent -File $filename -Container $containerName -Blob $BlobName -Context $destinationContext
#
# error message:
# (successfully completes!)
# However, afterwards when creating a VM, the error message shown is 'this is not a blob'. In reference to
# https://www.thomas-zuehlke.de/2019/08/creating-azure-vm-based-on-local-vhd-files/ this is expected as it is not a storage account of type "Pageblob".
# The solution is to use AzCopy, and AzCopy has the prerequisite that the account used must have the role "Blob Data Contributor" assigned. See https://github.com/Azure/azure-storage-azcopy/issues/77.


# FAIL #2 : Upload using AzCopy
# -----------------------------
# command(s):
/root/azcopy_linux_amd64_10.3.2/azcopy copy $filename $containerSASURI
# error message:
#
# INFO: Scanning...
# 
# Job 12ff670d-fecc-e247-5522-23b52a21a1ed has started
# Log file is located at: /root/.azcopy/12ff670d-fecc-e247-5522-23b52a21a1ed.log
# 
# 0.0 %, 0 Done, 0 Failed, 1 Pending, 0 Skipped, 1 Total,
# 
# 
# Job 12ff670d-fecc-e247-5522-23b52a21a1ed summary
# Elapsed Time (Minutes): 0.0333
# Total Number Of Transfers: 1
# Number of Transfers Completed: 0
# Number of Transfers Failed: 1
# Number of Transfers Skipped: 0
# TotalBytesTransferred: 0
# Final Job Status: Failed
#
# output in /root/.azcopy/12ff670d-fecc-e247-5522-23b52a21a1ed.log:
# 2019/11/20 21:41:52 ERR: [P#0-T#0] https://vhdfiedbootableiso.blob.core.windows.net/disks/isobootdisk.vhd?se=2019-11-21t21%3A41%3A50z&sig=-REDACTE
# D-&sp=rw&sr=c&sv=2019-02-02: 403: Delete (incomplete) Page Blob -403 This request is not authorized to perform this operation using this permissio
# n.. X-Ms-Request-Id:3ad1cbe4-f01c-000b-35eb-9f43e9000000



# FAIL #3 : Upload using Add-AzVhd
# --------------------------------
# command(s):
# Add-AzVhd -ResourceGroupName $ResourceGroupName -Destination ${containerSASURI} -LocalFilePath $filename -Overwrite
#
# error message:
# Add-AzVhd: https://[put blob name here].blob.core.windows.net/[put container name here]?sv=2019-02-02&sr=c&sig=[your sig]&se=2019-11-20T09%3A14%3A18Z&sp=rw (Parameter'Destination')
#
#
# FAIL #3b : Upload using Add-AzVhd
# ---------------------------------
# command(s):
# $urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${BlobName}"
# Add-AzVhd -ResourceGroupName $ResourceGroupName -Destination $urlOfUploadedVhd -LocalFilePath $filename -Overwrite
#
# error message on Pwsh6.2.3:
#
# Add-AzVhd : unsupported format
# At line:1 char:1
# + Add-AzVhd -ResourceGroupName $ResourceGroupName -Destination $urlOfUp ...
# + ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# + CategoryInfo          : CloseError: (:) [Add-AzVhd], VhdParsingException
# + FullyQualifiedErrorId : Microsoft.Azure.Commands.Compute.StorageServices.AddAzureVhdCommand
# 


# FAIL #4 : Upload using azure cli and add-azvhd
# ----------------------------------------------
# command(s):
# $result=az storage container exists --account-name $storageaccountname --name ${ContainerName} | convertfrom-json
# if ($result.exists -eq $false)
# {
#     az storage container create --name ${ContainerName} --public-access blob --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value
# }
# $result=az storage blob exists --account-key ($storageaccountkey[0]).value --account-name $StorageAccountName --container-name ${ContainerName} --name ${BlobName} | convertfrom-json
# if ($result.exists -eq $false)
# {
#     az storage blob upload --account-name $StorageAccountName `
#     --account-key ($storageaccountkey[0]).value `
#     --container-name ${ContainerName} `
#     --type page `
#     --file $filename `
#     --name ${BlobName}
# }
#
# # Result: completes successfully however throws an error afterwards when creating a VM from the vhd'fied bootable ISO.
#
# FAIL #4b : Upload using azure cli and add-azvhd (az login + connect-azaccount)
# ------------------------------------------------------------------------------
# command(s):
# $urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${BlobName}"
# Add-AzVhd -ResourceGroupName $ResourceGroupName -Destination $urlOfUploadedVhd -LocalFilePath $filename -Overwrite
#
# error message on Pwsh6.0:
#
# Detecting the empty data blocks completed.add-azvhd : Operation is not supported on this platform.
# At line:1 char:1
# + add-azvhd -resourcegroupname $resourcegroupname
# + ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# + CategoryInfo          : CloseError: (:) [Add-AzVhd], PlatformNotSupportedException
# + FullyQualifiedErrorId : Microsoft.Azure.Commands.Compute.StorageServices.AddAzureVhdCommand
# see https://github.com/Azure/azure-powershell/issues/10549
#

# TODO Cleanup vbox, downloaded ISO, etc.
rm -r /root/azcopy_linux_amd64_10.3.2
rm -r /root/azcopy.tar.gz
rm -r /root/VirtualBox-6.0.14-133895-Linux_amd64.run
rm $LocalFilePath/$filename
rm $LocalFilePath/$ISOfilename