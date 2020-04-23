# .SYNOPSIS
#  The script creates an Azure image of a VMware Photon OS release.
# .DESCRIPTION
#  To make use of VMware Photon OS on Azure, and without requiring to download the Photon OS bits locally, the script first creates a temporary Azure windows VM.
#  Inside that windows VM, the Photon release Azure .vhd file is downloaded. You can specify the Photon release download link as param value of $SoftwareToProcess.
#  VMware Photon OS release download links:
#    Photon OS 3.0 Revision 2 Azure VHD:                 http://dl.bintray.com/vmware/photon/3.0/Rev2/azure/photon-azure-3.0-9355405.vhd.tar.gz
#    Photon OS 3.0 GA Azure VHD:                         http://dl.bintray.com/vmware/photon/3.0/GA/azure/photon-azure-3.0-26156e2.vhd.tar.gz
#       Photon OS 3.0 RC Azure VHD:                      http://dl.bintray.com/vmware/photon/3.0/RC/azure/photon-azure-3.0-49fd219.vhd.tar.gz
#       Photon OS 3.0 Beta:                              http://dl.bintray.com/vmware/photon/3.0/Beta/azure/photon-azure-3.0-5e45dc9.vhd.tar.gz
#    Photon OS 2.0 GA Azure VHD gz file:                 http://dl.bintray.com/vmware/photon/2.0/GA/azure/photon-azure-2.0-304b817.vhd.gz
#    Photon OS 2.0 GA Azure VHD cloud-init provisioning: http://dl.bintray.com/vmware/photon/2.0/GA/azure/photon-azure-2.0-3146fa6.tar.gz
#       Photon OS 2.0 RC Azure VHD - gz file:            https://bintray.com/vmware/photon/download_file?file_path=2.0%2FRC%2Fazure%2Fphoton-azure-2.0-31bb961.vhd.gz
#       Photon OS 2.0 Beta Azure VHD:                    https://bintray.com/vmware/photon/download_file?file_path=2.0%2FBeta%2Fazure%2Fphoton-azure-2.0-8553d58.vhd
#  The extracted VMware Photon OS release .vhd file is uploaded as Azure page blob,and after the Azure Photon image has been created, the temporary Windows VM is deleted.
#  For study purposes the temporary VM operating system is Microsoft Windows Server 2019 on a specifiable Hyper-V generation virtual hardware using the Azure offering Standard_E4s_v3.
#  virtual hardware related learn weblinks
#    - https://docs.microsoft.com/en-us/azure/virtual-machines/windows/generation-2
#  prerequisites
#    - Microsoft Powershell, Microsoft Azure Powershell
#    - Azure account
#
# .NOTES
#   Author:  Daniel Casota
#   Version:
#   0.1   16.02.2020   dcasota  First release
#   0.2   24.02.2020   dcasota  Minor bugfixes, new param HyperVGeneration
#   0.3   23.04.2020   dcasota  Minor bugfixes image name processing and nsg cleanup
#
# .PARAMETER cred
#   Azure login credential
# .PARAMETER SoftwareToProcess
#   Specifies the URL of the VMware Photon OS .vhd.tar.gz file
# .PARAMETER Location
#   Azure location name where to create or lookup the resource group
# .PARAMETER ResourceGroupName
#   Azure resourcegroup name
# .PARAMETER StorageAccountName
#   Azure storage account name
# .PARAMETER StorageAccountType
#   Storage AccountType
# .PARAMETER ContainerName
#   Azure storage container name
# .PARAMETER Imagename
#   Azure image name for the uploaded VMware Photon OS
# .PARAMETER HyperVGeneration
#   Hyper-V Generation (V1, V2)
# .PARAMETER DiskName
#   Name of the DiskName in the Image
#
# .EXAMPLE
#    ./create-AzImage-PhotonOS.ps1 -cred $(Get-credential -message 'Enter a username and password for Azure login.') -ResourceGroupName photonoslab-rg -Location switzerlandnorth -StorageAccountName photonosaccount -ContainerName disks

[CmdletBinding()]
param(
[Parameter(Mandatory = $false)]
[ValidateNotNull()]
[System.Management.Automation.PSCredential]
[System.Management.Automation.Credential()]$cred = (Get-credential -message 'Enter a username and password for the Azure login.'),	

[Parameter(Mandatory = $false)]
[ValidateSet('http://dl.bintray.com/vmware/photon/3.0/Rev2/azure/photon-azure-3.0-9355405.vhd.tar.gz', `
'http://dl.bintray.com/vmware/photon/3.0/GA/azure/photon-azure-3.0-26156e2.vhd.tar.gz',`
'http://dl.bintray.com/vmware/photon/3.0/RC/azure/photon-azure-3.0-49fd219.vhd.tar.gz',`
'http://dl.bintray.com/vmware/photon/3.0/Beta/azure/photon-azure-3.0-5e45dc9.vhd.tar.gz',`
'http://dl.bintray.com/vmware/photon/2.0/GA/azure/photon-azure-2.0-304b817.vhd.gz',`
'http://dl.bintray.com/vmware/photon/2.0/GA/azure/photon-azure-2.0-3146fa6.tar.gz',`
'https://bintray.com/vmware/photon/download_file?file_path=2.0%2FRC%2Fazure%2Fphoton-azure-2.0-31bb961.vhd.gz',`
'https://bintray.com/vmware/photon/download_file?file_path=2.0%2FBeta%2Fazure%2Fphoton-azure-2.0-8553d58.vhd')]
[String]$SoftwareToProcess="http://dl.bintray.com/vmware/photon/3.0/Rev2/azure/photon-azure-3.0-9355405.vhd.tar.gz",

[Parameter(Mandatory = $true)][ValidateNotNull()]
[ValidateSet('eastasia','southeastasia','centralus','eastus','eastus2','westus','northcentralus','southcentralus',`
'northeurope','westeurope','japanwest','japaneast','brazilsouth','australiaeast','australiasoutheast',`
'southindia','centralindia','westindia','canadacentral','canadaeast','uksouth','ukwest','westcentralus','westus2',`'koreacentral','koreasouth','francecentral','francesouth','australiacentral','australiacentral2',`
'uaecentral','uaenorth','southafricanorth','southafricawest','switzerlandnorth','switzerlandwest',`
'germanynorth','germanywestcentral','norwaywest','norwayeast')]
[string]$Location,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$ResourceGroupName,

[Parameter(Mandatory = $true)][ValidateNotNull()]
[string]$StorageAccountName,

[Parameter(Mandatory = $false)]
[string]$StorageAccountType="Standard_LRS",

[Parameter(Mandatory = $false)][ValidateNotNull()]
[string]$ContainerName = "disks",

[Parameter(Mandatory = $false)]
[string]$ImageName=$(((split-path -path $([Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null;[System.Web.HttpUtility]::UrlDecode($SoftwareToProcess)) -Leaf) -split ".vhd")[0] + ".vhd"),

[Parameter(Mandatory = $false)]
[ValidateSet('V1','V2')]
[string]$HyperVGeneration="V1",

[Parameter(Mandatory = $false)]
[string]$DiskName="PhotonOS"
)


$Uri=$([Reflection.Assembly]::LoadWithPartialName("System.Web") | Out-Null;[System.Web.HttpUtility]::UrlDecode($SoftwareToProcess))



# settings of the temporary VM
# ----------------------------
$VMSize="Standard_E4s_v3" # This default VM size offering includes a d: drive with 60GB non-persistent capacity
$VMSize_TempPath="d:" # $SoftwareToProcess file is downloaded and extracted on this drive. Depending of the VMSize offer, it includes built-in an additional non persistent  drive.
# network setting
$NetworkName = "w2k19network"
# virtual network and subnets setting
$SubnetAddressPrefix = "192.168.1.0/24"
$VnetAddressPrefix = "192.168.0.0/16"
# VM setting
$ComputerName = "w2k19"
$VMName = $ComputerName
$NICName = $ComputerName + "nic"
$VMLocalAdminUser = "LocalAdminUser"
$VMLocalAdminPwd="Secure2020123!" #12-123 chars
$PublicIPDNSName="mypublicdns$(Get-Random)"
$nsgName = "myNetworkSecurityGroup"
$publisherName = "MicrosoftWindowsServer"
$offerName = "WindowsServer"
$skuName = "2019-datacenter-with-containers-smalldisk-g2"
$marketplacetermsname= $skuName
# Get-AzVMImage -Location switzerlandnorth -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2019-datacenter-with-containers-smalldisk-g2
$productversion = "17763.1039.2002091844"

# check Azure CLI
if (-not ($($env:path).contains("CLI2\wbin")))
{
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
    $env:path="C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin;"+$env:path
}

# check Azure Powershell
if (([string]::IsNullOrEmpty((get-module -name Az* -listavailable)))) {install-module Az -force -ErrorAction SilentlyContinue}

# Azure Login
$azcontext=connect-Azaccount -cred $cred
if (-not $($azcontext)) {break}
# save credentials
$contextfile=$($env:public) + [IO.Path]::DirectorySeparatorChar + "azcontext.txt"
Save-AzContext -Path $contextfile -Force

#Set the context to the subscription Id where Managed Disk exists and where VM will be created if necessary
$subscriptionId=(get-azcontext).Subscription.Id
# set subscription
az account set --subscription $subscriptionId

$Scriptrun=
@'

# check Azure Powershell
if (([string]::IsNullOrEmpty((get-module -name Az* -listavailable)))) {install-module Az -force -ErrorAction SilentlyContinue}

# check Azure CLI
if (-not ($($env:path).contains("CLI2\wbin")))
{
    if ($IsWindows -or $ENV:OS)
    {
        if (test-path AzureCLI.msi) {remove-item -path AzureCLI.msi -force}
        Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
        $env:path="C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin;"+$env:path
    }
    else
    {
        curl -L https://aka.ms/InstallAzureCli | bash
    }
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

$RootDrive=(get-item $tmppath).Root.Name

$tmpfilename=split-path -path $Uri -Leaf
$tmpname=($tmpfilename -split ".vhd")[0] + ".vhd"

$vhdfile=$tmppath + [io.path]::DirectorySeparatorChar+$tmpname
$downloadfile=$tmppath + [io.path]::DirectorySeparatorChar+$tmpfilename


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
                Invoke-WebRequest $Uri -OutFile $tmpfilename
            }
            if ((Test-Path $downloadfile) -and ((([IO.Path]::GetExtension($tmpfilename)) -ieq ".gz")))
            {
                tar -xzvf $downloadfile
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
		$result = get-azresourcegroup -name $ResourceGroupName -Location $Location -ErrorAction SilentlyContinue
		if ($result)
		{
			$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
			if ($storageaccount)
			{
				$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)
				$result=az storage container exists --account-name $StorageAccountName --account-key $storageaccountkey.value[0] --name $ContainerName | convertfrom-json
				if ($result.exists -eq $true)
				{
					$BlobName= $tmpname
					$result=az storage blob exists --account-key $storageaccountkey.value[0] --account-name $StorageAccountName --container-name ${ContainerName} --name ${BlobName} | convertfrom-json
					if ($result.exists -eq $false)
					{
						try {
						az storage blob upload --account-name $StorageAccountName `
						--account-key ($storageaccountkey[0]).value `
						--container-name ${ContainerName} `
						--type page `
						--file $vhdfile `
						--name ${BlobName}
						} catch{}
					}			
				}
			}
		}
	}
}
'@

# create lab resource group if it does not exist
$result = get-azresourcegroup -name $ResourceGroupName -Location $Location -ErrorAction SilentlyContinue
if ( -not $($result))
{
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location
}

# storageaccount
$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if ( -not $($storageaccount))
{
	$storageaccount=New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $Location -Kind Storage -SkuName Standard_LRS -ErrorAction SilentlyContinue
	if ( -not $($storageaccount)) {break}
}
do {sleep -Milliseconds 1000} until ($((get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).ProvisioningState) -ieq "Succeeded") 
$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)


$result=az storage container exists --account-name $storageaccountname --name ${ContainerName} | convertfrom-json
if ($result.exists -eq $false)
{
	az storage container create --name ${ContainerName} --public-access blob --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value
}

$Disk = Get-AzDisk | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.Name -ieq $DiskName)}
if (-not $($Disk))
{
	# a temporary VM is necessary because inside it downloads Photon and uploads the extracted disk as image base.

	[Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction SilentlyContinue
	if (-not ($VM))
	{
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
    		$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $Location -SecurityRules $rdpRule1,$rdpRule2
    	}

    	# set network if not already set
    	$vnet = get-azvirtualnetwork -name $networkname -ResourceGroupName $resourcegroupname -ErrorAction SilentlyContinue
    	if ( -not $($vnet))
    	{
    		$ServerSubnet  = New-AzVirtualNetworkSubnetConfig -Name frontendSubnet  -AddressPrefix $SubnetAddressPrefix -NetworkSecurityGroup $nsg
    		$vnet = New-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix $VnetAddressPrefix -Subnet $ServerSubnet
    		$vnet | Set-AzVirtualNetwork
    	}

		# create vm
		# -----------

		# VM local admin setting
		$VMLocalAdminSecurePassword = ConvertTo-SecureString $VMLocalAdminPwd -AsPlainText -Force
		$LocalAdminUserCredential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword)

		# Create a public IP address
		$nic=get-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
		if ( -not $($nic))
		{
			$pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Name $PublicIPDNSName -AllocationMethod Static -IdleTimeoutInMinutes 4
			# Create a virtual network card and associate with public IP address and NSG
			$nic = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $Location `
				-SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id
		}

		# Create a virtual machine configuration
		$vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize | `
		Add-AzVMNetworkInterface -Id $nic.Id

		$vmimage= get-azvmimage -Location $Location -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $productversion
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

			$vmConfig = Set-AzVMOperatingSystem -Windows -VM $vmConfig -ComputerName $ComputerName -Credential $LocalAdminUserCredential | `
			Set-AzVMSourceImage -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $productversion


			# Create the VM
			$VirtualMachine = New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig
		}
	}

	$objVM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -status -ErrorAction SilentlyContinue
	if (-not ([Object]::ReferenceEquals($objVM,$null)))
	{
		# First remote install Az Module
		az vm extension set --publisher Microsoft.Compute --version 1.8 --name "CustomScriptExtension" --vm-name $vmName --resource-group $ResourceGroupName --settings "{'commandToExecute':'powershell.exe Install-module Az -force -ErrorAction SilentlyContinue'}"
		Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -Name "CustomScriptExtension" -force
		
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
		$tmp='$tmppath="'+$VMSize_TempPath+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append	
		$tmp='$tenant="'+$((get-azcontext).tenant.id)+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$ResourceGroupName="'+$ResourceGroupName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$Location="'+$Location+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$StorageAccountName="'+$StorageAccountName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$ContainerName="'+$ContainerName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		out-file -inputobject $ScriptRun -FilePath $ScriptFile -Encoding ASCII -append
		remove-item -path ($contextfileEncoded) -force

		# Remote import azcontext and process blob upload from scriptfile
		$Blobtmp="importazcontext.ps1"
		$result=az storage blob exists --account-key ($storageaccountkey[0]).value --account-name $StorageAccountName --container-name ${ContainerName} --name ${BlobTmp} | convertfrom-json
		if ($result.exists -eq $false)
		{
			az storage blob upload --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value --container-name ${ContainerName} --type block --file $ScriptFile --name ${BlobTmp}
			$return=Set-AzVMCustomScriptExtension -ResourceGroupName $ResourceGroupName -Location $Location -ErrorAction SilentlyContinue `
				-VMName $vmName `
				-Name "CustomScriptExtension" `
				-containername $ContainerName -storageaccountname $StorageAccountName `
				-Filename ${BlobTmp}	
			Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -Name "CustomScriptExtension" -force -ErrorAction SilentlyContinue
		}
	}
}

if ((test-path($contextfile))) { remove-item -path ($contextfile) -force -ErrorAction SilentlyContinue }

$Disk = Get-AzDisk | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.Name -ieq $DiskName)}
if (-not $($Disk))
{
    $BlobName=((split-path -path $Uri -Leaf) -split ".vhd")[0] + ".vhd"
    $urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${BlobName}"
    $storageAccountId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"
    $diskConfig = New-AzDiskConfig -AccountType $StorageAccountType -Location $Location -HyperVGeneration $HyperVGeneration -CreateOption Import -StorageAccountId $storageAccountId -SourceUri $urlOfUploadedVhd
    New-AzDisk -Disk $diskConfig -ResourceGroupName $resourceGroupName -DiskName $DiskName -ErrorAction SilentlyContinue
}


$Image=get-AzImage | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.name -ieq $Imagename)}
if (-not $($Image))
{
    $Disk = Get-AzDisk | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.Name -ieq $DiskName)}
    if (-not ([Object]::ReferenceEquals($Disk,$null)))
    {	
        $imageconfig=new-azimageconfig -location $Location -HyperVGeneration $HyperVGeneration
        $imageConfig = Set-AzImageOsDisk -Image $imageConfig -OsState Generalized -OsType Linux -ManagedDiskId $Disk.ID
        new-azimage -ImageName $ImageName -ResourceGroupName $ResourceGroupName -image $imageconfig -ErrorAction SilentlyContinue
    }
}

$Image=get-AzImage | where-object {($_.resourcegroupname -ieq $ResourceGroupName) -and ($_.name -ieq $Imagename)}
if (-not ([Object]::ReferenceEquals($Image,$null)))
{
	# Delete Disk and VM
    $VirtualMachine=Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName
    if (-not ([Object]::ReferenceEquals($VirtualMachine,$null)))
       {
        $OsDiskName=$VirtualMachine.StorageProfile.OsDisk.Name
	    Remove-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -force -ErrorAction SilentlyContinue
	    Remove-AzDisk -ResourceGroupName $resourceGroupName -DiskName $OsDiskName -Force -ErrorAction SilentlyContinue
    }
	Remove-AzDisk -ResourceGroupName $resourceGroupName -DiskName $DiskName -Force -ErrorAction SilentlyContinue
    Remove-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -force -ErrorAction SilentlyContinue
    Remove-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $PublicIPDNSName -Force -ErrorAction SilentlyContinue
    Remove-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -force -ErrorAction SilentlyContinue
    Remove-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -force -ErrorAction SilentlyContinue
    az storage container delete --name ${ContainerName} --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value
    remove-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Force -ErrorAction SilentlyContinue
}
else { write-host Error: Image creation failed. }
