#
# The script creates an Azure VM with installed Node-Red editor from an individual VMware Photon OS Azure Image.
#
# 
# See creation using create-AzImage-PhotonOS.ps1.
#
# History
# 0.1   13.05.2020   dcasota  First release
# 
#
#
# Prerequisites:
#    - Microsoft Powershell, Microsoft Azure Powershell
#    - Azure account
#
# .PARAMETER cred
#   Azure login credential
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
# Parameter VMName
#    Name of the virtual machine to be created
# Parameter VMSize
#    Azure VM size offering
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
#    VM local username
# Parameter VMLocalAdminPwd
#    VM local user password
# Parameter PublicIPDNSName
#    VM public IP DNS name
#
# .EXAMPLE
#    ./create-AzVM_FromImage-PhotonOS.ps1 -cred $(Get-credential -message 'Enter a username and password for Azure login.') -ResourceGroupName photonoslab-rg -Location switzerlandnorth -StorageAccountName photonosaccount -ImageName photon-azure-3.0-9355405.vhd -VMName PhotonOS3.0rev2


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
[string]$ResourceGroupName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$StorageAccountName,

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$ContainerName = "disks",

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ImageName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$VMName,

[Parameter(Mandatory = $false)][ValidateNotNull()]
$VMSize = "Standard_E4s_v3",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$nsgName = "myNetworkSecurityGroup$VMName",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$NetworkName = "w2k19network",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$SubnetAddressPrefix = "192.168.1.0/24",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$VnetAddressPrefix = "192.168.0.0/16",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$ComputerName = $VMName,

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$NICName = $ComputerName + "nic",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$VMLocalAdminUser = "LocalAdminUser",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$VMLocalAdminPwd="Secure2020123!", #12-123 chars

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$PublicIPDNSName="mypublicdns$VMName"
)

# check Azure CLI
if (-not ($($env:path).contains("CLI2\wbin")))
{
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
do {sleep -Milliseconds 1000} until ($((get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).ProvisioningState) -ieq "Succeeded") 
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
	$rdpRule1 = New-AzNetworkSecurityRuleConfig -Name myConsoleRule -Description "Allow Console" `
	-Access Allow -Protocol Tcp -Direction Inbound -Priority 100 `
	-SourceAddressPrefix Internet -SourcePortRange * `
	-DestinationAddressPrefix * -DestinationPortRange 3389
	$rdpRule2 = New-AzNetworkSecurityRuleConfig -Name mySSHRule -Description "Allow SSH" `
	-Access Allow -Protocol Tcp -Direction Inbound -Priority 110 `
	-SourceAddressPrefix Internet -SourcePortRange * `
	-DestinationAddressPrefix * -DestinationPortRange 22
	$rdpRule3 = New-AzNetworkSecurityRuleConfig -Name myNodeRedRule -Description "Allow Node-Red" `
	-Access Allow -Protocol Tcp -Direction Inbound -Priority 120 `
	-SourceAddressPrefix Internet -SourcePortRange * `
	-DestinationAddressPrefix * -DestinationPortRange 1880

	$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $LocationName -SecurityRules $rdpRule1,$rdpRule2,$rdpRule3
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
	
	az vm run-command invoke -g $ResourceGroupName -n $VMName --command-id RunShellScript --scripts "sudo tdnf distro-sync -y && sudo tdnf install -y wget curl glibc-iconv autoconf automake binutils diffutils gcc glib-devel glibc-devel linux-api-headers make ncurses-devel util-linux-devel zlib-devel nodejs && sudo npm install -g --unsafe-perm node-red && sudo /sbin/iptables -A INPUT -p tcp --dport 1880 -j ACCEPT && sudo node-red > /dev/null 2>&1 &"
	
}

