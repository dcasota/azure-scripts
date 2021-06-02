#
# Deploy the Azure Microsoft Windows 10 20H2 from Image 20h2-evd-o365pp-g2
#
# History
# 0.1  02.06.2021   dcasota  Initial release

# SKU
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/cli-ps-findimage

# Location setting
$LocationName = "switzerlandnorth"

# Resourcegroup setting
$ResourceGroupName = "w10-rg2"

# network setting
$NetworkName = "w10-lab2"

# virtual network and subnets setting
$SubnetAddressPrefix = "192.168.1.0/24"
$VnetAddressPrefix = "192.168.0.0/16"

# VM setting
$VMSize = "Standard_E4s_v3"
$ComputerName = "w10-02"
$VMName = $ComputerName
$NICName = $ComputerName + "nic"
$VMLocalAdminUser = "Local"
$VMLocalAdminPwd="DummyPassword123!"
$disk1SizeGB = "100"
$disk2SizeGB = "75"
$PublicIPDNSName="mypublicdns$(Get-Random)"
$nsgName = "myNetworkSecurityGroup2"
$publisherName = "MicrosoftWindowsDesktop"
$offerName = "office-365"
$skuName = "20h2-evd-o365pp-g2"
$version="19042.928.2104132225"

# check Azure CLI
if (-not ($($env:path).contains("CLI2\wbin")))
{
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
    $env:path="C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin;"+$env:path
}

# check Azure Powershell
if (([string]::IsNullOrEmpty((get-module -name Az* -listavailable)))) {install-module Az -force -ErrorAction SilentlyContinue}

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

# marketplace plan
# be aware first the marketplace terms must be accepted manually. https://github.com/terraform-providers/terraform-provider-azurerm/issues/1145#issuecomment-383070349

# Create a virtual machine configuration
$vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize | Add-AzVMNetworkInterface -Id $nic.Id
if (!(([string]::IsNullOrEmpty($vmConfig))))
{

    $vmConfig = Set-AzVMOperatingSystem -Windows -VM $vmConfig -ComputerName $ComputerName -Credential $LocalAdminUserCredential | `
    # Add-AzVMDataDisk -Name $dataDiskName1 -CreateOption Attach -ManagedDiskId $dataDisk1.Id -Lun 0 | `
    Set-AzVMSourceImage -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $version

    $vmConfig | Set-AzVMBootDiagnostic -Disable

    # Create the VM
    New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $vmConfig

    # Verify that the vm was created
    $vmList = Get-AzVM -ResourceGroupName $resourceGroupName
    $vmList.Name
}




