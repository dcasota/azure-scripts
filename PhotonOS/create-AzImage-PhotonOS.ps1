# .SYNOPSIS
#  Deploy an Azure image of VMware Photon OS
#
# .DESCRIPTION
#  The script creates an Azure image of VMware Photon OS by vhd download url, the location and the resource group name as mandatory parameters.
#  Without specifying further parameters, an Azure image HyperVGeneration V2 of VMware Photon OS 4.0 rev2 is created.
#  The name of the Azure image is adopted from the vhd download url and the HyperVGeneration ending _V1.vhd or _V2.vhd. It looks like "photon-azure-4.0-c001795b8_V2.vhd".
#
#  First the script installs the Az 8.0 module if necessary and triggers an Azure login using the device code method. You get a similar message to
#    WARNUNG: To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code xxxxxxxxx to authenticate.
#  The Azure Powershell output shows up as warning (see above). Open a webbrowser, and fill in the code given by the Azure Powershell login output.
#
#  A temporary Azure windows virtual machine is created with Microsoft Windows Server 2022 on a specifiable Hyper-V generation virtual hardware V1/V2 using the Azure offering Standard_E4s_v3.
#  See Azure virtual hardware generation related weblink https://docs.microsoft.com/en-us/azure/virtual-machines/windows/generation-2
#  After uploading the extracted VMware Photon OS release vhd file as Azure page blob, the Azure Photon OS image is created. The cleanup deletes the temporary virtual machine.
#
#  .PREREQUISITES
#    - Script must run on MS Windows OS with Powershell PSVersion 5.1 or higher
#    - Azure account with Virtual Machine contributor role
#
#
# .NOTES
#   Author:  Daniel Casota
#   Version:
#   0.1   16.02.2020   dcasota  First release
#   0.2   24.02.2020   dcasota  Minor bugfixes, new param HyperVGeneration
#   0.3   23.04.2020   dcasota  Minor bugfixes image name processing and nsg cleanup
#   0.4   24.06.2020   dcasota  Bugfix extract .vhd.gz file
#   0.5   08.07.2020   dcasota  ValidateLength and ValidatePattern added
#   0.6   19.09.2020   dcasota  check administrative privileges
#   0.7   18.11.2020   dcasota  Photon OS 4.0 Beta Azure Vhd added
#   0.8   29.11.2020   dcasota  fix login issue https://github.com/Azure/azure-powershell/issues/13337
#   0.9   01.03.2021   dcasota  download URLs updated. Scheduled runas as localadminuser fixed.
#   0.91  02.03.2021   dcasota  comment fix
#   0.92  21.03.2021   dcasota  bugfix photon 2.0 processing
#   0.93  07.04.2021   dcasota  Changed naming of DownloadURL, bugfixing
#   0.94  08.04.2021   dcasota  code description added
#   1.00  13.10.2021   dcasota  Photon OS 4.0 Rev1 Azure Vhd added
#   1.01  08.11.2021   dcasota  Enforced Azure powershell + cli version update, temp vm scheduled task bug fix
#   1.10  15.06.2022   dcasota  Bugfixing, substitution of Azure CLI commands with Azure Powershell commands, latest Photon OS release added
#   1.11  11.07.2022   dcasota  text changes
#   1.12  17.08.2022   dcasota  bugfixing
#
# .PARAMETER DownloadURL
#   Specifies the URL of the VMware Photon OS .vhd.tar.gz file
#      VMware Photon OS build download links:
#        Photon OS 4.0 Rev2 Azure VHD                        https://packages.vmware.com/photon/4.0/Rev2/azure/photon-azure-4.0-c001795b8.vhd.tar.gz
#        Photon OS 4.0 Rev1 Azure VHD                        https://packages.vmware.com/photon/4.0/Rev1/azure/photon-azure-4.0-ca7c9e933.vhd.tar.gz
#        Photon OS 4.0 GA Azure VHD                          https://packages.vmware.com/photon/4.0/GA/azure/photon-azure-4.0-1526e30ba.vhd.tar.gz
#        Photon OS 4.0 RC Azure VHD                          https://packages.vmware.com/photon/4.0/RC/azure/photon-azure-4.0-a3a49f540.vhd.tar.gz
#        Photon OS 4.0 Beta Azure VHD                        https://packages.vmware.com/photon/4.0/Beta/azure/photon-azure-4.0-d98e681.vhd.tar.gz
#        Photon OS 3.0 Revision 2 Azure VHD                  https://packages.vmware.com/photon/3.0/Rev2/azure/photon-azure-3.0-9355405.vhd.tar.gz
#        Photon OS 3.0 GA Azure VHD                          https://packages.vmware.com/photon/3.0/GA/azure/photon-azure-3.0-26156e2.vhd.tar.gz
#        Photon OS 3.0 RC Azure VHD                          https://packages.vmware.com/photon/3.0/RC/azure/photon-azure-3.0-49fd219.vhd.tar.gz
#        Photon OS 3.0 Beta                                  https://packages.vmware.com/photon/3.0/Beta/azure/photon-azure-3.0-5e45dc9.vhd.tar.gz
#        Photon OS 2.0 GA Azure VHD gz file:                 https://packatares.vmware.com/photon/2.0/GA/azure/photon-azure-2.0-304b817.vhd.gz
#        Photon OS 2.0 GA Azure VHD cloud-init provisioning  https://packages.vmware.com/photon/2.0/GA/azure/photon-azure-2.0-3146fa6.tar.gz
#        Photon OS 2.0 RC Azure VHD - gz file                https://packages.vmware.com/photon/2.0/RC/azure/photon-azure-2.0-31bb961.vhd.gz
#        Photon OS 2.0 Beta Azure VHD                        https://packages.vmware.com/photon/2.0/Beta/azure/photon-azure-2.0-8553d58.vhd
# .PARAMETER LocationName
#   Azure location name where to create or lookup the resource group
# .PARAMETER ResourceGroupName
#   resource group name
# .PARAMETER RuntimeId
#   random id used in names
# .PARAMETER StorageAccountName
#   storage account name
# .PARAMETER StorageKind
#   storage kind
# .PARAMETER StorageAccountType
#   storage account type
# .PARAMETER HyperVGeneration
#   Azure HyperVGeneration
# .PARAMETER Imagename
#   image name
# .PARAMETER HelperVMComputerName
#   helper vm computername
# .PARAMETER HelperVMName
#   helper vm name
# .PARAMETER HelperVMContainerName
#   helper vm container name
# .PARAMETER HelperVMDiskName
#   helper vm disk name
# .PARAMETER HelperVMPublishername
#   helper vm os publishername
# .PARAMETER HelperVMOffername
#   helper vm os offername
# .PARAMETER HelperVMSku
#   helper vm os sku
# .PARAMETER HelperVMSize
#   helper vm size
# .PARAMETER HelperVMNetworkName
#   helper vm network name
# .PARAMETER HelperVMSubnetAddressPrefix
#   helper vm subnet address prefix
# .PARAMETER HelperVMVNetAddressPrefix
#   helper vm vnet address prefix
# .PARAMETER HelperVMnsgName
#   helper vm nsg name
# .PARAMETER HelperVMPublicIPDNSName
#   helper vm public ip dns name
# .PARAMETER HelperVMNicName
#   helper vm nic name
# .PARAMETER HelperVMLocalAdminUser
#   helper vm local admin user
# .PARAMETER HelperVMLocalAdminPwd
#   helper vm local admin pwd
# .PARAMETER HelperVMsize_TempPath
#   helper vm size temp path
#
# .EXAMPLE
#    ./create-AzImage-PhotonOS.ps1 -DownloadURL "https://packages.vmware.com/photon/4.0/Rev2/azure/photon-azure-4.0-c001795b8.vhd.tar.gz" -ResourceGroupName PhotonOSTemplates -LocationName switzerlandnorth -HyperVGeneration V2
#
#>

[CmdletBinding()]
param(
[Parameter(Mandatory = $true)][ValidateNotNull()]
[ValidateSet(`
'https://packages.vmware.com/photon/4.0/Rev2/azure/photon-azure-4.0-c001795b8.vhd.tar.gz', `
'https://packages.vmware.com/photon/4.0/Rev1/azure/photon-azure-4.0-ca7c9e933.vhd.tar.gz', `
'https://packages.vmware.com/photon/4.0/GA/azure/photon-azure-4.0-1526e30ba.vhd.tar.gz', `
'https://packages.vmware.com/photon/4.0/RC/azure/photon-azure-4.0-a3a49f540.vhd.tar.gz', `
'https://packages.vmware.com/photon/4.0/Beta/azure/photon-azure-4.0-d98e681.vhd.tar.gz', `
'https://packages.vmware.com/photon/3.0/Rev2/azure/photon-azure-3.0-9355405.vhd.tar.gz', `
'https://packages.vmware.com/photon/3.0/GA/azure/photon-azure-3.0-26156e2.vhd.tar.gz', `
'https://packages.vmware.com/photon/3.0/RC/azure/photon-azure-3.0-49fd219.vhd.tar.gz', `
'https://packages.vmware.com/photon/3.0/Beta/azure/photon-azure-3.0-5e45dc9.vhd.tar.gz', `
'https://packages.vmware.com/photon/2.0/GA/azure/photon-azure-2.0-304b817.vhd.gz', `
'https://packages.vmware.com/photon/2.0/GA/azure/photon-azure-2.0-3146fa6.tar.gz', `
'https://packages.vmware.com/photon/2.0/RC/azure/photon-azure-2.0-31bb961.vhd.gz', `
'https://packages.vmware.com/photon/2.0/Beta/azure/photon-azure-2.0-8553d58.vhd')]
[String]$DownloadURL="https://packages.vmware.com/photon/4.0/Rev2/azure/photon-azure-4.0-c001795b8.vhd.tar.gz",

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$LocationName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ResourceGroupName,

[Parameter(Mandatory = $false)]
[string]$RuntimeId = (Get-Random).ToString(),

[Parameter(Mandatory = $false)][ValidateLength(3,24)][ValidatePattern("[a-z0-9]")]
[string]$StorageAccountName=("PhotonOS${RuntimeId}").ToLower(),

[Parameter(Mandatory = $false)]
[string]$StorageKind="Storage",

[Parameter(Mandatory = $false)]
[string]$StorageAccountType="Standard_LRS",

[Parameter(Mandatory = $false)][ValidateSet('V1','V2')]
[string]$HyperVGeneration="V2",

[Parameter(Mandatory = $false)]
[string]$ImageName=$(((split-path -path $([Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null;[System.Web.HttpUtility]::UrlDecode($DownloadURL)) -Leaf) -split ".vhd")[0] + "_" + $HyperVGeneration + ".vhd"),

[Parameter(Mandatory = $false)]
[string]$HelperVMComputerName = "w2k22${RuntimeId}",

[Parameter(Mandatory = $false)]
[string]$HelperVMName = $HelperVMComputerName,

[Parameter(Mandatory = $false)]
[string]$HelperVMContainerName = "${HelperVMComputerName}disks",

[Parameter(Mandatory = $false)]
[string]$HelperVMDiskName="${HelperVMComputerName}PhotonOSDisk",

[Parameter(Mandatory = $false)]
[string]$HelperVMPublisherName = "MicrosoftWindowsServer",

[Parameter(Mandatory = $false)]
[string]$HelperVMofferName = "WindowsServer",

[Parameter(Mandatory = $false)]
[string]$HelperVMsku = "2022-datacenter-core-smalldisk-g2",

[Parameter(Mandatory = $false)]
[string]$HelperVMsize="Standard_E4s_v3", # This default virtual machine size offering includes a d: drive with 60GB non-persistent capacity

[Parameter(Mandatory = $false)]
[string]$HelperVMNetworkName = "${HelperVMComputerName}vnet",

[Parameter(Mandatory = $false)]
[string]$HelperVMSubnetAddressPrefix = "192.168.1.0/24",

[Parameter(Mandatory = $false)]
[string]$HelperVMVnetAddressPrefix = "192.168.0.0/16",

[Parameter(Mandatory = $false)]
[string]$HelperVMnsgName = "${HelperVMComputerName}nsg",

[Parameter(Mandatory = $false)]
[string]$HelperVMPublicIPDNSName="${HelperVMComputerName}dns",

[Parameter(Mandatory = $false)]
[string]$HelperVMNICName = "${HelperVMComputerName}nic",

[Parameter(Mandatory = $false)]
[string]$HelperVMLocalAdminUser = "LocalAdminUser",

[Parameter(Mandatory = $false)][ValidateLength(12,123)]
[string]$HelperVMLocalAdminPwd="Secure2020123!", #12-123 chars

[Parameter(Mandatory = $false)]
[string]$HelperVMsize_TempPath="d:" # $DownloadURL file is downloaded and extracted on this drive inside vm. Depending of the VMSize offer, it includes built-in an additional non persistent  drive.
)


# Specify Tls
$TLSProtocols = [System.Net.SecurityProtocolType]::'Tls13',[System.Net.SecurityProtocolType]::'Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $TLSProtocols

# Check Azure Powershell
try
{
	# $version = (get-installedmodule -name Az).version # really slow
    $version = (get-command get-azcontext).Version.ToString()
	if ($version -lt "2.8")
	{
		write-output "Updating Azure Powershell ..."	
		update-module -Name Az -RequiredVersion "8.0" -ErrorAction SilentlyContinue
		write-output "Please restart Powershell session."
		break			
	}
}
catch
{
    write-output "Installing Azure Powershell ..."
    install-module -Name Az -RequiredVersion "8.0" -ErrorAction SilentlyContinue
    write-output "Please restart Powershell session."
    break	
}

$azconnect=$null
try
{
    # Already logged-in?
    $subscriptionId=(get-azcontext).Subscription.Id
    $TenantId=(get-azcontext).Tenant.Id
    # set subscription
    select-AzSubscription -Subscription $subscriptionId -tenant $TenantId -ErrorAction Stop
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
        select-AzSubscription -Subscription $subscriptionId -tenant $TenantId -ErrorAction Stop
    }
    catch
    {
        write-output "Azure Powershell login required."
        break
    }
}


# Uri + Blobname
$Uri=$([Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null;[System.Web.HttpUtility]::UrlDecode($DownloadURL))
$BlobName=((split-path -path $Uri -Leaf) -split ".vhd")[0] + ".vhd"

# save credentials
$contextfile=$($env:public) + [IO.Path]::DirectorySeparatorChar + "azcontext.txt"
Save-AzContext -Path $contextfile -Force

$Scriptrun=
@'

# The core concept of this script is:
#   1) Download and extract the Photon OS bits from download url
#   2) do a blob upload of the extracted vhd file
# There are several culprits:
#   A) The script is started in localsystem account. In LocalSystem context there is no possibility to connect outside.
#      Hence, the script creates a run once scheduled task with user impersonation and executing the downloaded powershell script.
#      There are some hacks in localsystem context to make a run-once-scheduled task with user logon type.
#   B) Portion of the script uses Azure Powershell.

$RootDrive=(get-item $tmppath).Root.Name
$tmpfilename=split-path -path $Uri -Leaf
$tmpname=($tmpfilename -split ".vhd")[0] + ".vhd"
$vhdfile=$tmppath + [io.path]::DirectorySeparatorChar+$tmpname
$downloadfile=$tmppath + [io.path]::DirectorySeparatorChar+$tmpfilename
$IsVhdUploaded=$env:public + [IO.Path]::DirectorySeparatorChar + "VhdUploaded.txt"

if ($env:username -ine $HelperVMLocalAdminUser)
{
    $filetostart=$MyInvocation.MyCommand.Source
    # $LocalUser=$env:computername + "\" + $HelperVMLocalAdminUser
    $LocalUser=$HelperVMLocalAdminUser

	$PowershellFilePath =  "$PsHome\powershell.exe"
    $Taskname = "PhotonProcessing"
	$Argument = "\"""+$PowershellFilePath +"\"" -WindowStyle Hidden -NoLogo -NoProfile -Executionpolicy unrestricted -command \"""+$filetostart+"\"""

    # Scheduled task run takes time.
    $timeout=3600

    $i=0
    $rc=0
    do
    {
        $i++
        try
        {
            if ($rc -eq 0)
            {
                schtasks.exe /create /F /TN "$Taskname" /tr $Argument /SC ONCE /ST 00:00 /RU ${LocalUser} /RP ${HelperVMLocalAdminPwd} /RL HIGHEST /NP
                start-sleep -s 1
                schtasks /Run /TN "$Taskname" /I
                start-sleep -s 1
                $rc=1
            }
            if ($rc -eq 1)
            {
                start-sleep -s 1
                $i++
            }
        }
        catch {}
    }
    until ((test-path(${IsVhdUploaded})) -or ($i -gt $timeout))
    exit
}



$orgfile=$($env:public) + [IO.Path]::DirectorySeparatorChar + "azcontext.txt"
$fileencoded=$($env:public) + [IO.Path]::DirectorySeparatorChar + "azcontext_encoded.txt"
if ((test-path($fileencoded)) -eq $false)
{
	out-file -inputobject $CachedAzContext -FilePath $fileencoded
	if ((test-path($orgfile)) -eq $true) {remove-item -path ($orgfile) -force}
	certutil -decode $fileencoded $orgfile
	if ((test-path($orgfile)) -eq $true)
    {
        import-azcontext -path $orgfile
        remove-item -path ($fileencoded) -force
        remove-item -path ($orgfile) -force
    }
}

if (Test-Path -d $tmppath)
{
    if (!(Test-Path $downloadfile))
    {
        cd $tmppath
        $RootDrive="'"+$(split-path -path $tmppath -Qualifier)+"'"
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID=$RootDrive" | select-object @{Name="FreeGB";Expression={[math]::Round($_.Freespace/1GB,2)}}
        if ($disk.FreeGB -gt 35)
        {
            if (!(Test-Path $vhdfile))
            {
                # Invoke-WebRequest $Uri -OutFile $tmpfilename
                c:\windows\system32\curl.exe -J -O -L $Uri
            }
            if ((Test-Path $downloadfile) -and ((([IO.Path]::GetExtension($tmpfilename)) -ieq ".gz")))
            {
                try
                {
                    $PatchCheck=$tmppath + [io.path]::DirectorySeparatorChar+"photon-azure-3.0-49fd219.vhd.tar.gz"
                    if ($downloadfile -ieq $PatchCheck)
                    {
                         $PatchDir = $tmppath + [io.path]::DirectorySeparatorChar+ "root" + [io.path]::DirectorySeparatorChar+ "photon" + [io.path]::DirectorySeparatorChar+ "stage" + [io.path]::DirectorySeparatorChar+ "azure"
                         mkdir $PatchDir
                         $vhdfile=$PatchDir + [io.path]::DirectorySeparatorChar+$tmpname
                    }
                    c:\windows\system32\tar.exe -xzvf $downloadfile
                }
                catch{}
                if (!(Test-Path $vhdfile))
                {
                        # Windows tar does not extract photon-azure-2.0-304b817.vhd.gz but PS7Zip does.
                        install-module PS7Zip -force
                        # work directory must be path of $tmpfilename
                        Expand-7Zip -FullName $tmpfilename -destinationpath $tmpname
                        # vhdfile should now be unextracted into directory $tmpname
                        $vhdfile=$tmppath + [io.path]::DirectorySeparatorChar+$tmpname + [io.path]::DirectorySeparatorChar + $tmpname
                }
            }
        }
    }
}

if (Test-Path $vhdfile)
{
	# Azure login
	$azcontext=get-azcontext
	if ($azcontext)
	{
		$result = get-azresourcegroup -name $ResourceGroupName -Location $LocationName -ErrorAction SilentlyContinue
		if ($result)
		{
			$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
			if ($storageaccount)
			{
                $result=get-azstoragecontainer -Name ${HelperVMContainerName} -Context $storageaccount.Context -ErrorAction SilentlyContinue
                if ($result)
				{
                    $result=get-azstorageblob -Container ${HelperVMContainerName} -Blob ${ImageName} -Context $storageaccount.Context -ErrorAction SilentlyContinue
                    if ( -not ($result))
					{
                        Set-AzStorageBlobContent -Container ${HelperVMContainerName} -File $vhdfile -Blob ${ImageName} -BlobType page -Context $storageaccount.Context
					}
                    $result=get-azstorageblob -Container ${HelperVMContainerName} -Blob ${ImageName} -Context $storageaccount.Context -ErrorAction SilentlyContinue
                    if ($result)
					{
                        $vhdfile | out-file -filepath $IsVhdUploaded -append
                    }
				}
			}
		}
	}
}
'@

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
	$storageaccount=New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $LocationName -Kind $StorageKind -SkuName $StorageAccountType -ErrorAction SilentlyContinue
	if ( -not $($storageaccount))
    {
        write-output "Storage account has not been created. Check if the name is already taken."
        break
    }
}
do {start-sleep -Milliseconds 1000} until ($((get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).ProvisioningState) -ieq "Succeeded")
$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)
$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue


$result=get-azstoragecontainer -Name ${HelperVMContainerName} -Context $storageaccount.Context -ErrorAction SilentlyContinue
if ( -not $($result))
{
    new-azstoragecontainer -Name ${HelperVMContainerName} -Context $storageaccount.Context -ErrorAction SilentlyContinue -Permission Blob
}

$Disk = Get-AzDisk | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.location -ieq $LocationName) -and ($_.Name -ieq $HelperVMDiskName)}
if (-not $($Disk))
{
	# a temporary virtual machine is necessary because inside it downloads Photon and uploads the extracted disk as image base.

	[Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HelperVMName -ErrorAction SilentlyContinue
	if (-not ($VM))
	{
    	# networksecurityruleconfig
    	$nsg=get-AzNetworkSecurityGroup -Name $HelperVMnsgName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    	if ( -not $($nsg))
    	{
    		$rdpRule1 = New-AzNetworkSecurityRuleConfig -Name myRdpRule -Description "Allow RDP" `
    		-Access Allow -Protocol Tcp -Direction Inbound -Priority 110 `
    		-SourceAddressPrefix Internet -SourcePortRange * `
    		-DestinationAddressPrefix * -DestinationPortRange 3389
    		$nsg = New-AzNetworkSecurityGroup -Name $HelperVMnsgName -ResourceGroupName $ResourceGroupName -Location $LocationName -SecurityRules $rdpRule1
    	}

    	# set network if not already set
    	$vnet = get-azvirtualnetwork -name $HelperVMNetworkName -ResourceGroupName $resourcegroupname -ErrorAction SilentlyContinue
    	if ( -not $($vnet))
    	{
    		$ServerSubnet  = New-AzVirtualNetworkSubnetConfig -Name frontendSubnet -AddressPrefix $HelperVMSubnetAddressPrefix -NetworkSecurityGroup $nsg
    		$vnet = New-AzVirtualNetwork -Name $HelperVMNetworkName -ResourceGroupName $ResourceGroupName -Location $LocationName -AddressPrefix $HelperVMVnetAddressPrefix -Subnet $ServerSubnet
    		$vnet | Set-AzVirtualNetwork
    	}

		# create the temporary virtual machine

		# virtual machine local admin setting
		$VMLocalAdminSecurePassword = ConvertTo-SecureString $HelperVMLocalAdminPwd -AsPlainText -Force
		$LocalAdminUserCredential = New-Object System.Management.Automation.PSCredential ($HelperVMLocalAdminUser, $VMLocalAdminSecurePassword)

		# Create a public IP address
		$nic=get-AzNetworkInterface -Name $HelperVMNICName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
		if ( -not $($nic))
		{
			$pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $LocationName -Name $HelperVMPublicIPDNSName -AllocationMethod Static -IdleTimeoutInMinutes 4
			# Create a virtual network card and associate with public IP address and NSG
			$nic = New-AzNetworkInterface -Name $HelperVMNICName -ResourceGroupName $ResourceGroupName -Location $LocationName `
				-SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id
		}

		# Create a virtual machine configuration
		$vmConfig = New-AzVMConfig -VMName $HelperVMName -VMSize $HelperVMsize | `
		Add-AzVMNetworkInterface -Id $nic.Id

        # Get-AzVMImage -Location switzerlandnorth -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2019-datacenter-with-containers-smalldisk-g2
        $productversion=((get-azvmimage -Location $LocationName -PublisherName $HelperVMPublisherName -Offer $HelperVMofferName -Skus $HelperVMsku)[(get-azvmimage -Location $LocationName -PublisherName $HelperVMPublisherName -Offer $HelperVMofferName -Skus $HelperVMsku).count -1 ]).version

		$vmimage= get-azvmimage -Location $LocationName -PublisherName $HelperVMPublisherName -Offer $HelperVMofferName -Skus $HelperVMsku -Version $productversion
		if (-not ([Object]::ReferenceEquals($vmimage,$null)))
		{
			if (-not ([Object]::ReferenceEquals($vmimage.PurchasePlan,$null)))
			{
				$agreementTerms=Get-AzMarketplaceterms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
				Set-AzMarketplaceTerms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name -Terms $agreementTerms -Accept
				$agreementTerms=Get-AzMarketplaceterms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
				Set-AzMarketplaceTerms -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name -Terms $agreementTerms -Accept
				$vmConfig = Set-AzVMPlan -VM $vmConfig -publisher $vmimage.PurchasePlan.publisher -Product $vmimage.PurchasePlan.product -name $vmimage.PurchasePlan.name
			}

			$vmConfig = Set-AzVMOperatingSystem -Windows -VM $vmConfig -ComputerName $HelperVMComputerName -Credential $LocalAdminUserCredential | `
			Set-AzVMSourceImage -PublisherName $HelperVMPublisherName -Offer $HelperVMofferName -Skus $HelperVMsku -Version $productversion		
			$vmConfig | Set-AzVMBootDiagnostic -Disable

			# Create the virtual machine		
			New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $vmConfig
			
			$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HelperVMName			
			Set-AzVMBootDiagnostic -VM $VM -Enable -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName			
		}
	}

    $objBlob=get-azstorageblob -Container $HelperVMContainerName -Blob $BlobName -Context $storageaccount.Context -ErrorAction SilentlyContinue
	$objVM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HelperVMName -status -ErrorAction SilentlyContinue
	if ((-not ([Object]::ReferenceEquals($objVM,$null))) -and (!($objBlob)))
	{
		# Prepare scriptfile
		$contextfileEncoded=$($env:public) + [IO.Path]::DirectorySeparatorChar + "azcontext_enc.txt"
		if ((test-path($contextfileEncoded)) -eq $true) {remove-item -path ($contextfileEncoded) -force}
		certutil -encode $contextfile $contextfileEncoded
		$content = get-content -path $contextfileEncoded
		$ScriptFile = $($env:public) + [IO.Path]::DirectorySeparatorChar + "importazcontext.ps1"
		$value = '$CachedAzContext=@'+"'`r`n"
		# https://stackoverflow.com/questions/42407136/difference-between-redirection-to-null-and-out-null
		$null = new-item $ScriptFile -type file -force -value $value
		out-file -inputobject $content -FilePath $ScriptFile -Encoding ASCII -Append
		out-file -inputobject "'@" -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$Uri="'+$Uri+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$tmppath="'+$HelperVMsize_TempPath+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$tenant="'+$((get-azcontext).tenant.id)+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$ResourceGroupName="'+$ResourceGroupName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$LocationName="'+$LocationName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$StorageAccountName="'+$StorageAccountName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$ImageName="'+$ImageName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$HelperVMContainerName="'+$HelperVMContainerName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$HelperVMLocalAdminUser="'+$HelperVMLocalAdminUser+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$HelperVMLocalAdminPwd="'+$HelperVMLocalAdminPwd+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		out-file -inputobject $ScriptRun -FilePath $ScriptFile -Encoding ASCII -append
		remove-item -path ($contextfileEncoded) -force

        # Extensions preparation
		$Blobtmp="importazcontext.ps1"
        $Extensions = Get-AzVMExtensionImage -Location $LocationName -PublisherName "Microsoft.Compute" -Type "CustomScriptExtension"
        $ExtensionPublisher= $Extensions[$Extensions.count-1].PublisherName
        $ExtensionType = $Extensions[$Extensions.count-1].Type
        $ExtensionVersion = (($Extensions[$Extensions.count-1].Version)[0..2]) -join ""

		# blob upload of scriptfile
        $result=get-azstorageblob -Container $HelperVMContainerName -Blob ${BlobTmp} -Context $storageaccount.Context -ErrorAction SilentlyContinue
        if (!($result))
		{
            Set-AzStorageBlobContent -Container ${HelperVMContainerName} -File $ScriptFile -Blob ${BlobTmp} -BlobType Block -Context $storageaccount.Context
		}

        # Remote install Az module
        $commandToExecute="powershell.exe Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force ; powershell install-module -name Az -force -ErrorAction SilentlyContinue; shutdown.exe /r /t 0"
        $ScriptSettings = @{}
        $ProtectedSettings = @{"storageAccountName" = $StorageAccountName; "storageaccountkey" = ($storageaccountkey[0]).value ; "commandToExecute" = $commandToExecute }
        Set-AzVMExtension -ResourceGroupName $ResourceGroupName -Location $LocationName -VMName $HelperVMName -Name $ExtensionType -Publisher $ExtensionPublisher -ExtensionType $ExtensionType -TypeHandlerVersion $ExtensionVersion -Settings $ScriptSettings -ProtectedSettings $ProtectedSettings
     	Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $HelperVMName -Name $ExtensionType -force -ErrorAction SilentlyContinue
        # wait for the reboot
        start-sleep 15

        # Run scriptfile
        $Run = "C:\Packages\Plugins\Microsoft.Compute.CustomScriptExtension\1.10.12\Downloads\0\$BlobTmp"
        Set-AzVMCustomScriptExtension -Name "CustomScriptExtension" -Location $LocationName -ResourceGroupName $ResourceGroupName -VMName $HelperVMName -StorageAccountName $StorageAccountName -ContainerName $HelperVMContainerName -FileName $BlobTmp -Run $Run
	}
}

if ((test-path($contextfile))) { remove-item -path ($contextfile) -force -ErrorAction SilentlyContinue }

$Disk = Get-AzDisk | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.location -ieq $LocationName) -and ($_.Name -ieq $HelperVMDiskName)}
if (-not $($Disk))
{
    $urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${HelperVMContainerName}/${ImageName}"
    $storageAccountId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"
    $diskConfig = New-AzDiskConfig -AccountType $StorageAccountType -Location $LocationName -HyperVGeneration $HyperVGeneration -CreateOption Import -StorageAccountId $storageAccountId -SourceUri $urlOfUploadedVhd
    New-AzDisk -Disk $diskConfig -ResourceGroupName $resourceGroupName -DiskName $HelperVMDiskName -ErrorAction SilentlyContinue
}

$Image=get-AzImage | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.location -ieq $LocationName) -and ($_.name -ieq $Imagename)}
if (-not $($Image))
{
    $Disk = Get-AzDisk | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.location -ieq $LocationName) -and ($_.Name -ieq $HelperVMDiskName)}
    if (-not ([Object]::ReferenceEquals($Disk,$null)))
    {
        $imageconfig=new-azimageconfig -location $LocationName -HyperVGeneration $HyperVGeneration
        $imageConfig = Set-AzImageOsDisk -Image $imageConfig -OsState Generalized -OsType Linux -ManagedDiskId $Disk.ID
        new-azimage -ImageName $ImageName -ResourceGroupName $ResourceGroupName -image $imageconfig -ErrorAction SilentlyContinue
    }
}

# Delete virtual machine with its objects
$AzImage=get-AzImage | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.location -ieq $LocationName) -and ($_.name -ieq $Imagename)}
if ([Object]::ReferenceEquals($AzImage,$null))
{
    write-Output "Error: Image creation failed."
}


$obj=Get-AzVM -ResourceGroupName $ResourceGroupName -Name $HelperVMName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
    $HelperVMDiskName=$obj.StorageProfile.OsDisk.Name
    Remove-AzVM -ResourceGroupName $resourceGroupName -Name $HelperVMName -force -ErrorAction SilentlyContinue
    $obj=Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $HelperVMDiskName -ErrorAction SilentlyContinue
    if (-not ([Object]::ReferenceEquals($obj,$null)))
    {
        Remove-AzDisk -ResourceGroupName $resourceGroupName -DiskName $HelperVMDiskName -Force -ErrorAction SilentlyContinue
    }
}



$obj=Get-AzNetworkInterface -ResourceGroupName $resourceGroupName -Name $HelperVMNICName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
	Remove-AzNetworkInterface -Name $HelperVMNICName -ResourceGroupName $ResourceGroupName -force -ErrorAction SilentlyContinue
}

$obj=Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $HelperVMPublicIPDNSName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
	Remove-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $HelperVMPublicIPDNSName -Force -ErrorAction SilentlyContinue
}

$obj=Get-AzVirtualNetwork -Name $HelperVMNetworkName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
	Remove-AzVirtualNetwork -Name $HelperVMNetworkName -ResourceGroupName $ResourceGroupName -Force -ErrorAction SilentlyContinue
}

$obj=Get-AzNetworkSecurityGroup -Name $HelperVMnsgName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
	Remove-AzNetworkSecurityGroup -Name $HelperVMnsgName -ResourceGroupName $ResourceGroupName -Force -ErrorAction SilentlyContinue
}

$obj=Get-AzStorageContainer -Name ${HelperVMContainerName} -Context $storageaccount.Context  -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
	Remove-AzStorageContainer -Name ${HelperVMContainerName} -Context $storageaccount.Context -Force -ErrorAction SilentlyContinue
}

$obj=Get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (-not ([Object]::ReferenceEquals($obj,$null)))
{
	Remove-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Force -ErrorAction SilentlyContinue
}
