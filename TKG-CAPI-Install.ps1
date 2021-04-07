#
# Deploy the Azure TKG-CAPI
#
# History
# 0.1  07.04.2021   dcasota  Initial release


# Location setting
$LocationName = "switzerlandnorth"

# Resourcegroup setting
$ResourceGroupName = "tkg-capi-lab"

# Storageaccount
$StorageAccountName ="tkgcapistorage"

# network setting
$NetworkName = "tkgcapilab"

# virtual network and subnets setting
$SubnetAddressPrefix = "192.168.1.0/24"
$VnetAddressPrefix = "192.168.0.0/16"

# VM setting
$VMSize = "Standard_D2s_v3"
$ComputerName = "tkgcapi"
$VMName = $ComputerName
$NICName = $ComputerName + "nic"
$VMLocalAdminUser = "localuser"
$VMLocalAdminPwd="Secure2021123."
$PublicIPDNSName="mypublicdns$(Get-Random)"
$nsgName = "myNetworkSecurityGroup"
$publisherName = "vmware-inc"
$offerName = "tkg-capi"
$skuName = "k8s-1dot20dot4-ubuntu-2004"
$version="2021.03.05"

# https://github.com/Azure/azure-powershell/blob/master/documentation/breaking-changes/breaking-changes-messages-help.md
Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

# Check Windows Powershell environment. Original codesnippet parts from https://www.powershellgallery.com/packages/Az.Accounts/2.2.5/Content/Az.Accounts.psm1
$PSDefaultParameterValues.Clear()
Set-StrictMode -Version Latest

function Test-DotNet
{
    try
    {
        if ((Get-PSDrive 'HKLM' -ErrorAction Ignore) -and (-not (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full\' -ErrorAction Stop | Get-ItemPropertyValue -ErrorAction Stop -Name Release | Where-Object { $_ -ge 461808 })))
        {
            throw ".NET Framework versions lower than 4.7.2 are not supported in Az. Please upgrade to .NET Framework 4.7.2 or higher."
            exit
        }
    }
    catch [System.Management.Automation.DriveNotFoundException]
    {
        Write-Verbose ".NET Framework version check failed."
        exit
    }
}

if ($true -and ($PSEdition -eq 'Desktop'))
{
    if ($PSVersionTable.PSVersion -lt [Version]'5.1')
    {
        throw "PowerShell versions lower than 5.1 are not supported in Az. Please upgrade to PowerShell 5.1 or higher."
        exit
    }
    Test-DotNet
}


# check Azure Powershell
# https://github.com/Azure/azure-powershell/issues/13530
# https://github.com/Azure/azure-powershell/issues/13337
if (!(([string]::IsNullOrEmpty((get-module -name Az.Accounts -listavailable)))))
{
    if ((get-module -name Az.Accounts -listavailable).Version.ToString() -lt "2.2.5") 
    {
        update-module Az -Scope User -RequiredVersion 5.5 -MaximumVersion 5.5 -force -ErrorAction SilentlyContinue
    }
}
else
{
    install-module Az -Scope User -RequiredVersion 5.5 -MaximumVersion 5.5 -force -ErrorAction SilentlyContinue
}


if (!(Get-variable -name azconnect -ErrorAction SilentlyContinue))
{
    $azconnect=connect-azaccount -devicecode
    $azcontext=$null
}

if ([string]::IsNullOrEmpty($azcontext))
{
    $azcontext = get-azcontext
    $ArmToken = [Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate(
    $AzContext.'Account',
    $AzContext.'Environment',
    $AzContext.'Tenant'.'Id',
    $null,
    [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never,
    $null,
    'https://management.azure.com/'
    )
    $tenantId = ($AzContext).Tenant.Id
    $accessToken = (Get-AzAccessToken -ResourceUrl "https://management.core.windows.net/" -TenantId $tenantId).Token
    $subscriptionId=(get-azcontext).Subscription.Id
}

if (!(Get-AzVM -ResourceGroupName $resourceGroupName -name $VMName -ErrorAction SilentlyContinue))
{

    # create lab resource group if it does not exist
    $result = get-azresourcegroup -name $ResourceGroupName -Location $LocationName -ErrorAction SilentlyContinue
    if (([string]::IsNullOrEmpty($result)))
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

    $vnet = get-azvirtualnetwork -name $networkname -ResourceGroupName $resourcegroupname -ErrorAction SilentlyContinue
    if (([string]::IsNullOrEmpty($vnet)))
    {
        $SingleSubnet  = New-AzVirtualNetworkSubnetConfig -Name frontendSubnet -AddressPrefix $SubnetAddressPrefix
        $vnet = New-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -Location $LocationName -AddressPrefix $VnetAddressPrefix -Subnet $SingleSubnet
        $vnet | Set-AzVirtualNetwork
    }


    # networksecurityruleconfig
    $nsg=get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if (([string]::IsNullOrEmpty($nsg)))
    {
        $netRule1 = New-AzNetworkSecurityRuleConfig -Name mynetRule1 -Description "Allow tcp 22" `
        -Access Allow -Protocol Tcp -Direction Inbound -Priority 110 `
        -SourceAddressPrefix Internet -SourcePortRange * `
        -DestinationAddressPrefix * -DestinationPortRange 22
        $netRule2 = New-AzNetworkSecurityRuleConfig -Name mynetRule2 -Description "Allow tcp 6443" `
        -Access Allow -Protocol Tcp -Direction Inbound -Priority 120 `
        -SourceAddressPrefix Internet -SourcePortRange * `
        -DestinationAddressPrefix * -DestinationPortRange 6443
        $nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $LocationName -SecurityRules $netRule1,$netRule2
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

    $vmimage= get-azvmimage -Location $LocationName -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $version
    if (!(([string]::IsNullOrEmpty($vmimage))))
    {
        $vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize | `
        Add-AzVMNetworkInterface -Id $nic.Id

        if (!(([string]::IsNullOrEmpty($vmimage.PurchasePlan))))
        {
            get-azmarketplaceterms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
            $agreementTerms=Get-AzMarketplaceterms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
            Set-AzMarketplaceTerms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name -Terms $agreementTerms -Accept
            $vmConfig = Set-AzVMPlan -VM $vmConfig -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
        }

        $VMLocalAdminSecurePassword = ConvertTo-SecureString $VMLocalAdminPwd -AsPlainText -Force
        $LocalAdminUserCredential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword)

        $vmConfig = Set-AzVMOperatingSystem -Linux -VM $vmConfig -ComputerName $ComputerName -Credential $LocalAdminUserCredential | `
        set-AzVMSourceImage -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $version

        # Create the VM
        New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $vmConfig

        $VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName
        Set-AzVMBootDiagnostic -VM $VM -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName
    }
}

if (Get-AzVM -ResourceGroupName $resourceGroupName -name $VMName -ErrorAction SilentlyContinue)
{
    write-host TKG-CAPI running.
}

