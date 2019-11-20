#
# Upload ESXi on Azure
#

#
# History
# 0.1  04.11.2019   dcasota  UNFINISHED! WORK IN PROGRESS!

$ScriptPath=$PSScriptRoot



# Location setting
$LocationName = "westus"

# Resourcegroup setting
$ResourceGroupName = "photonos-lab-rg"

# network setting
$NetworkName = "photonos-lab-network"

# virtual network and subnets setting
$VnetAddressPrefix = "192.168.0.0/16"
$ServerSubnetAddressPrefix = "192.168.1.0/24"

# Base Image
$StorageAccountName="esxi67u3"
$ContainerName="disks"
$BlobName="mydisk.vhd"
$LocalFilePath="./${BlobName}"



# Create az login object. You get a pop-up prompting you to enter the credentials.
$tenant=Read-Host -Prompt "Enter your tenant id"
$subscriptionid=Read-Host -Prompt "Enter your subscription id"
Connect-AzAccount -tenant $tenant -subscriptionid $subscriptionid
# Verify Login
if( -not $(Get-AzContext) ) { return }

# Prepare upload
$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (([string]::IsNullOrEmpty($storageaccount)))
{
    New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $LocationName -Kind Storage -SkuName Standard_LRS -ErrorAction SilentlyContinue
}
$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)


# New-AzStorageContainer -Name $containerName -Context $destinationContext -Permission blob
#Set-AzStorageBlobContent -File $LocalFilePath -Container $containerName -Blob $BlobName -Context $destinationContext
# fails afterwards when creating VM with this is not a blob

$containerSASURI = New-AzStorageContainerSASToken -Context $storageaccount.context -ExpiryTime(get-date).AddSeconds(3600) -FullUri -Name $ContainerName -Permission rw
wget -O azcopy.tar.gz https://aka.ms/downloadazcopy-v10-linux
tar -xf azcopy.tar.gz
# ./azcopy_linux_amd64_10.3.2/azcopy login --tenant-id "here"
./azcopy_linux_amd64_10.3.2/azcopy copy $LocalFilePath $containerSASURI

# FAIL1
# Set AzStorageContext
# $destinationContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey[0].value
# Generate SAS URI
# $containerSASURI = New-AzStorageContainerSASToken -Context $destinationContext -ExpiryTime(get-date).AddSeconds(3600) -FullUri -Name $ContainerName -Permission rw
# Add-AzVhd -ResourceGroupName $ResourceGroupName -Destination ${containerSASURI} -LocalFilePath mydisk.vhd -Overwrite
# Error Add-AzVhd: https://esxi67u3.blob.core.windows.net/disks?sv=2019-02-02&sr=c&sig=bZeB7t%2Bn%2FqUr%2BwDP%2BTMcMZfVBnFkA%2FAWsuqTFaDf0a0%3D&se=2019-11-20T09%3A14%3A18Z&sp=rw (Parameter'Destination')

# FAIL2
# Upload File using AzCopy
# $containerSASURI = New-AzStorageContainerSASToken -Context $destinationContext -ExpiryTime(get-date).AddSeconds(3600) -FullUri -Name $ContainerName -Permission rw
# azcopy copy $LocalFilePath $containerSASURI –recursive

# FAIL3
# az login
# $ctx = $storageAccount.Context
# New-AzStorageContainer -Name $containerName -Context $ctx -Permission blob
# Set-AzStorageBlobContent -File $LocalFilePath `
#  -Container $containerName `
#  -Blob $BlobName `
#   -Context $ctx

# $result=az storage container exists --account-name $storageaccountname --name ${ContainerName} | convertfrom-json
# if ($result.exists -eq $false)
# {
#     az storage container create --name ${ContainerName} --public-access blob --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value
# }

#Upload
# $urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${BlobName}"

# cd ..
# Add-AzVhd -ResourceGroupName $ResourceGroupName -Destination $urlOfUploadedVhd -LocalFilePath mydisk.vhd -Overwrite
# Detecting the empty data blocks completed.add-azvhd : Operation is not supported on this platform.
# At line:1 char:1
# + add-azvhd -resourcegroupname $resourcegroupname
# + ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# + CategoryInfo          : CloseError: (:) [Add-AzVhd], PlatformNotSupportedException
# + FullyQualifiedErrorId : Microsoft.Azure.Commands.Compute.StorageServices.AddAzureVhdCommand
# see https://github.com/Azure/azure-powershell/issues/10549

# $result=az storage blob exists --account-key ($storageaccountkey[0]).value --account-name $StorageAccountName --container-name ${ContainerName} --name ${BlobName} | convertfrom-json
# if ($result.exists -eq $false)
# {
#     az storage blob upload --account-name $StorageAccountName `
#     --account-key ($storageaccountkey[0]).value `
#     --container-name ${ContainerName} `
#     --type page `
#     --file $LocalFilePath `
#     --name ${BlobName}
# }
