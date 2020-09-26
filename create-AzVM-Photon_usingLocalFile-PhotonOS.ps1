#
# The script creates an Azure virtual machine with VMware Photon OS.
# 
#
# History
# 0.1  27.09.2020   dcasota  first release
#
# Prerequisites:
#    - Microsoft Powershell, Microsoft Azure Powershell, Microsoft Azure CLI
#    - must run in an elevated powershell session
#    - VMware Photon OS .vhd image
#    - Azure account
#
# Parameter LocalFilePath
#    Specifies the local file path to the unzipped VMware Photon OS .vhd
# Parameter BlobName
#    Azure Blob Name for the Photon OS .vhd
# Parameter cred
#    Azure login credentials
# Parameter LocationName
#    Azure location name where to create or lookup the resource group
# Parameter ResourceGroupName
#    Azure resource group name
# Parameter StorageAccountName
#    Azure storage account name
# Parameter ContainerName
#    Azure storage container name 
# Parameter NetworkName
#    Azure VNet Network name
# Parameter VnetAddressPrefix
#    Azure VNet subnet. Use the format like "192.168.0.0/16"
# Parameter ServerSubnetAddressPrefix
#    Azure Server subnet address prefix. Use the format like "192.168.1.0/24"
# Parameter VMName
#    Name of the Azure VM
# Parameter VMSize
#    Azure offering. Use the format like "Standard_E4s_v3". See 'Important information' below.
# Parameter NICName1
#    Name for the first nic adapter
# Parameter Ip1Address
#    Private IP4 address of the first nic adapter exposed to the Azure VM
# Parameter PublicIPDNSName
#    Public IP4 name of the first nic adapter
# Parameter nsgName
#    Name of the network security group, the nsg is applied to both nics
# Parameter diskName
#    Name of the Photon OS disk
# Parameter diskSizeGB
#    Disk size of the Photon OS disk. Minimum is 16gb
# Parameter Computername
#    Hostname Photon OS. The hostname is not set for ESXi (yet).
# Parameter VMLocalAdminUser
#    Local Photon OS user
# Parameter VMLocalAdminPassword
#    Local Photon OS user password. Must be 7-12 characters long, and meet pwd complexitiy rules.
#

function create-AzVM-Photon_usingPhotonOS{
   [cmdletbinding()]
    param(
        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        # Local file path of unzipped Photon OS 3.0 GA .vhd from http://dl.bintray.com/vmware/photon/3.0/GA/azure/photon-azure-3.0-26156e2.vhd.tar.gz
        # Local file path of unzipped Photon OS 3.0 rev2 .vhd from http://dl.bintray.com/vmware/photon/3.0/Rev2/azure/photon-azure-3.0-9355405.vhd.tar.gz
        $LocalFilePath="J:\photon-azure-2.0-3146fa6.tar\photon-azure-2.0-3146fa6.vhd",

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]$cred = (Get-credential -message 'Enter a username and password for the Azure login.'),	

        [Parameter(Mandatory = $false)]
        [ValidateSet('eastus','westus','westeurope','switzerlandnorth')]
        [String]$LocationName="switzerlandnorth",
        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$ResourceGroupName="p3",

        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$StorageAccountName="photonos$(Get-Random)",
		# Photon OS Image Blob name
        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$BlobName= (split-path $LocalFilePath -leaf) ,
        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$ContainerName="disks",

        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$NetworkName="photonos-lab-network",
        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$VnetAddressPrefix="192.168.0.0/16",
        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$ServerSubnetAddressPrefix="192.168.1.0/24",

        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$VMSize = "Standard_B1ms",

        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$VMName = "photonos",
        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$NICName1 = "${VMName}nic1",
        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$Ip1Address="192.168.1.6",
		[Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$PublicIPDNSName="${NICName1}dns",
        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$nsgName = "myNetworkSecurityGroup",
        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$diskName = "photonosdisk",
        [Parameter(Mandatory = $false, ParameterSetName = 'PlainText')]
        [String]$diskSizeGB = '16', # minimum is 16gb

        [String]$Computername = $VMName ,
        
        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]$VMLocalcred = (Get-credential -message 'Enter username and password for the VM user account to be created locally. Password must be 7-12 characters. Username must be all in small letters.')        	
   		
    )

# Step #1: Check prerequisites and Azure login
# --------------------------------------------
# check if .vhd exists
if (!(Test-Path $LocalFilePath)) {break}

# check Azure CLI
az help 1>$null 2>$null
if ($lastexitcode -ne 0) {break}

# check Azure Powershell
if (([string]::IsNullOrEmpty((get-module -name Az* -listavailable)))) {break}

# Azure login
connect-Azaccount -Credential $cred
$azcontext=get-azcontext
if( -not $($azcontext) ) { return }
#Set the context to the subscription Id where Managed Disk exists and where VM will be created
$subscriptionId=($azcontext).Subscription.Id
# set subscription
az account set --subscription $subscriptionId

# Verify VM doesn't exist
[Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] `
$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($VM,$null))) { return }

# Step #2: create a resource group and storage container
# ------------------------------------------------------
# create lab resource group if it does not exist
$result = get-azresourcegroup -name $ResourceGroupName -Location $LocationName -ErrorAction SilentlyContinue
if (-not ($result))
{
    New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName
}

$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (-not ($storageaccount))
{
    New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $LocationName -Kind Storage -SkuName Standard_LRS -ErrorAction SilentlyContinue
}
$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)


$result=az storage container exists --account-name $storageaccountname --name ${ContainerName} | convertfrom-json
if ($result.exists -eq $false)
{
    try {
        az storage container create --name ${ContainerName} --public-access blob --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value
    } catch{}
}

# Step #3: upload the Photon OS .vhd as page blob
# -----------------------------------------------
$urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${BlobName}"
$result=az storage blob exists --account-key ($storageaccountkey[0]).value --account-name $StorageAccountName --container-name ${ContainerName} --name ${BlobName} | convertfrom-json
if ($result.exists -eq $false)
{
    try {
    az storage blob upload --account-name $StorageAccountName `
    --account-key ($storageaccountkey[0]).value `
    --container-name ${ContainerName} `
    --type page `
    --file $LocalFilePath `
    --name ${BlobName}
    } catch{}
}

# Step #4: create virtual network and security group
# --------------------------------------------------

# networksecurityruleconfig, UNFINISHED as VMware ESXi ports must be included
$nsg=get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (-not ($nsg))
{
	$rdpRule1 = New-AzNetworkSecurityRuleConfig -Name myRdpRule -Description "Allow http" `
	-Access Allow -Protocol Tcp -Direction Inbound -Priority 110 `
	-SourceAddressPrefix Internet -SourcePortRange * `
	-DestinationAddressPrefix * -DestinationPortRange 80
	$rdpRule2 = New-AzNetworkSecurityRuleConfig -Name mySSHRule -Description "Allow SSH" `
	-Access Allow -Protocol Tcp -Direction Inbound -Priority 100 `
	-SourceAddressPrefix Internet -SourcePortRange * `
	-DestinationAddressPrefix * -DestinationPortRange 22
	$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $LocationName -SecurityRules $rdpRule1,$rdpRule2
}

# network if not already set
$vnet = get-azvirtualnetwork -name $networkname -ResourceGroupName $resourcegroupname -ErrorAction SilentlyContinue
if (-not ($vnet))
{
	$ServerSubnet  = New-AzVirtualNetworkSubnetConfig -Name frontendSubnet  -AddressPrefix $ServerSubnetAddressPrefix -NetworkSecurityGroup $nsg
	$vnet = New-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -Location $LocationName -AddressPrefix $VnetAddressPrefix -Subnet $ServerSubnet
	$vnet | Set-AzVirtualNetwork
}

# Step #5: create a nic with a public IP address
# ----------------------------------------------
$nic1=get-AzNetworkInterface -Name $NICName1 -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (-not ($nic1))
{
	$pip1 = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $LocationName -Name $PublicIPDNSName -AllocationMethod Static -IdleTimeoutInMinutes 4
	# Create a virtual network card and associate with public IP address and NSG
	$nic1 = New-AzNetworkInterface -Name $NICName1 -ResourceGroupName $ResourceGroupName -Location $LocationName `
		-SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip1.Id -NetworkSecurityGroupId $nsg.Id -EnableIPForwarding
    # assign static IP adress
    if (-not ([string]::IsNullOrEmpty($nic1)))
    {
        $nic1=get-aznetworkinterface -resourcegroupname $resourcegroupname -name $NICName1
        $nic1.IpConfigurations[0].PrivateIpAddress=$Ip1Address
        $nic1.IpConfigurations[0].PrivateIpAllocationMethod="static"
        $nic1.tag=@{Name="Name";Value="Value"}
        set-aznetworkinterface -networkinterface $nic1
    }

}

# Step #6: create the vm with Photon OS
# -------------------------------------
$VMLocalAdminUser=$VMLocalcred.GetNetworkCredential().username
$VMLocalAdminPassword=$VMLocalcred.GetNetworkCredential().password

# az vm create
try {
	az vm create --resource-group ${ResourceGroupName} --location ${LocationName} --name ${vmName} `
	--size ${VMSize} `
	--admin-username ${VMLocalAdminUser} --admin-password ${VMLocalAdminPassword} `
	--storage-account ${StorageAccountName} `
	--storage-container-name ${ContainerName} `
	--os-type linux `
	--use-unmanaged-disk `
	--os-disk-size-gb ${diskSizeGB} `
	--image ${urlOfUploadedVhd} `
	--attach-data-disks ${urlOfUploadedVhd} `
	--computer-name ${computerName} `
	--nics ${NICName1} `
	--generate-ssh-keys `
	--boot-diagnostics-storage "https://${StorageAccountName}.blob.core.windows.net"
} catch {}

}

create-AzVM-Photon_usingPhotonOS