# .SYNOPSIS
#  The script provisions an Azure virtual machine from a user VMware Photon OS Azure image.
#
# .DESCRIPTION
#  Actually there are no official Azure marketplace images of VMware Photon OS. You can create one using the official .vhd file of a specific VMware Photon OS build, or
#  you can use the Azure Virtual Machine Image builder script create-AzImage-PhotonOS.ps1 to create an Azure image.
#  This script does a device login on Azure, and uses the specified location and resource group of the Azure image and provisions a virtual machine. Default Azure VM size is Standard_B1ms.
#  
#  With the start it does twice trigger an Azure login using the device code method.
#  
#      az : WARNING: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code xxxxxxxxx to authenticate.
#      In Zeile:1 Zeichen:13
#      + $azclilogin=az login --use-device-code
#          +             ~~~~~~~~~~~~~~~~~~~~~~~~~~
#          + CategoryInfo          : NotSpecified: (WARNING: To sig...o authenticate.:String) [], RemoteException
#          + FullyQualifiedErrorId : NativeCommandError
#
#    WARNUNG: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code xxxxxxxxx to authenticate.
#
#  The Azure CLI and Azure Powershell output shows up as warning (see above).
#  You will have to open a webbrowser, and fill in the code given by the Azure Powershell login output and by the Azure CLI login output.
#
#
#  It would be nice to avoid some cmdlets-specific warning output on the host screen during run. You can safely ignore Warnings, especially:
#  "WARNUNG: System.ArgumentException: Argument passed in is not serializable." + appendings like "Microsoft.WindowsAzure.Commands.Common.MetricHelper"
#  "az : WARNING: There are no credentials provided in your command and environment, we will query for the account key inside your storage account."
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
#
#
# .PARAMETER azconnect
#   Azure powershell devicecode login
# .PARAMETER azclilogin
#   Azure CLI devicecode login
# Parameter VMName
#    Name of the virtual machine to be created
# Parameter LocationName
#    Azure location name where to create or lookup the resource group
# Parameter ResourceGroupNameImage
#    Azure resource group name of the Azure image
# Parameter Imagename
#    Azure image name for the uploaded VMware Photon OS
# Parameter ResourceGroupName
#    Azure resource group name
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
# Parameter VMLocalAdminUser
#    virtual machine local username
# Parameter VMLocalAdminPwd
#    virtual machine local user password
# Parameter PublicIPDNSName
#    virtual machine public IP DNS name
#
# .EXAMPLE
#    ./create-AzVM_FromImage-PhotonOS.ps1 -Location switzerlandnorth -ResourceGroupNameImage ph4rev2 -ImageName photon-azure-4.0-c001795b8_V2.vhd -ResourceGroupName ph4rev2 -VMName ph4rev2

[CmdletBinding()]
param(
[Parameter(Mandatory = $false)]
[ValidateNotNull()]
[string]$azconnect,
[Parameter(Mandatory = $false)]
[ValidateNotNull()]
[string]$azclilogin,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[ValidateSet('eastasia','southeastasia','centralus','eastus','eastus2','westus','northcentralus','southcentralus',`
'northeurope','westeurope','japanwest','japaneast','brazilsouth','australiaeast','australiasoutheast',`
'southindia','centralindia','westindia','canadacentral','canadaeast','uksouth','ukwest','westcentralus','westus2',`
'koreacentral','koreasouth','francecentral','francesouth','australiacentral','australiacentral2',`
'uaecentral','uaenorth','southafricanorth','southafricawest','switzerlandnorth','switzerlandwest',`
'germanynorth','germanywestcentral','norwaywest','norwayeast','brazilsoutheast','westus3')]
[string]$LocationName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ResourceGroupNameImage,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ImageName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ResourceGroupName,

[Parameter(Mandatory = $false)][ValidateNotNull()][ValidateNotNull()][ValidateLength(3,24)][ValidatePattern("[a-z0-9]")]
[string]$StorageAccountName=$ResourceGroupName.ToLower()+"storage",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$ContainerName = "disks",

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$VMName,

[Parameter(Mandatory = $false)][ValidateNotNull()]
$VMSize = "Standard_E4s_v3",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$nsgName = "nsg"+$VMName,

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$NetworkName = "network"+$VMName,

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$SubnetAddressPrefix = "192.168.1.0/24",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$VnetAddressPrefix = "192.168.0.0/16",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$ComputerName = $VMName,

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$NICName = "ni"+$VMName,

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$PublicIPDNSName="publicdns"+$VMName,

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$VMLocalAdminUser = "Local",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$VMLocalAdminPwd="Secure2020123." #12-123 chars
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
    exit
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
	exit
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
    $nsRule1 = New-AzNetworkSecurityRuleConfig -Name myPort80Rule -Description "Allow http" `
	-Access Allow -Protocol Tcp -Direction Inbound -Priority 110 `
	-SourceAddressPrefix Internet -SourcePortRange * `
	-DestinationAddressPrefix * -DestinationPortRange 80	
	$nsRule2 = New-AzNetworkSecurityRuleConfig -Name mySSHRule -Description "Allow SSH" `
	-Access Allow -Protocol Tcp -Direction Inbound -Priority 100 `
	-SourceAddressPrefix Internet -SourcePortRange * `
	-DestinationAddressPrefix * -DestinationPortRange 22
	$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $LocationName -SecurityRules $nsRule1,$nsRule2
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

# virtual machine local admin setting
$VMLocalAdminSecurePassword = ConvertTo-SecureString $VMLocalAdminPwd -AsPlainText -Force
$LocalAdminUserCredential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword)

# create virtual machine
$VM = New-AzVMConfig -VMName $VMName -VMSize $VMSize
$VM = Set-AzVMOperatingSystem -VM $VM -Linux -ComputerName $ComputerName -Credential $LocalAdminUserCredential
$VM = Add-AzVMNetworkInterface -VM $VM -Id $nic.Id
$VM = $VM | set-AzVMSourceImage -Id (get-azimage -ResourceGroupName $ResourceGroupNameImage -ImageName $ImageName).Id

# $VM = Set-AzVmSecurityProfile -VM $VM -SecurityType  "trustedLaunch"
# $VM  = Set-AzVmUefi -VM $VM -EnableVtpm  $true  -EnableSecureBoot $true

New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VM

$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
Set-AzVMBootDiagnostic -VM $VM -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName
