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
#    ./create-AzVM_FromImage-PhotonOS.ps1 -Location switzerlandnorth -ResourceGroupNameImage photonoslab -ImageName photon-azure-4.0-1526e30ba_V2.vhd -ResourceGroupName ph4lab -VMName Ph4

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
$VMSize = "Standard_B2ms",

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

if ($true -and ($PSEdition -eq 'Core'))
{
    if ($PSVersionTable.PSVersion -lt [Version]'6.2.4')
    {
        throw "Current Az version doesn't support PowerShell Core versions lower than 6.2.4. Please upgrade to PowerShell Core 6.2.4 or higher."
        exit
    }
}

# check Azure CLI user install
if (test-path("$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin"))
{
    $Remove = "$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin"
    $env:Path = ($env:Path.Split(';') | Where-Object -FilterScript {$_ -ne $Remove}) -join ';'
    $env:path="$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin;"+$env:path
}

$version=""
try
{
    $version=az --version 2>$null
    $version=(($version | select-string "azure-cli")[0].ToString().Replace(" ","")).Replace("azure-cli","")
}
catch {}

# Update was introduced in 2.11.0, see https://docs.microsoft.com/en-us/cli/azure/update-azure-cli
if (($version -eq "") -or ($version -lt "2.11.0"))
{
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
    Start-Process msiexec.exe -Wait -ArgumentList "/a AzureCLI.msi /qb TARGETDIR=$env:APPDATA\azure-cli /quiet"
    if (!(test-path("$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin")))
    {
        throw "Azure CLI installation failed."
        exit
    }
    else
    {
        $Remove = "$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin"
        $env:Path = ($env:Path.Split(';') | Where-Object -FilterScript {$_ -ne $Remove}) -join ';'
        $env:path="$env:APPDATA\azure-cli\Microsoft SDKs\Azure\CLI2\wbin;"+$env:path

        $version=az --version 2>$null
        $version=(($version | select-string "azure-cli")[0].ToString().Replace(" ","")).Replace("azure-cli","")
    }
    if (test-path(.\AzureCLI.msi)) {rm .\AzureCLI.msi}
}
if ($version -lt "2.19.1")
{
    az upgrade --yes --all 2>&1 | out-null
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


if (!(Get-variable -name azclilogin -ErrorAction SilentlyContinue))
{
    $azclilogin=az login --use-device-code
}
else
{
    if ([string]::IsNullOrEmpty($azclilogin))
    {
        $azclilogin=az login --use-device-code
    }
}

if (!(Get-variable -name azclilogin -ErrorAction SilentlyContinue))
{
    write-host "Azure CLI login required."
    exit
}

if (!(Get-variable -name azconnect -ErrorAction SilentlyContinue))
{
    $azconnect=connect-azaccount -devicecode
	$AzContext=$null
}
else
{
    if ([string]::IsNullOrEmpty($azconnect))
    {
        $azconnect=connect-azaccount -devicecode
	    $AzContext=$null
    }
}

if (!(Get-variable -name azconnect -ErrorAction SilentlyContinue))
{
    write-host "Azure Powershell login required."
    exit
}

if (!(Get-variable -name AzContext -ErrorAction SilentlyContinue))
{
	$AzContext = Get-AzContext
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
}


#Set the context to the subscription Id where the Azure image exists and where the virtual machine will be created
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
