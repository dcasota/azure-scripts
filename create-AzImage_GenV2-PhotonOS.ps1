#
# The script creates an Azure Generation V2 image of VMware Photon OS.
#
# To make use of VMware Photon OS on Azure, the script first creates a temporary Windows VM.
# Inside that Windows VM the VMware Photon OS bits for Azure are downloaded from the VMware download location,
# the extracted VMware Photon OS .vhd is uploaded as Azure page blob and after the Generation V2 image has been created, the Windows VM is deleted.
#
# For study purposes the temporary VM created is Microsoft Windows Server 2019 on a Hyper-V Generation V2 virtual hardware using the offering Standard_E4s_v3.
# 
#
# History
# 0.1   16.02.2020   dcasota  First release
#
# related learn weblinks
# https://docs.microsoft.com/en-us/azure/virtual-machines/windows/generation-2
#
# Prerequisites:
#    - Microsoft Powershell, Microsoft Azure Powershell
#    - Azure account
#
# Parameter username
#    Azure login username
# Parameter password
#    Azure login password
# Parameter SoftwareToProcess
#    Specifies the URL of the VMware Photon OS .vhd.tar.gz file
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
[string]$SoftwareToProcess="http://dl.bintray.com/vmware/photon/3.0/Rev2/azure/photon-azure-3.0-9355405.vhd.tar.gz",
[string]$LocationName = "switzerlandnorth",
[string]$ResourceGroupName = "photonos-lab-rg",
[string]$StorageAccountName="photonoslab",
[string]$ContainerName="disks",
[string]$BlobName=($(split-path -path $SoftwareToProcess -Leaf) -split ".tar.gz")[0],
[string]$ImageName=($(split-path -path $SoftwareToProcess -Leaf) -split ".vhd.tar.gz")[0]
)


# settings of the temporary VM
# ----------------------------
# network setting
$NetworkName = "w2k19network"
# virtual network and subnets setting
$SubnetAddressPrefix = "192.168.1.0/24"
$VnetAddressPrefix = "192.168.0.0/16"
# VM setting
$VMSize = "Standard_E4s_v3" # offering includes a d: drive with 60GB non-persistent capacity
$DiskName="PhotonOS"
$VMSize_TempPath="d:" # on this drive $SoftwareToProcess is processed
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
# Get-AzVMImage -Location westus2 -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus 2019-datacenter-with-containers-smalldisk-g2
$productversion = "17763.973.2001110547"

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
$contextfile=$($env:public) + [IO.Path]::DirectorySeparatorChar + "azcontext.txt"
Save-AzContext -Path $contextfile -Force

#Set the context to the subscription Id where Managed Disk exists and where VM will be created
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
$PhotonOSTarGzFileName=split-path -path $Uri -Leaf
$PhotonOSTarFileName=$PhotonOSTarGzFileName.Substring(0,$PhotonOSTarGzFileName.LastIndexOf('.')).split([io.path]::DirectorySeparatorChar)[-1]
$PhotonOSVhdFilename=$PhotonOSTarFileName.Substring(0,$PhotonOSTarFileName.LastIndexOf('.')).split([io.path]::DirectorySeparatorChar)[-1]
$vhdfile=$tmppath + [io.path]::DirectorySeparatorChar+$PhotonOSVhdFilename
$gzfile=$tmppath + [io.path]::DirectorySeparatorChar+$PhotonOSTarGzFileName

if (!(Test-Path $vhdfile))
{
    if (Test-Path -d $tmppath)
    {
        cd $tmppath
        if (!(Test-Path $gzfile))
        {
            $RootDrive="'"+$(split-path -path $tmppath -Qualifier)+"'"
            $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID=$RootDrive" | select-object @{Name="FreeGB";Expression={[math]::Round($_.Freespace/1GB,2)}}
            if ($disk.FreeGB -gt 35)
            {
                Invoke-WebRequest $Uri -OutFile $PhotonOSTarGzFileName
                if (Test-Path $gzfile)
                {
                    cd $tmppath
                    tar -xzvf $gzfile
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
				$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)
				$result=az storage container exists --account-name $StorageAccountName --account-key $storageaccountkey.value[0] --name $ContainerName | convertfrom-json
				if ($result.exists -eq $true)
				{
					$BlobName= split-path $vhdfile -leaf
					$urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${BlobName}"
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
$result = get-azresourcegroup -name $ResourceGroupName -Location $LocationName -ErrorAction SilentlyContinue
if ( -not $($result))
{
		New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName
}

$Image=Get-AzImage -ResourceGroupName $resourceGroupName -ImageName $ImageName
if (-not $($Image))
{
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
		# create vm
		# -----------

		# VM local admin setting
		$VMLocalAdminSecurePassword = ConvertTo-SecureString $VMLocalAdminPwd -AsPlainText -Force
		$LocalAdminUserCredential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword)

		# Create a public IP address
		$nic=get-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
		if ( -not $($nic))
		{
			$pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $LocationName -Name $PublicIPDNSName -AllocationMethod Static -IdleTimeoutInMinutes 4
			# Create a virtual network card and associate with public IP address and NSG
			$nic = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName `
				-SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id
		}

		# Create a virtual machine configuration
		$vmConfig = New-AzVMConfig -VMName $VMName -VMSize $VMSize | `
		Add-AzVMNetworkInterface -Id $nic.Id

		$vmimage= get-azvmimage -Location $LocationName -PublisherName $publisherName -Offer $offerName -Skus $skuName -Version $productversion
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
			$VirtualMachine = New-AzVM -ResourceGroupName $ResourceGroupName -Location $LocationName -VM $vmConfig
		}
	}

	$objVM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -status -ErrorAction SilentlyContinue
	if (-not ([Object]::ReferenceEquals($objVM,$null)))
	{
		# enable boot diagnostics for serial console option
		az vm boot-diagnostics enable --name $vmName --resource-group $ResourceGroupName --storage "https://${StorageAccountName}.blob.core.windows.net"
		
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
		$tmp='$Uri="'+$SoftwareToProcess+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append		
		$tmp='$tmppath="'+$VMSize_TempPath+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append	
		$tmp='$tenant="'+$((get-azcontext).tenant.id)+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$ResourceGroupName="'+$ResourceGroupName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$LocationName="'+$LocationName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$StorageAccountName="'+$StorageAccountName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		$tmp='$ContainerName="'+$ContainerName+'"'; out-file -inputobject $tmp -FilePath $ScriptFile -Encoding ASCII -Append
		out-file -inputobject $ScriptRun -FilePath $ScriptFile -Encoding ASCII -append
		remove-item -path ($contextfile) -force
		remove-item -path ($contextfileEncoded) -force

		# Remote import azcontext and process blob upload from scriptfile
		$Blobtmp="importazcontext.ps1"
		$result=az storage blob exists --account-key ($storageaccountkey[0]).value --account-name $StorageAccountName --container-name ${ContainerName} --name ${BlobTmp} | convertfrom-json
		if ($result.exists -eq $false)
		{
			az storage blob upload --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value --container-name ${ContainerName} --type block --file $ScriptFile --name ${BlobTmp}
			$return=Set-AzVMCustomScriptExtension -ResourceGroupName $ResourceGroupName -Location $LocationName `
				-VMName $vmName `
				-Name "CustomScriptExtension" `
				-containername $ContainerName -storageaccountname $StorageAccountName `
				-Filename ${BlobTmp}	
			echo $return
			Remove-AzVMExtension -ResourceGroupName $ResourceGroupName -VMName $VMName -Name "CustomScriptExtension" -force
		}
	}

	$Disk = Get-AzDisk -ResourceGroupName $resourceGroupName -DiskName $DiskName
	if (-not $($Disk))
	{
		$urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${BlobName}"
		$storageAccountId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$StorageAccountName"
		$diskConfig = New-AzDiskConfig -AccountType 'Standard_LRS' -Location $LocationName -HyperVGeneration "V2" -CreateOption Import -StorageAccountId $storageAccountId -SourceUri $urlOfUploadedVhd
		New-AzDisk -Disk $diskConfig -ResourceGroupName $resourceGroupName -DiskName $DiskName		
	}

    $Disk=Get-AzDisk -ResourceGroupName $resourceGroupName -name $DiskName
	if (-not ([Object]::ReferenceEquals($Disk,$null)))
	{	
		$imageconfig=new-azimageconfig -location $LocationName -HyperVGeneration "V2"
		$imageConfig = Set-AzImageOsDisk -Image $imageConfig -OsState Generalized -OsType Linux -ManagedDiskId $Disk.ID
		new-azimage -ImageName $ImageName -ResourceGroupName $ResourceGroupName -image $imageconfig
	}
}

$Image=Get-AzImage -ResourceGroupName $resourceGroupName -ImageName $ImageName
if (-not ([Object]::ReferenceEquals($Image,$null)))
{
	# Delete Disk and VM
	Remove-AzVM -ResourceGroupName $resourceGroupName -Name $vmName -force
    Remove-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $PublicIPDNSName -Force
    Remove-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -force
	Remove-AzDisk -ResourceGroupName $resourceGroupName -DiskName $DiskName -Force
    Remove-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -force
    Remove-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -force
    az storage container delete --name ${ContainerName} --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value
}


