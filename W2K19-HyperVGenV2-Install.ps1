﻿#
# Deploy Windows 2019 datacenter-generation2 on Microsoft Azure.
#
# History
# 0.1   26.01.2020   dcasota  Initial release
#
# related learn weblinks
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/generation-2
#
# SKU
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/cli-ps-findimage
#
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
$ResourceGroupName = "azure-scripts-rg"

# network setting
$NetworkName = "w2k19lab"

# virtual network and subnets setting
$SubnetAddressPrefix = "192.168.1.0/24"
$VnetAddressPrefix = "192.168.0.0/16"

# VM setting
$VMSize = "Standard_E4s_v3"
$ComputerName = "w2k19-01"
$VMName = $ComputerName
$NICName = $ComputerName + "nic"
$VMLocalAdminUser = "LocalAdminUser"
$VMLocalAdminPwd="Secure123!"
$disk1SizeGB = "20"
$PublicIPDNSName="mypublicdns$(Get-Random)"
$nsgName = "myNetworkSecurityGroup"
$publisherName = "MicrosoftWindowsServer"
$offerName = "WindowsServer"
$skuName = "2019-datacenter-gensecond"
$marketplacetermsname= "2019-datacenter-gensecond"
# Get-AzVMImage -Location westus2 -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2019-datacenter-gensecond
$productversion = "17763.973.2001110547"

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
$diskConfig1 = New-AzDiskConfig -SkuName $storageType -Location $LocationName -HyperVGeneration "V2" -CreateOption Empty -DiskSizeGB $disk1SizeGB -Zone 1
$dataDisk1 = New-AzDisk -DiskName $dataDiskName1 -Disk $diskConfig1 -ResourceGroupName $ResourceGroupName


# marketplace plan
# be aware first the marketplace terms must be accepted manually. https://github.com/terraform-providers/terraform-provider-azurerm/issues/1145#issuecomment-383070349

# Create a virtual machine configuration
$vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize | `
Add-AzVMNetworkInterface -Id $nic.Id

$vmimage= get-azvmimage -Location $LocationName -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $productversion
if (!(([string]::IsNullOrEmpty($vmimage))))
{
    if (!(([string]::IsNullOrEmpty($vmimage.PurchasePlan))))
    {
        get-azmarketplaceterms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
        $agreementTerms=Get-AzMarketplaceterms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
        Set-AzMarketplaceTerms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name -Terms $agreementTerms -Accept
        $vmConfig = Set-AzVMPlan -VM $vmConfig -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
    }

    $vmConfig = Set-AzVMOperatingSystem -Windows -VM $vmConfig -ComputerName $ComputerName -Credential $LocalAdminUserCredential | `
    Set-AzVMSourceImage -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $productversion

    # Create the VM
    New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $vmConfig
}

# Verify that the vm was created
$vmList = Get-AzVM -ResourceGroupName $resourceGroupName
$vmList.Name
