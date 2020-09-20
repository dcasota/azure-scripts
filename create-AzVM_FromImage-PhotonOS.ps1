#
# The script provisions an Azure virtual machine from a user VMware Photon OS Azure image.
#
# 
# See create-AzImage-PhotonOS.ps1 for user VMware Photon OS Azure image creation.
#
# History
# 0.1   16.02.2020   dcasota  First release
# 0.2   23.04.2020   dcasota  adopted params to create-AzImage-PhotonOS.ps1
# 0.3   12.05.2020   dcasota  bugfix retrieving storageaccountkey
# 0.4   19.09.2020   dcasota  differentiation between image resourcegroup and vm resourcegroup
#
#
# Prerequisites:
#    - Microsoft Powershell, Microsoft Azure Powershell
#    - Azure account
#
# .PARAMETER cred
#   Azure login credential
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
#    ./create-AzVM_FromImage-PhotonOS.ps1 -cred $(Get-credential -message 'Enter a username and password for Azure login.') -Location switzerlandnorth -ResourceGroupNameImage photonoslab-rg -ImageName photon-azure-3.0-9355405.vhd -ResourceGroupName photonoslab -StorageAccountName photonoslabstorage  -VMName PhotonOS3.0rev2

[CmdletBinding()]
param(
[Parameter(Mandatory = $false)]
[ValidateNotNull()]
[System.Management.Automation.PSCredential]
[System.Management.Automation.Credential()]$cred = (Get-credential -message 'Enter a username and password for the Azure login.'),

[Parameter(Mandatory = $true)][ValidateNotNull()]
[ValidateSet('eastasia','southeastasia','centralus','eastus','eastus2','westus','northcentralus','southcentralus',`
'northeurope','westeurope','japanwest','japaneast','brazilsouth','australiaeast','australiasoutheast',`
'southindia','centralindia','westindia','canadacentral','canadaeast','uksouth','ukwest','westcentralus','westus2',`'koreacentral','koreasouth','francecentral','francesouth','australiacentral','australiacentral2',`
'uaecentral','uaenorth','southafricanorth','southafricawest','switzerlandnorth','switzerlandwest',`
'germanynorth','germanywestcentral','norwaywest','norwayeast')]
[string]$LocationName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ResourceGroupNameImage,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ImageName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ResourceGroupName,

[Parameter(Mandatory = $true)][ValidateNotNull()][ValidateNotNull()][ValidateLength(3,24)][ValidatePattern("[a-z0-9]")]
[string]$StorageAccountName,

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$ContainerName = "disks",

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$VMName,

[Parameter(Mandatory = $false)][ValidateNotNull()]
$VMSize = "Standard_B1ms",

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
[string]$VMLocalAdminUser = "LocalAdminUser",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$VMLocalAdminPwd="Secure2020123!" #12-123 chars
)

#admin role
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())
$AdminRole=($myWindowsPrincipal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))

# check Azure CLI
if (-not ($($env:path).contains("CLI2\wbin")))
{
    if (!($AdminRole))
    {
        write-host "Administrative privileges required."
        break
    }
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
    $env:path="C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin;"+$env:path
}

# check Azure Powershell
if (([string]::IsNullOrEmpty((get-module -name Az* -listavailable)))) {install-module Az -force -ErrorAction SilentlyContinue}

# Azure Login
$azcontext=connect-Azaccount -Credential $cred
if (-not $($azcontext)) {break}

#Set the context to the subscription Id where Managed Disk exists and where VM will be created
$subscriptionId=(get-azcontext).Subscription.Id
# set subscription
az account set --subscription $subscriptionId

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

# create storageaccount if it does not exist
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

$result=az storage container exists --account-name $storageaccountname --name ${ContainerName} | convertfrom-json
if ($result.exists -eq $false)
{
    az storage container create --name ${ContainerName} --public-access blob --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value
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
New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VM

$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
Set-AzVMBootDiagnostic -VM $VM -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName
