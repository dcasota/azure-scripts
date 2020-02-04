#
# Actually there is no VMware Photon OS offering on the Azure marketplace. The script creates an Azure Generation V2 image of VMware Photon OS.
#
# To make us of VMware Photon OS on Azure, the script first creates a temporary Windows VM.
# Inside that Windows VM the VMware Photon OS bits for Azure are downloaded from the VMware download location,
# the extracted VMware Photon OS .vhd is uploaded as Azure page blob and after the Generation V2 image has been created, the Windows VM is deleted.
#
# For the .vhd file upload as Azure page blob a sub script "https://raw.githubusercontent.com/dcasota/azure-scripts/master/Upload-PhotonVhd-as-Blob.ps1" is used.
#
# For study purposes the temporary VM created is Microsoft Windows Server 2019 on a Hyper-V Generation V2 virtual hardware.
# 
#
# History
# 0.1   26.01.2020   dcasota  UNFINISHED! WORK IN PROGRESS!
#
# related learn weblinks
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/generation-2
#
# Prerequisites:
#    - Microsoft Powershell, Microsoft Azure Powershell
#    - Azure account


[CmdletBinding()]
param(
[string]$SoftwareToProcess="http://dl.bintray.com/vmware/photon/3.0/Rev2/azure/photon-azure-3.0-9355405.vhd.tar.gz",
[string]$LocationName = "switzerlandnorth",
[string]$ResourceGroupName = "photonos-lab-rg",
[string]$StorageAccountName="photonoslab",
[string]$ContainerName="disks",
[string]$BlobName=($(split-path -path $SoftwareToProcess -Leaf) -split ".tar.gz")[0],
[string]$ImageName=($(split-path -path $SoftwareToProcess -Leaf) -split ".vhd.tar.gz")[0]
)


# Location setting


# Resourcegroup setting


# Storage account setting




$DiskName="PhotonOS"



# settings of the temporary VM
# network setting
$NetworkName = "w2k19network"
# virtual network and subnets setting
$SubnetAddressPrefix = "192.168.1.0/24"
$VnetAddressPrefix = "192.168.0.0/16"
# VM setting
$VMSize = "Standard_E4s_v3" # offering includes a d: drive with 60GB non-persistent capacity
$VMSize_TempPath="d:" # on this drive $SoftwareToProcess is processed
$ComputerName = "w2k19"
$VMName = $ComputerName
$NICName = $ComputerName + "nic"
$VMLocalAdminUser = "LocalAdminUser"
$VMLocalAdminPwd="Secure2020123!" #12-123 chars
$PublicIPDNSName="mypublicdns$(Get-Random)"
$nsgName = "myNetworkSecurityGroup"
$publisherName = "MicrosoftWindowsServer"
$offerName = "WindowsServer"
$skuName = "2019-datacenter-with-containers-smalldisk-g2"
$marketplacetermsname= $skuName
# Get-AzVMImage -Location westus2 -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2019-datacenter-with-containers-smalldisk-g2
$productversion = "17763.973.2001110547"

# check Azure CLI
az help 1>$null 2>$null
if ($lastexitcode -ne 0)
{
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
}

# check Azure Powershell
if (([string]::IsNullOrEmpty((get-module -name Az* -listavailable)))) {install-module Az -force -ErrorAction SilentlyContinue}

# Verify Login
$azcontext=Get-AzContext
if( -not $($azcontext) )
{
	# Azure login
	[System.Management.Automation.Credential()]$cred = Get-credential -message 'Enter a username and password for the Azure login.'
	connect-Azaccount -Credential $cred
}

#Set the context to the subscription Id where Managed Disk exists and where VM will be created
$subscriptionId=($azcontext).Subscription.Id
# set subscription
az account set --subscription $subscriptionId

# Verify VM doesn't exist
[Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($VM,$null)))
{

	# create lab resource group if it does not exist
	$result = get-azresourcegroup -name $ResourceGroupName -Location $LocationName -ErrorAction SilentlyContinue
	if ( -not $($result))
	{
		New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName
	}

	# storageaccount
	$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
	if ( -not $($storageaccount))
	{
		$storageaccount=New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $LocationName -Kind Storage -SkuName Standard_LRS -ErrorAction SilentlyContinue
		if ( -not $($storageaccount)) {break}
	}
	$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)


	$result=az storage container exists --account-name $storageaccountname --name ${ContainerName} | convertfrom-json
	if ($result.exists -eq $false)
	{
		az storage container create --name ${ContainerName} --public-access blob --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value
	}

	# networksecurityruleconfig
	$nsg=get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
	if ( -not $($nsg))
	{
		$rdpRule1 = New-AzNetworkSecurityRuleConfig -Name myRdpRule -Description "Allow RDP" `
		-Access Allow -Protocol Tcp -Direction Inbound -Priority 110 `
		-SourceAddressPrefix Internet -SourcePortRange * `
		-DestinationAddressPrefix * -DestinationPortRange 3389
		$rdpRule2 = New-AzNetworkSecurityRuleConfig -Name mySSHRule -Description "Allow SSH" `
		-Access Allow -Protocol Tcp -Direction Inbound -Priority 100 `
		-SourceAddressPrefix Internet -SourcePortRange * `
		-DestinationAddressPrefix * -DestinationPortRange 22
		$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $LocationName -SecurityRules $rdpRule1,$rdpRule2
	}

	# set network if not already set
	$vnet = get-azvirtualnetwork -name $networkname -ResourceGroupName $resourcegroupname -ErrorAction SilentlyContinue
	if ( -not $($vnet))
	{
		$ServerSubnet  = New-AzVirtualNetworkSubnetConfig -Name frontendSubnet  -AddressPrefix $SubnetAddressPrefix -NetworkSecurityGroup $nsg
		$vnet = New-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -Location $LocationName -AddressPrefix $VnetAddressPrefix -Subnet $ServerSubnet
		$vnet | Set-AzVirtualNetwork
	}


	# create vm
	# -----------

	# VM local admin setting
	$VMLocalAdminSecurePassword = ConvertTo-SecureString $VMLocalAdminPwd -AsPlainText -Force
	$LocalAdminUserCredential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword)

	# Create a public IP address
	$nic=get-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
	if ( -not $($nic))
	{
		$pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $LocationName -Name $PublicIPDNSName -AllocationMethod Static -IdleTimeoutInMinutes 4
		# Create a virtual network card and associate with public IP address and NSG
		$nic = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName `
			-SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id
	}

	# Create a virtual machine configuration
	$vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize | `
	Add-AzVMNetworkInterface -Id $nic.Id

	$vmimage= get-azvmimage -Location $LocationName -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $productversion
	if (-not ([Object]::ReferenceEquals($vmimage,$null)))
	{
		if (-not ([Object]::ReferenceEquals($vmimage.PurchasePlan,$null)))
		{
			$agreementTerms=Get-AzMarketplaceterms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
			Set-AzMarketplaceTerms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name -Terms $agreementTerms -Accept
			$agreementTerms=Get-AzMarketplaceterms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
			Set-AzMarketplaceTerms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name -Terms $agreementTerms -Accept
			$vmConfig = Set-AzVMPlan -VM $vmConfig -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
		}

		$vmConfig = Set-AzVMOperatingSystem -Windows -VM $vmConfig -ComputerName $ComputerName -Credential $LocalAdminUserCredential | `
		Set-AzVMSourceImage -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $productversion

		# Create the VM
		$VirtualMachine = New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $vmConfig
	}

	$objVM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -status -ErrorAction SilentlyContinue
	if (-not ([Object]::ReferenceEquals($objVM,$null)))
	{
		# enable boot diagnostics for serial console option
		az vm boot-diagnostics enable --name $vmName --resource-group $ResourceGroupName --storage "https://${StorageAccountName}.blob.core.windows.net"

		$return=Set-AzVMCustomScriptExtension -ResourceGroupName $ResourceGroupName -Location $LocationName `
			-VMName $vmName `
			-Name "getPhotonVhdWindows" `
			-FileUri "https://raw.githubusercontent.com/dcasota/azure-scripts/master/Upload-PhotonVhd-as-Blob.ps1" `
			-Run "Upload-PhotonVhd-as-Blob.ps1" -argument "-Uri $SoftwareToProcess -tmppath $VMSize_TempPath -username $($cred.getnetworkcredential().username) -password $($cred.getnetworkcredential().Password) -tenant $((get-azcontext).tenant.id) -ResourceGroupName $ResourceGroupName -LocationName $LocationName -StorageAccountName $StorageAccountName -ContainerName $ContainerName"
		
		echo $return
		pause
	}
}


$Image=Get-AzImage -ResourceGroupName $resourceGroupName -ImageName $ImageName
if (-not $($Image))
{
	$Disk = Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $DiskName
	if (-not $($Image))
	{
		$urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${BlobName}"
		$storageAccountId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"
		$diskConfig = New-AzDiskConfig -AccountType 'Standard_LRS' -Location $LocationName -HyperVGeneration "V2" -CreateOption Import -StorageAccountId $storageAccountId -SourceUri $urlOfUploadedVhd
		New-AzDisk -Disk $diskConfig -ResourceGroupName $resourceGroupName -DiskName $DiskName		
	}

    $Disk=Get-AzDisk -ResourceGroupName $resourceGroupName -name $DiskName	
    $imageconfig=new-azimageconfig -location $LocationName -HyperVGeneration "V2"
    $imageConfig = Set-AzImageOsDisk -Image $imageConfig -OsState Generalized -OsType Linux -ManagedDiskId $Disk.ID
    new-azimage -ImageName $ImageName -ResourceGroupName $ResourceGroupName -image $imageconfig
}


$Image=Get-AzImage -ResourceGroupName $resourceGroupName -ImageName $ImageName
if (-not ([Object]::ReferenceEquals($Image$null)))
{
	# Delete Disk and VM
	Remove-AzDisk -ResourceGroupName $resourceGroupName -DiskName $DiskName -Force
	Remove-AzVM -ResourceGroupName $resourceGroupName -Name $vmName
}


