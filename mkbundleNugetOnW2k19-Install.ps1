#
# Deploy a windows 2019 worker on Microsoft Azure with mono with cross-compile to Ubuntu and blob store the mkbundled nuget.exe.
#
# History
# 0.1  4.10.2019   dcasota  Initial release
#
# related learn weblinks
# https://github.com/MicrosoftDocs/azure-docs-powershell/blob/master/docs-conceptual/Azps-4.4.1/install-Az-ps.md
# https://github.com/kpatnayakuni/PowerShell/blob/master/Create-AzVM.ps1
# https://kpatnayakuni.com/2019/01/03/create-new-azure-vm-using-powershell-az/
# https://blog.kaniski.eu/
# https://docs.microsoft.com/en-us/azure/storage/common/storage-redundancy
# https://docs.microsoft.com/en-us/rest/api/storagerp/storageaccounts/list
#
# SKU
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/cli-ps-findimage
#
# https://docs.microsoft.com/en-us/powershell/azure/new-azureps-module-az?view=azps-2.2.0
# The existing Az module will no longer receive new cmdlets or features. However, Az is still officially maintained and will get bug fixes up through at least December 2020.
# Starting in December 2018, the Azure PowerShell Az module is in general release and now the intended PowerShell module for interacting with Azure.
# Using Az with PowerShell 5.1 for Windows requires the installation of .NET Framework 4.7.2. Using PowerShell Core 6.x or later does not require .NET Framework.
#
# must be in an elevated powershell session
# install-module -name powershellget -force
#
# uninstall von AzureRM
# get-command -listavailable | %{if ($_.module -match "AzureRM") {uninstall-module -name $_.module -Force}}
#
# Install az. can be in a non-elevated powershell session
# install-module -name az -AllowClobber -Force
# 



# Location setting
$LocationName = "westeurope"

# Resourcegroup setting
$ResourceGroupName = "azure-scripts"

# network setting
$NetworkName = "mssql-lab"

# virtual network and subnets setting
$SubnetAddressPrefix = "192.168.1.0/24"
$VnetAddressPrefix = "192.168.0.0/16"

# VM setting
$VMSize = "Standard_F4"
$ComputerName = "mssql01"
$VMName = "mssql01"
$NICName = "mssqlnic01"
$VMLocalAdminUser = "LocalAdminUser"
$VMLocalAdminPwd="Secure123!"
$disk1SizeGB = "20"
$PublicIPDNSName="mypublicdns$(Get-Random)"
$nsgName = "myNetworkSecurityGroup"

# Create az login object. You get a pop-up prompting you to enter the credentials.
$cred = Get-Credential -Message "Enter a username and password for az login."
connect-Azaccount -Credential $cred
# Verify Login
if( -not $(Get-AzContext) ) { return }

# Verify VM doesn't exist
[Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] `
$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction SilentlyContinue
if (-not ([string]::IsNullOrEmpty($VM))) { return }

# create lab resource group if it does not exist
$result = get-azresourcegroup -name $ResourceGroupName -Location $LocationName -ErrorAction SilentlyContinue
if (([string]::IsNullOrEmpty($result)))
{
    New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName
}

$vnet = get-azvirtualnetwork -name $networkname -ResourceGroupName $resourcegroupname -ErrorAction SilentlyContinue
if (([string]::IsNullOrEmpty($vnet)))
{
    $SingleSubnet  = New-AzVirtualNetworkSubnetConfig -Name frontendSubnet -AddressPrefix $SubnetAddressPrefix
    $vnet = New-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -Location $LocationName -AddressPrefix $VnetAddressPrefix -Subnet $SingleSubnet
    $vnet | Set-AzVirtualNetwork
}


# create vm
# -----------

# VM local admin setting
$VMLocalAdminSecurePassword = ConvertTo-SecureString $VMLocalAdminPwd -AsPlainText -Force
$LocalAdminUserCredential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword)

# networksecurityruleconfig
$nsg=get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (([string]::IsNullOrEmpty($nsg)))
{
    $rdpRule = New-AzNetworkSecurityRuleConfig -Name myRdpRule -Description "Allow RDP" `
    -Access Allow -Protocol Tcp -Direction Inbound -Priority 110 `
    -SourceAddressPrefix Internet -SourcePortRange * `
    -DestinationAddressPrefix * -DestinationPortRange 3389
    $nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $LocationName -SecurityRules $rdpRule
}
# Create a public IP address
$nic=get-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (([string]::IsNullOrEmpty($nic)))
{
    $pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $LocationName -Name $PublicIPDNSName -AllocationMethod Static -IdleTimeoutInMinutes 4
    # Create a virtual network card and associate with public IP address and NSG
    $nic = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName `
        -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id
}

# data disk storage setting
$storageType = 'Standard_LRS'
$dataDiskName1 = "Data"
$diskConfig1 = New-AzDiskConfig -SkuName $storageType -Location $LocationName -CreateOption Empty -DiskSizeGB $disk1SizeGB -Zone 1
$dataDisk1 = New-AzDisk -DiskName $dataDiskName1 -Disk $diskConfig1 -ResourceGroupName $ResourceGroupName

# Create a virtual machine configuration
$vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize | `
Set-AzVMOperatingSystem -Windows -ComputerName $ComputerName -Credential $LocalAdminUserCredential | `
Set-AzVMSourceImage -PublisherName 'MicrosoftWindowsServer' -Offer 'WindowsServer' -Skus '2019-Datacenter-with-Containers' -Version latest | `
Add-AzVMDataDisk -Name $dataDiskName1 -CreateOption Attach -ManagedDiskId $dataDisk1.Id -Lun 0 | `
Add-AzVMNetworkInterface -Id $nic.Id

# Create the VM
New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $vmConfig

# Verify that the vm was created
$vmList = Get-AzVM -ResourceGroupName $resourceGroupName
$vmList.Name

#TODO
