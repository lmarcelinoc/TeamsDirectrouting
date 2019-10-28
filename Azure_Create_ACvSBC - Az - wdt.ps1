# Welcome
    Cls
    Read-Host "This PowerShell script will deploy an AudioCodes VE Session Border Controller in Azure. Please press <Enter> to continue."
    Write-Host ""
    Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"

# Import Modules
    Import-Module Az

# Login & Select Azure Subscription
	Write-Host "Logging in..." -foreground "green";
    Connect-AzAccount
    $Subscriptions = Get-AzSubscription
    Write-Host ""
	Write-Host "Please select the Azure Subscription you want to deploy the AudioCodes VE SBC to: " -foreground "green"
		For ($i=0; $i -lt $Subscriptions.Count; $i++)  {
			Write-Host "$($i+1): $($Subscriptions[$i].Name)"
		}	
	[int]$number = Read-Host "Select your Azure Subscription: "
    Write-Host ""	
    Write-Host "You've selected $($Subscriptions[$number-1].Name)." -foreground "green"

    $subscriptionId = $Subscriptions
    Select-AzSubscription -SubscriptionName $($Subscriptions[$number-1].Name)

# Define Environment Variables
    $ResourceName = Read-Host "Please enter the prefix for all Audiocodes VE SBC resources"
    $ResourceGroupName = $ResourceName + "-rg"
    $VNetName = $ResourceName + "-vnet"
    $Subnet1Name = $ResourceName + "-teams-01"
    $Subnet2Name = $ResourceName + "-pstn-01"
    $VNetAddressSpace = "192.192.0.0/22"
    $SubnetAddressPrefix1 = "192.192.0.0/24"
    $SubnetAddressPrefix2 = "192.192.1.0/24"
	$NSG1 = $ResourceName + "-teams-nsg"
	$NSG2 = $ResourceName + "-pstn-nsg"
    $VMName1 = $ResourceName + "-ACvSBC-01"
    $Location = "SouthAfricaNorth"
    $AdminUsername = "wdt-admin"
    $AdminPassword = "WdT12345678980Microsoft!@#$"

# Display all variables which will be used to configure the AudioCodes VE SBC
    Write-Host "The following Variables will be used to create the AudioCodes VE Session Border Controller in Azure"
    Write-Host "---------------------------------------------------------------------------------------------------"
    Write-Host ""
    Write-Host "Microsoft Azure Subscription                : " $($Subscriptions[$number-1].Name)
    Write-Host "Resource Group Name                         : " $ResourceGroupName
    Write-Host ""
    Write-Host "Virtual Network Name                        : " $VNetName
    Write-Host "Virtual Network Subnet Address              : " $VNetAddressSpace
    Write-Host ""
    Write-Host "Microsoft Teams Subnet Name                 : " $Subnet1Name
    Write-Host "Microsof Teams Subnet Address               : " $SubnetAddressPrefix1
    Write-Host "Microsoft Teams Network Security Group Name : " $NSG1
    Write-Host ""
    Write-Host "PSTN/SIP Trunk Subnet Name                  : " $Subnet2Name
    Write-Host "PSTN/SIP Trunk Subnet Address               : " $SubnetAddressPrefix2
    Write-Host "PSTN/SIP Trunk Network Security Group Name  : " $NSG2
    Write-Host ""
    Write-Host "Virtual Machine Name                        : " $VMName1
    Write-Host "Virtual Machine Location                    : " $Location
    Write-Host ""
    Write-Host "AudioCodes VE SBC Username                  : " $AdminUsername
    Write-Host "AudioCodes VE SBC Password                  : " $AdminPassword
    
    Read-Host "Press enter to continue with the above variables or <CTRL+C> to quit."

# Create Resource Group
    Write-Host "Creating Resource Group..." -foreground "green";
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location

# Create Virtual Network Configuration
    Write-Host "Creating Virtual Network..." -foreground "green";
    $TeamsSubnet = New-AzVirtualNetworkSubnetConfig -Name $Subnet1Name -AddressPrefix $SubnetAddressPrefix1
    $PSTNSubnet  = New-AzVirtualNetworkSubnetConfig -Name $Subnet2Name  -AddressPrefix $SubnetAddressPrefix2
    New-AzVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix $VNetAddressSpace -Subnet $TeamsSubnet,$PSTNSubnet
    $VNet = Get-AZVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupName
    $Subnet1 = Get-AzVirtualNetworkSubnetConfig -Name $Subnet1Name -VirtualNetwork $VNet
    $Subnet2 = Get-AzVirtualNetworkSubnetConfig -Name $Subnet2Name -VirtualNetwork $VNet

# Create Network Security Groups for Teams & PSTN Interfaces
	$Teamsrule1 = New-AzNetworkSecurityRuleConfig -Name O365_SIP_Signalling -Description "O365 SIP Signalling Port" -Access Allow -Protocol * -Direction Inbound -Priority 100 -SourceAddressPrefix 52.112.0.0/14 -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 5061
	$TeamsRule2 = New-AzNetworkSecurityRuleConfig -Name Media_Ports -Description "Media Ports" -Access Allow -Protocol Udp -Direction Inbound -Priority 101 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 10000-10999
	$TeamsRule3 = New-AzNetworkSecurityRuleConfig -Name HTTP_Management -Description "HTTP Management of AudioCodes VE SBC" -Access Allow -Protocol Tcp -Direction Inbound -Priority 200 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80,443
	$NSGTeams = New-AzNetworkSecurityGroup -Name $NSG1 -ResourceGroupName $ResourceGroupName -Location $Location -SecurityRules $TeamsRule1,$TeamsRule2,$TeamsRule3
	
	$PSTNRule1 = New-AzNetworkSecurityRuleConfig -Name SIP_Trunk -Description "SIP Trunk Port" -Access Allow -Protocol Tcp -Direction Inbound -Priority 100 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 5060
	$PSTNRule2 = New-AzNetworkSecurityRuleConfig -Name HTTP_Management -Description "HTTP Management of AudioCodes VE SBC" -Access Allow -Protocol Tcp -Direction Inbound -Priority 200 -SourceAddressPrefix Internet -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 80,443
	$NSGPSTN = New-AzNetworkSecurityGroup -Name $NSG2 -ResourceGroupName $ResourceGroupName -Location $Location -SecurityRules $PSTNRule1,$PSTNRule2

# Define Virtual Machine Configuration
    $VMSize = "Standard_B2s"
    $VM1 = New-AzVMConfig -VMName $VMName1 -VMSize $VMSize

# Create Teams facing Public IP for VM1
    $PublicIPName11 = $VMName1 + "-PIP-TEAMS"
    $PublicIP11 = New-AzPublicIpAddress -Name $PublicIPName11 -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Static

# Create PSTN facing Public IP for VM1
    $PublicIPName12 = $VMName1 + "-PIP-PSTN"
    $PublicIP12 = New-AzPublicIpAddress -Name $PublicIPName12 -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Static

# Create Teams Facing Interface for VM1
    Write-Host "Creating Teams facing Interface for the first VM..." -foreground "green";
    $Interface11Name = $VMName1 + "-INF-TEAMS"
    $Interface11 = New-AzNetworkInterface -Name $Interface11Name -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $Subnet1.id -PublicIPAddressId $PublicIP11.id
    Add-AzVMNetworkInterface -VM $VM1 -Id $Interface11.Id

# Create PSTN facing Interface for VM1
    Write-Host "Creating PSTN facing Interface for the first VM..." -foreground "green";
    $Interface12Name = $VMName1 + "-INF-PSTN"
    $Interface12 = New-AzNetworkInterface -Name $Interface12Name -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $Subnet2.id -PublicIPAddressId $PublicIP12.id
    Add-AzVMNetworkInterface -VM $VM1 -Id $Interface12.Id –Primary

# Define the AudioCodes Source Image
    Write-Host "Setting Azure AudioCodes SBC Image as Source..." -foreground "green";
    Get-AzMarketplaceTerms -Publisher "audiocodes" -Product "mediantsessionbordercontroller" -Name "mediantvirtualsbcazure" | Set-AzMarketplaceTerms -Accept
	Set-AzVMSourceImage -VM $VM1 -PublisherName audiocodes -Offer mediantsessionbordercontroller -Skus mediantvirtualsbcazure -Version latest
	Set-AzVMPlan -VM $VM1 -Name mediantvirtualsbcazure -Publisher audiocodes -Product mediantsessionbordercontroller

# Configure Managed Disks
    Write-Host "Setting Virtual Machine Disk parameters..." -foreground "green";
    $DiskSize = "10"
    $DiskName1 = $VMName1 + "-Disk"
    Set-AzVMOSDisk -VM $VM1 -Name $DiskName1 -DiskSizeInGB $DiskSize -CreateOption fromImage -Linux

# Configure Administrator Credentials
    Write-Host "Setting Azure AudioCodes SBC Administrator parameters..." -foreground "green";
    $Credential = New-Object PSCredential $AdminUsername, ($AdminPassword | ConvertTo-SecureString -AsPlainText -Force)
    Set-AzVMOperatingSystem -VM $VM1 -Linux -ComputerName $VMName1 -Credential $Credential

# Create Virtual Machine
    Write-Host "Creating Azure AudioCodes VE Session Border Controller, please wait..." -foreground "green";
    New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VM1

# Assign Network Security Groups to AudioCodes VE SBC
    Write-Host "Applying Teams Network Security Groups to Azure AudioCodes VE SBC ..." -foreground "green";
    $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $NSG1
    $vNIC = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $Interface11Name
    $vNIC.NetworkSecurityGroup = $nsg
    $vNIC | Set-AzNetworkInterface

    Write-Host "Applying PSTN Network Security Groups to Azure AudioCodes VE SBC ..." -foreground "green";
    $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Name $NSG2
    $vNIC = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $Interface12Name
    $vNIC.NetworkSecurityGroup = $nsg
    $vNIC | Set-AzNetworkInterface

# Show Public IP Address to connect to the AudioCodes SBC
    Write-Host "The Azure AudioCodes SBC has been created, here are the associated Public IP Addresses" -foreground "green";
    Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName | ft -auto Name, IPAddress