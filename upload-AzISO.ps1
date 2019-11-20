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

# Install AzCopy & Login
cd $LocalFilePath
wget -O azcopy.tar.gz https://aka.ms/downloadazcopy-v10-linux
tar -xf azcopy.tar.gz
/azcopy_linux_amd64_10.3.2/azcopy login --tenant-id $tenant

# Verify Login
if( -not $(Get-AzContext) ) { return }

# vbox
cd /
wget https://download.virtualbox.org/virtualbox/6.0.14/VirtualBox-6.0.14-133895-Linux_amd64.run
chmod a+x VirtualBox-6.0.14-133895-Linux_amd64.run
./VirtualBox-6.0.14-133895-Linux_amd64.run
curl -O -J -L $ISOurl
vboxmanage convertfromraw $ISOurl $filename
# TODO Cleanup vbox


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

cd $LocalFilePath

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
# The solution to use AzCopy has the prerequisite that the account used must have the role "Blob Data Contributor" assigned. See https://github.com/Azure/azure-storage-azcopy/issues/77.


# FAIL #2 : Upload using AzCopy
# -----------------------------
# command(s):
# /azcopy_linux_amd64_10.3.2/azcopy copy $filename $containerSASURI
# error message:
#


# FAIL #3 : Upload using Add-AzVhd
# --------------------------------
# command(s):
# Add-AzVhd -ResourceGroupName $ResourceGroupName -Destination ${containerSASURI} -LocalFilePath $filename -Overwrite
#
# error message:
# Add-AzVhd: https://[put blob name here].blob.core.windows.net/[put container name here]?sv=2019-02-02&sr=c&sig=[your sig]&se=2019-11-20T09%3A14%3A18Z&sp=rw (Parameter'Destination')


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
# command(s):
# $urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${BlobName}"
# Add-AzVhd -ResourceGroupName $ResourceGroupName -Destination $urlOfUploadedVhd -LocalFilePath $filename -Overwrite
#
# error message:
#
# Detecting the empty data blocks completed.add-azvhd : Operation is not supported on this platform.
# At line:1 char:1
# + add-azvhd -resourcegroupname $resourcegroupname
# + ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# + CategoryInfo          : CloseError: (:) [Add-AzVhd], PlatformNotSupportedException
# + FullyQualifiedErrorId : Microsoft.Azure.Commands.Compute.StorageServices.AddAzureVhdCommand
# see https://github.com/Azure/azure-powershell/issues/10549

