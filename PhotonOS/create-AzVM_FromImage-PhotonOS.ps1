# .SYNOPSIS
#  Provision an Azure virtual machine from a user Azure VMware Photon OS image.
#
# .DESCRIPTION
#  The script provisions an Azure virtual machine by the Azure VMware Photon OS image name and resource group, the vm resource group and the vm name as mandatory parameters.
#  If there is no previously created Azure VMware Photon OS image, do use the Azure Virtual Machine Image builder script create-AzImage-PhotonOS.ps1 to create an image.
#
#  Two kinds of images are supported:
#    - Managed image of a Photon OS Azure vhd, e.g. photon-azure-5.0-dde71ec57.x86_64_V2.vhd. The image already contains the information if it is a HyperVGeneration V1 or V2 image.
#      The vm local admin credential is applied by the Azure provisioning.
#    - Azure Compute Gallery image of a Photon OS iso, e.g. -GalleryName PhotonOS_westeurope -ImageName photon-5.0-dde71ec57.aarch64_iso_V2.
#      The image is specialized and boots the Photon OS installer. Connect with the Azure serial console. An empty data disk is added as installation target.
#      Architecture (x64/Arm64) and HyperVGeneration are read from the image definition.
#
#  The script checks the Az module and triggers an Azure login using the device code method. You get a similar message to
#    WARNUNG: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code xxxxxxxxx to authenticate.
#  The Azure Powershell output shows up as warning (see above). Open a webbrowser, and fill in the code given by the Azure Powershell login output.
#
#  After the login on Azure, it uses the specified location and resource group of the Azure image and provisions the virtual machine.
#  Default Azure vm size is Standard_B1ms for x64 and Standard_D2pls_v5 for Arm64 images. Boot diagnostics use a managed storage account.
#
#  .PREREQUISITES
#    - Script must run on MS Windows OS with Powershell PSVersion 5.1 or higher
#    - Az.Compute 9.0 or higher
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
# 0.7   11.07.2022   dcasota  Bugfixing, substitution of Azure CLI commands with Azure Powershell commands, text changes
# 0.71  12.07.2022   dcasota  Bugfixing
# 0.72  21.07.2022   dcasota  Bugfixing
# 0.73  28.01.2023   dcasota  Bugfixing
# 0.80  14.09.2026   dcasota  Azure Compute Gallery images (Arm64, specialized Photon OS installer images) added, vm size and quota preflight check,
#                             LocationName defaults to the image location, managed boot diagnostics, standard public ip
# 0.81  15.09.2026   dcasota  LocationName accepts display names with spaces (e.g. "UK South") and is normalized to the Azure location name,
#                             the image must be available in that location
#
# .PARAMETER
# Parameter LocationName
#    Azure location name (e.g. uksouth) or display name (e.g. "UK South") where to create or lookup the resource group.
#    Default is the location of the image. The image must be available in that location.
# Parameter ResourceGroupNameImage
#    Azure resource group name of the Azure image or gallery
# Parameter GalleryName
#    Azure Compute Gallery name. If specified, ImageName is the gallery image definition name.
# Parameter ImageVersion
#    Gallery image version. Default is the latest version.
# Parameter RuntimeId
#    Generates a random id used in names
# Parameter ImageName
#    Azure image name, or gallery image definition name
# Parameter ResourceGroupName
#    Azure resource group name of the VM
# Parameter VMName
#    Name of the virtual machine to be created
# Parameter StorageAccountName
#    not used anymore, boot diagnostics use a managed storage account
# Parameter ContainerName
#    not used anymore
# Parameter VMSize
#    Azure virtual machine size offering
# Parameter InstallDiskSizeGB
#    Size of the empty data disk added for specialized installer images
# Parameter nsgName
#    network security group name
# Parameter NetworkName
#    vnet name
# Parameter SubnetAddressPrefix
#    subnet address. Use cidr format, eg. "192.168.0.0/24"
# Parameter VnetAddressPrefix
#    virtual network address. Use cidr format, eg. "192.168.0.0/16"
# Parameter Computername
#    computername
# Parameter NICName
#    virtual network card name
# Parameter PublicIPDNSName
#    virtual machine public IP DNS name
# Parameter VMLocalAdminCredential
#    virtual machine local admin credential. Not used for specialized gallery images.
#
# .EXAMPLE
#    ./create-AzVM_FromImage-PhotonOS.ps1 -Location switzerlandnorth -ResourceGroupNameImage PhotonOSTemplates -ImageName photon-azure-4.0-c001795b8_V2.vhd -ResourceGroupName ph4rev2 -VMName ph01 -VMLocalAdminCredential $(Get-credential -message 'Specify a Photon OS local admin username and password. Password must be 12-23 chars long.')
#    ./create-AzVM_FromImage-PhotonOS.ps1 -ResourceGroupNameImage PhotonOSTemplates -GalleryName PhotonOS_westeurope -ImageName photon-5.0-dde71ec57.aarch64_iso_V2 -ResourceGroupName ph5arm -VMName ph5arm01

[CmdletBinding()]
param(
[Parameter(Mandatory = $false)]
[string]$LocationName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ResourceGroupNameImage,

[Parameter(Mandatory = $false)]
[string]$GalleryName,

[Parameter(Mandatory = $false)]
[string]$ImageVersion,

[Parameter(Mandatory = $false)]
[string]$RuntimeId = (Get-Random).ToString(),

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ImageName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ResourceGroupName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$VMName,

[Parameter(Mandatory = $false)][ValidateLength(3,24)][ValidatePattern("[a-z0-9]")]
[string]$StorageAccountName=("PhotonOS${RuntimeId}").ToLower(),

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$ContainerName = "${RuntimeId}disks",

[Parameter(Mandatory = $false)]
[string]$VMSize,

[Parameter(Mandatory = $false)][ValidateRange(8,1024)]
[int]$InstallDiskSizeGB = 16,

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$nsgName = "${RuntimeId}nsg",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$NetworkName = "${RuntimeId}vnet",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$SubnetAddressPrefix = "192.168.1.0/24",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$VnetAddressPrefix = "192.168.0.0/16",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$ComputerName = $VMName,

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$NICName = "${RuntimeId}nic",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$PublicIPDNSName="${RuntimeId}dns",

[Parameter(Mandatory = $false)]
[System.Management.Automation.PSCredential]
[System.Management.Automation.Credential()]$VMLocalAdminCredential = [System.Management.Automation.PSCredential]::Empty

)

$ErrorActionPreference = 'Stop'

function Get-AzResourceOrNull([scriptblock]$Query)
{
    try { & $Query } catch { $null }
}

function Test-VMCapacity
{
    param([string]$Location, [string]$Size)

    $sku = Get-AzComputeResourceSku -Location $Location | Where-Object { ($_.ResourceType -eq 'virtualMachines') -and ($_.Name -ieq $Size) }
    if (-not $sku) { throw "VM size $Size is not offered in location $Location. Specify another -VMSize." }
    if ($sku.Restrictions | Where-Object { ($_.ReasonCode -eq 'NotAvailableForSubscription') -and ($_.Type -eq 'Location') })
    {
        throw "VM size $Size is restricted for this subscription in location $Location."
    }
    $vCPUs = [int](($sku.Capabilities | Where-Object Name -eq 'vCPUs').Value)
    $usage = Get-AzVMUsage -Location $Location
    foreach ($quota in @(($usage | Where-Object { $_.Name.Value -ieq $sku.Family }), ($usage | Where-Object { $_.Name.Value -ieq 'cores' })))
    {
        if ($quota -and (($quota.Limit - $quota.CurrentValue) -lt $vCPUs))
        {
            throw "Not enough vCPU quota for $Size in ${Location}: $($quota.Name.LocalizedValue) $($quota.CurrentValue)/$($quota.Limit), $vCPUs needed."
        }
    }
    $cpuArchitecture = ($sku.Capabilities | Where-Object Name -eq 'CpuArchitectureType').Value
    if ([string]::IsNullOrEmpty($cpuArchitecture)) { $cpuArchitecture = 'x64' }
    return $cpuArchitecture
}

# Specify Tls
$TLSProtocols = [System.Net.SecurityProtocolType]::'Tls13',[System.Net.SecurityProtocolType]::'Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $TLSProtocols

# Check Azure Powershell
$AzComputeModule = Get-Module -Name Az.Compute -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
if ((-not $AzComputeModule) -or ($AzComputeModule.Version -lt [version]'9.0.0'))
{
    write-output "Az.Compute 9.0 or higher is required (Azure Compute Gallery and Arm64 support)."
    write-output "Install it with: Install-Module -Name Az -Force -AllowClobber, and restart the Powershell session."
    return
}

$azconnect=$null
try
{
    # Already logged-in?
    $subscriptionId=(get-azcontext).Subscription.Id
    $TenantId=(get-azcontext).Tenant.Id
    # set subscription
    $null = select-AzSubscription -Subscription $subscriptionId -tenant $TenantId -ErrorAction Stop
    $azconnect=get-azcontext -ErrorAction SilentlyContinue
}
catch {}
if ([Object]::ReferenceEquals($azconnect,$null))
{
    try
    {
        $azconnect=connect-azaccount -devicecode
        $subscriptionId=(get-azcontext).Subscription.Id
        $TenantId=(get-azcontext).Tenant.Id
        # set subscription
        $null = select-AzSubscription -Subscription $subscriptionId -tenant $TenantId -ErrorAction Stop
    }
    catch
    {
        write-output "Azure Powershell login required."
        return
    }
}

# Verify virtual machine doesn't exist
if (Get-AzResourceOrNull { Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName })
{
	write-output "VM $VMName already exists."
	return
}

# Verify if image exists
if ([string]::IsNullOrEmpty($GalleryName))
{
    $image = Get-AzResourceOrNull { Get-AzImage -ResourceGroupName $ResourceGroupNameImage -ImageName $ImageName }
    if (-not $image)
    {
        write-output "Could not find Azure image $ImageName on resourcegroup $ResourceGroupNameImage."
        return
    }
    $ImageId = $image.Id
    $ImageLocation = $image.Location
    $ImageRegions = @($image.Location)
    $ImageArchitecture = 'x64'
    $IsSpecialized = $false
}
else
{
    $definition = Get-AzResourceOrNull { Get-AzGalleryImageDefinition -ResourceGroupName $ResourceGroupNameImage -GalleryName $GalleryName -Name $ImageName }
    if (-not $definition)
    {
        write-output "Could not find image definition $ImageName in gallery $GalleryName on resourcegroup $ResourceGroupNameImage."
        return
    }
    if ([string]::IsNullOrEmpty($ImageVersion))
    {
        # the image definition id deploys the latest image version
        $ImageId = $definition.Id
    }
    else
    {
        $version = Get-AzResourceOrNull { Get-AzGalleryImageVersion -ResourceGroupName $ResourceGroupNameImage -GalleryName $GalleryName -GalleryImageDefinitionName $ImageName -Name $ImageVersion }
        if (-not $version)
        {
            write-output "Could not find version $ImageVersion of image definition $ImageName in gallery $GalleryName."
            return
        }
        $ImageId = $version.Id
    }
    # regions the image version(s) are replicated to, e.g. "West Europe"
    if ($version) { $versions = @($version) } else { $versions = @(Get-AzResourceOrNull { Get-AzGalleryImageVersion -ResourceGroupName $ResourceGroupNameImage -GalleryName $GalleryName -GalleryImageDefinitionName $ImageName }) | Where-Object { $_ } }
    if (-not $versions)
    {
        write-output "Image definition $ImageName in gallery $GalleryName has no image version."
        return
    }
    $ImageRegions = @($versions | ForEach-Object { $_.PublishingProfile.TargetRegions.Name })
    $ImageLocation = $definition.Location
    if ([string]::IsNullOrEmpty($definition.Architecture)) { $ImageArchitecture = 'x64' } else { $ImageArchitecture = $definition.Architecture }
    $IsSpecialized = ($definition.OsState -ieq 'Specialized')
}

# Location: the Azure location name (e.g. uksouth) or its display name (e.g. "UK South") is normalized to the location name
$azLocations = Get-AzLocation
function ConvertTo-AzLocationName([string]$Name)
{
    ($azLocations | Where-Object { ($_.Location -ieq $Name) -or ($_.DisplayName -ieq $Name) -or ($_.Location -ieq ($Name -replace '\s', '')) } | Select-Object -First 1).Location
}
if ([string]::IsNullOrEmpty($LocationName)) { $LocationName = $ImageLocation }
$normalizedLocation = ConvertTo-AzLocationName $LocationName
if (-not $normalizedLocation) { throw "Location '$LocationName' is unknown. Use an Azure location name like westeurope, switzerlandnorth or uksouth (see Get-AzLocation)." }
if ($normalizedLocation -cne $LocationName) { write-output "Location '$LocationName' is used as $normalizedLocation." }
$LocationName = $normalizedLocation

# The image must be available in the VM location
$ImageRegions = @($ImageRegions | ForEach-Object { ConvertTo-AzLocationName $_ } | Where-Object { $_ } | Select-Object -Unique)
if ($ImageRegions -and ($ImageRegions -notcontains $LocationName))
{
    throw "Image $ImageName is not available in $LocationName, only in: $($ImageRegions -join ', '). Specify -LocationName accordingly or replicate the image."
}
if ([string]::IsNullOrEmpty($VMSize))
{
    if ($ImageArchitecture -eq 'Arm64') { $VMSize = 'Standard_D2pls_v5' } else { $VMSize = 'Standard_B1ms' }
}

$VMSizeArchitecture = Test-VMCapacity -Location $LocationName -Size $VMSize
if ($VMSizeArchitecture -ne $ImageArchitecture)
{
    throw "VM size $VMSize is $VMSizeArchitecture, but image $ImageName is $ImageArchitecture."
}

if ((-not $IsSpecialized) -and ($VMLocalAdminCredential -eq [System.Management.Automation.PSCredential]::Empty))
{
    $VMLocalAdminCredential = Get-credential -Message 'Specify a Photon OS local admin username and password. Username must be all in small letters. Password must be 12-23 chars long.'
}

# create resource group if it does not exist
if (-not (Get-AzResourceOrNull { Get-AzResourceGroup -Name $ResourceGroupName }))
{
    $null = New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName
}

# network security rules configuration
$nsg = Get-AzResourceOrNull { Get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName }
if ( -not $($nsg))
{
	$nsgRule1 = New-AzNetworkSecurityRuleConfig -Name nsgRule1 -Description "Allow SSH" `
	-Access Allow -Protocol Tcp -Direction Inbound -Priority 100 `
	-SourceAddressPrefix Internet -SourcePortRange * `
	-DestinationAddressPrefix * -DestinationPortRange 22
	$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $LocationName -SecurityRules $nsgRule1
}

# set network if not already set
$vnet = Get-AzResourceOrNull { Get-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName }
if ( -not $($vnet))
{
    $ServerSubnet  = New-AzVirtualNetworkSubnetConfig -Name frontendSubnet  -AddressPrefix $SubnetAddressPrefix -NetworkSecurityGroup $nsg
	$vnet = New-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -Location $LocationName -AddressPrefix $VnetAddressPrefix -Subnet $ServerSubnet
}

# Create a public IP address
$nic = Get-AzResourceOrNull { Get-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName }
if ( -not $($nic))
{
	$pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $LocationName -Name $PublicIPDNSName -AllocationMethod Static -Sku Standard -IdleTimeoutInMinutes 4
	# Create a virtual network interface and associate it with public IP address and NSG
	$nic = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName `
		-SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id
}

# create virtual machine
$VM = New-AzVMConfig -VMName $VMName -VMSize $VMSize
if ($IsSpecialized)
{
    # no OS profile: the Photon OS installer image has no Azure provisioning agent.
    # Without OS profile New-AzVM assumes Windows and adds the BGInfo extension, which waits for a VM agent forever.
    $VM = Set-AzVMOSDisk -VM $VM -CreateOption FromImage -Linux
    $VM = Add-AzVMDataDisk -VM $VM -Name "${VMName}_installdisk" -Lun 0 -CreateOption Empty -DiskSizeInGB $InstallDiskSizeGB
}
else
{
    $VM = Set-AzVMOperatingSystem -VM $VM -Linux -ComputerName $ComputerName -Credential $VMLocalAdminCredential
}
$VM = Add-AzVMNetworkInterface -VM $VM -Id $nic.Id
$VM = Set-AzVMSourceImage -VM $VM -Id $ImageId
$VM = Set-AzVMBootDiagnostic -VM $VM -Enable

New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $VM -DisableBginfoExtension

$VM = Get-AzResourceOrNull { Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName }
if (!($VM))
{
	write-Output "Error: Virtual machine hasn't been created."
	return
}
if ($IsSpecialized)
{
    write-output "VM $VMName boots the Photon OS installer. Open the Azure serial console of the VM to proceed with the installation onto disk ${VMName}_installdisk."
}
