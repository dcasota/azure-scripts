#
# The script creates an Azure Generation V2 VM from an individual VMware Photon OS Azure Image.
#
# 
# See creation using create-AzImage_GenV2-PhotonOS.ps1.
#
# History
# 0.1   16.02.2020   dcasota  First release
#
#
# Prerequisites:
#    - Microsoft Powershell, Microsoft Azure Powershell
#    - Azure account
#
# Parameter username
#    Azure login username
# Parameter password
#    Azure login password
# Parameter VMName
#    Name of the VM to be created
# Parameter LocationName
#    Azure location name where to create or lookup the resource group
# Parameter ResourceGroupName
#    Azure resource group name
# Parameter StorageAccountName
#    Azure storage account name
# Parameter ContainerName
#    Azure storage container name
# Parameter BlobName
#    Azure Blob Name for the Photon OS .vhd
# Parameter Imagename
#    Azure image name for the uploaded VMware Photon OS
#

[CmdletBinding()]
param(
[Parameter(Mandatory = $true, ParameterSetName = 'PlainText')]
[String]$username,
[Parameter(Mandatory = $true, ParameterSetName = 'PlainText')]
[String]$password,
[string]$LocationName = "switzerlandnorth",
[string]$ResourceGroupName = "photonos-lab-rg",
[string]$StorageAccountName="photonoslab",
[string]$ContainerName="disks",
[string]$ImageName="photon-azure-3.0-9355405",
[string]$VMName = "PhotonOS"
)


# VM settings
# -----------
# network setting
$NetworkName = "w2k19network"
# virtual network and subnets setting
$SubnetAddressPrefix = "192.168.1.0/24"
$VnetAddressPrefix = "192.168.0.0/16"
# VM setting
$VMSize = "Standard_E4s_v3"
$DiskName="PhotonOS"
$VMSize_TempPath="d:" # on this drive $SoftwareToProcess is processed
$ComputerName = $VMName
$NICName = $ComputerName + "nic"
$VMLocalAdminUser = "LocalAdminUser"
$VMLocalAdminPwd="Secure2020123!" #12-123 chars
$PublicIPDNSName="mypublicdns$(Get-Random)"
$nsgName = "myNetworkSecurityGroup"


# check Azure CLI
if (-not ($($env:path).contains("CLI2\wbin")))
{
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
    $env:path="C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin;"+$env:path
}

# check Azure Powershell
if (([string]::IsNullOrEmpty((get-module -name Az* -listavailable)))) {install-module Az -force -ErrorAction SilentlyContinue}

# Azure Login
$secpasswd = ConvertTo-SecureString ${password} -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential ($username,$secpasswd)
$azcontext=connect-Azaccount -Credential $cred
if (-not $($azcontext)) {break}

#Set the context to the subscription Id where Managed Disk exists and where VM will be created
$subscriptionId=(get-azcontext).Subscription.Id
# set subscription
az account set --subscription $subscriptionId

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

# Verify VM doesn't exist
[Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction SilentlyContinue
if (-not ($VM))
{
    # Create a public IP address
    $nic=get-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if ( -not $($nic))
    {
        $pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $LocationName -Name $PublicIPDNSName -AllocationMethod Static -IdleTimeoutInMinutes 4
        # Create a virtual network card and associate with public IP address and NSG
        $nic = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName `
            -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id
    }

    # VM local admin setting
    $VMLocalAdminSecurePassword = ConvertTo-SecureString $VMLocalAdminPwd -AsPlainText -Force
    $LocalAdminUserCredential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword)

    $VM = New-AzVMConfig -VMName $VMName -VMSize $VMSize
    $VM = Set-AzVMOperatingSystem -VM $VM -Linux -ComputerName $ComputerName -Credential $LocalAdminUserCredential
    $VM = Add-AzVMNetworkInterface -VM $VM -Id $nic.Id
    $VM = $VM | set-AzVMSourceImage -Id (get-azimage -ResourceGroupName $ResourceGroupName -ImageName $ImageName).Id
    New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VM

    $VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
    Set-AzVMBootDiagnostic -VM $VM -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName
}

