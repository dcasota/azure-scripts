# .SYNOPSIS
#  Provision an Azure virtual machine from a user Azure VMware Photon OS image.
#
# .DESCRIPTION
#  The script provisions an Azure virtual machine by the location, the Azure VMware Photon OS image name and resource group, the vm resource group, the vm name and the vm local admin credentials as mandatory parameters.
#  If there is no previously created Azure VMware Photon OS image name, do use the Azure Virtual Machine Image builder script create-AzImage-PhotonOS.ps1 to create an image.
#  The image name looks like photon-azure-4.0-c001795b8_V2.vhd. The image already contains the information if it is a HyperVGeneration V1 or V2 image.
#
#  The script installs the Az 8.0 module if necessary and triggers an Azure login using the device code method. You get a similar message to
#    WARNUNG: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code xxxxxxxxx to authenticate.
#  The Azure Powershell output shows up as warning (see above). Open a webbrowser, and fill in the code given by the Azure Powershell login output.
#
#  After the login on Azure, it uses the specified location and resource group of the Azure image and provisions the virtual machine. Default Azure vm size is Standard_B1ms.
#
#  .PREREQUISITES
#    - Script must run on MS Windows OS with Powershell PSVersion 5.1 or higher
#    - Azure account with Virtual Machine contributor role
#
# .NOTES
# 0.1   16.02.2020   dcasota  First release
# 0.2   23.04.2020   dcasota  adopted params to create-AzImage-PhotonOS.ps1
# 0.3   12.05.2020   dcasota  bugfix retrieving storageaccountkey
# 0.4   19.09.2020   dcasota  differentiation between image resourcegroup and vm resourcegroup
# 0.5   02.03.2021   dcasota  switched to device code login
# 0.51  21.03.2021   dcasota  List available Azure locations updated
# 0.6   07.04.2021   dcasota  Minor fixing
# 0.7   11.07.2022   dcasota  Bugfixing, substitution of Azure CLI commands with Azure Powershell commands, text changes
#
#
# .PARAMETER
# Parameter LocationName
#    Azure location name where to create or lookup the resource group
# Parameter ResourceGroupNameImage
#    Azure resource group name of the Azure image
# Parameter Imagename
#    Azure image name for the uploaded VMware Photon OS
# Parameter ResourceGroupName
#    Azure resource group name
# Parameter VMName
#    Name of the virtual machine to be created
# Parameter StorageAccountName
#    Azure storage account name
# Parameter ContainerName
#    Azure storage container name
# Parameter BlobName
#    Azure Blob Name for the Photon OS .vhd
# Parameter VMName
#    Name of the virtual machine to be created
# Parameter VMSize
#    Azure virtual machine size offering
# Parameter nsgName
#    network security group name
# Parameter NetworkName
#    network name
# Parameter VnetAddressPrefix
#    virtual network address. Use cidr format, eg. "192.168.0.0/16"
# Parameter SubnetAddressPrefix
#    subnet address. Use cidr format, eg. "192.168.0.0/24"
# Parameter Computername
#    computername
# Parameter NICName
#    virtual network card name
# Parameter PublicIPDNSName
#    virtual machine public IP DNS name
# Parameter VMLocalAdminCredential
#    virtual machine local admin credential
#
# .EXAMPLE
#    ./create-AzVM_FromImage-PhotonOS.ps1 -Location switzerlandnorth -ResourceGroupNameImage ph4rev2 -ImageName photon-azure-4.0-c001795b8_V2.vhd -ResourceGroupName ph4rev2 -VMName ph4rev2 -VMLocalAdminCredential $(Get-credential -message 'Specify a Photon OS local admin username and password. Password must be 12-23 chars long.')

[CmdletBinding()]
param(
[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$LocationName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ResourceGroupNameImage,

[Parameter(Mandatory = $false)]
[string]$RuntimeId = (Get-Random).ToString(),

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ImageName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ResourceGroupName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$VMName,

[Parameter(Mandatory = $false)][ValidateLength(3,24)][ValidatePattern("[a-z0-9]")]
[string]$StorageAccountName=("PhotonOS${RuntimeId}").ToLower(),

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$ContainerName = "${RuntimeId}disks",

[Parameter(Mandatory = $false)][ValidateNotNull()]
$VMSize = "Standard_B1ms",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$nsgName = "${RuntimeId}nsg",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$NetworkName = "${RuntimeId}vnet",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$SubnetAddressPrefix = "192.168.1.0/24",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$VnetAddressPrefix = "192.168.0.0/16",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$ComputerName = $VMName,

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$NICName = "${RuntimeId}nic"

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$PublicIPDNSName="{RuntimeId}dns"

[Parameter(Mandatory = $true)][ValidateNotNull()]
$VMLocalAdminCredential = Get-Credential -Message "Specify a Photon OS local admin username and password. Password must be 12-23 chars long."

)


# check Azure Powershell
# https://github.com/Azure/azure-powershell/issues/13530
# https://github.com/Azure/azure-powershell/issues/13337
$check=get-module -ListAvailable | where-object {$_ -ilike 'Az.*'}
if ([Object]::ReferenceEquals($check,$null))
{
    install-module -name Az -MinimumVersion "8.0" -ErrorAction SilentlyContinue
    write-host "Please restart the script."
    exit
}
else
{
    update-module -Name Az -RequiredVersion "8.0" -ErrorAction SilentlyContinue
}

$azconnect=get-azcontext -ErrorAction SilentlyContinue
if ([Object]::ReferenceEquals($azconnect,$null))
{
    $azconnect=connect-azaccount -devicecode
}


if (!(Get-variable -name azconnect -ErrorAction SilentlyContinue))
{
    write-host "Azure Powershell login required."
    break
}

#Set the context to the subscription Id where Managed Disk exists and where virtual machine will be created if necessary
$subscriptionId=(get-azcontext).Subscription.Id
# set subscription
select-AzSubscription -Subscription $subscriptionId

# Verify virtual machine doesn't exist
[Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction SilentlyContinue
if ($VM)
{
	write-host "VM $VMName already exists."
	break
}

# Verify if image exists
$result=get-azimage -ResourceGroupName $ResourceGroupNameImage -Name $Imagename -ErrorAction SilentlyContinue
if ( -not $($result))
{
	write-host "Could not find Azure image $Imagename on resourcegroup $ResourceGroupNameImage."
	break
}

# create resource group if it does not exist
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
	if ( -not $($storageaccount))
    {
        write-host "Storage account has not been created. Check if the name is already taken."
        break
    }
}
do {sleep -Milliseconds 1000} until ($((get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).ProvisioningState) -ieq "Succeeded") 
$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)
$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue


$result=get-azstoragecontainer -Name ${ContainerName} -Context $storageaccount.Context -ErrorAction SilentlyContinue 
if ( -not $($result))
{
    new-azstoragecontainer -Name ${ContainerName} -Context $storageaccount.Context -ErrorAction SilentlyContinue -Permission Blob
}

# network security rules configuration
$nsg=get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if ( -not $($nsg))
{
	$nsgRule1 = New-AzNetworkSecurityRuleConfig -Name nsgRule1 -Description "Allow SSH" `
	-Access Allow -Protocol Tcp -Direction Inbound -Priority 100 `
	-SourceAddressPrefix Internet -SourcePortRange * `
	-DestinationAddressPrefix * -DestinationPortRange 22
	$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $LocationName -SecurityRules $nsgRule1
}

# set network if not already set
$vnet = get-azvirtualnetwork -name $networkname -ResourceGroupName $resourcegroupname -ErrorAction SilentlyContinue
if ( -not $($vnet))
{
    $ServerSubnet  = New-AzVirtualNetworkSubnetConfig -Name frontendSubnet  -AddressPrefix $SubnetAddressPrefix -NetworkSecurityGroup $nsg
	$vnet = New-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -Location $LocationName -AddressPrefix $VnetAddressPrefix -Subnet $ServerSubnet
	$vnet | Set-AzVirtualNetwork
}

# Create a public IP address
$nic=get-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if ( -not $($nic))
{
	$pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $LocationName -Name $PublicIPDNSName -AllocationMethod Static -IdleTimeoutInMinutes 4
	# Create a virtual network interface and associate it with public IP address and NSG
	$nic = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName `
		-SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id
}

# create virtual machine
$VM = New-AzVMConfig -VMName $VMName -VMSize $VMSize
$VM = Set-AzVMOperatingSystem -VM $VM -Linux -ComputerName $ComputerName -Credential $VMLocalAdminCredential
$VM = Add-AzVMNetworkInterface -VM $VM -Id $nic.Id
$VM = $VM | set-AzVMSourceImage -Id (get-azimage -ResourceGroupName $ResourceGroupNameImage -ImageName $ImageName).Id
$VM| Set-AzVMBootDiagnostic -Disable

New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VM

$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
Set-AzVMBootDiagnostic -VM $VM -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName
