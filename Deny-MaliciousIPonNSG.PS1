#Install-Module Az.Storage
Import-Module -Name Az.Storage
$vaultName = ""
$subscription = Get-AutomationVariable -Name 'workspaceSubscription'
$automantionconnectionname = ''
$workspaceId = Get-AutomationVariable -Name 'workspaceGuid'
$Conn = Get-AutomationConnection -Name 'EssRunAsConnection'
  
#Connect to Azure Account
$connectAz= Connect-AzAccount -CertificateThumbprint $Conn.CertificateThumbprint -ApplicationId $Conn.ApplicationId -Tenant $Conn.TenantId -ServicePrincipal  
Select-AzSubscription -Subscription ""
$storageAccountRG = ""
$storageAccountName = ""
$storageContainerName = ""
$blobname = ""
$localPath = "$env:TEMP\$blobName"
$storageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $storageAccountRG -Name $storageAccountName).Value
$context = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey[1]
Get-AzStorageBlobContent -Blob $blobName -Container $storageContainerName -Context $context -Destination $localPath
$excelData = Import-Excel -Path $localPath
#$data
$localPath
 
Select-AzSubscription -Subscription ""
function Check-RuleExists {
    param(
        [string] $ruleName,
        [array] $nsgRules
    )
    foreach ($rule in $nsgRules) {
        if ($rule.Name -eq $ruleName) {
            return $true
        }
    }
    return $false
}
 
function Get-NextAvailablePriority {
    param(
        [string] $nsgName,
        [string] $resourceGroupName
    )
    $Priority_nsg = Get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $resourceGroupName
    #$Priority_nsg
    Write-host "Using direction " $i.Kind
    $currentRules = $Priority_nsg.SecurityRules | Where-Object { $_.Direction -eq $i.Kind }
    $priorityRange = 100..4096
    $usedPriorities = $currentRules.Priority | Sort-Object
    $availablePriorities = $priorityRange | Where-Object { $_ -notin $usedPriorities }
 
    if ($availablePriorities) {
        return $availablePriorities[0]
    } else {
        throw "No available priorities. Maximum number of rules reached."
    }
}
 
function Create_Inbound_rules {
 
    param(
       [object] $nsg,
       [String] $denyRuleName,
       [String] $SourceIP,
       [String] $Direction,
       [int] $Priority_ib
    )
    $Final_NSG_IB = Get-AzNetworkSecurityGroup -Name $i.NSGName -ResourceGroupName $i.ResourceGroupName
    $Final_Name_IB = $i.NSGName
 
    Write-Host "Trying to modify" $Final_NSG_IB.Name " with new rule name " $i.RuleName $i.IP   
    $Final_NSG_IB | Add-AzNetworkSecurityRuleConfig -Name $denyRuleName -Description "" `
      -Access Deny -Protocol * -Direction Inbound -Priority $Priority_ib -SourceAddressPrefix $SourceIP -SourcePortRange * `
      -DestinationAddressPrefix "*" -DestinationPortRange * | Set-AzNetworkSecurityGroup
     
 Write-Host "Successfully created new rule with name" $i.RuleName $i.NSGName "in" $i.ResourceGroupName -ForegroundColor Green
 
}
 
function Create_Outbound_rules {
   param(
       [object] $nsg,
       [String] $denyRuleName,
       [String] $DestinationIp,
       [String] $Direction,
       [int] $Priority_ob
    )
 
 
 $Final_NSG_OB = Get-AzNetworkSecurityGroup -Name $i.NSGName -ResourceGroupName $i.ResourceGroupName
 $Final_Name = $i.NSGName
 
   Write-Host "Trying to modify" $Final_NSG_OB.Name " with new rule name " $i.RuleName $i.IP   
   $Final_NSG_OB | Add-AzNetworkSecurityRuleConfig -Name $denyRuleName -Description "" `
    -Access Deny -Protocol * -Direction Outbound -Priority $Priority_ob -SourceAddressPrefix "*" -SourcePortRange * `
    -DestinationAddressPrefix $DestinationIp -DestinationPortRange * | Set-AzNetworkSecurityGroup
   
 Write-Output "Successfully created new rule with name" $i.RuleName $i.NSGName "in" $i.ResourceGroupName
 #$Priority_nsg.SecurityRules
 #$Final_NSG_OB.SecurityRules
}
 
$NSGsWithoutRule = @()
 
foreach ($rows in $excelData) {
    Write-Host "Checking rules for" $rows.Name -ForegroundColor Yellow
    $Name_file = $rows.'Name'
    $ruleExists = $false
 
    $nsgs = Get-AzNetworkSecurityGroup 
    foreach ($nsg in $nsgs) {
        $Nsgrules = $nsg.SecurityRules
        if (-not (Check-RuleExists -ruleName $Name_File -nsgRules $nsg.SecurityRules)) {
            Write-Output "Adding rule to NSGWithoutRule"
            $NSGsWithoutRule += [PSCustomObject]@{
                NSGName = $nsg.Name
                ResourceGroupName = $nsg.ResourceGroupName
                RuleName = $Name_File
                Kind = $rows.Kind
                IP = $rows.IP
                NSG = $nsg
            }
        }else 
        {
            
        } 
    }
}
$NSGsWithoutRule | Where-Object {$_.Kind -eq "Inbound" }
foreach ($i in $NSGsWithoutRule){
  Switch ($i.Kind){
       All { }
       Inbound { 
            Write-Host "Creating rule for" $i.RuleName "in" $i.NSGName
            $Priority_ib = Get-NextAvailablePriority -nsgName $i.NSGName -resourceGroupName $i.ResourceGroupName
            Write-Output "Next available priority number on " $i.NSGName " to create " $i.RuleName " is" $Priority_ib
            Create_Inbound_rules -denyRuleName $i.RuleName -SourceIP $i.IP -Direction $i.Kind -nsg $nsgs -Priority $Priority_ib
        }
       Outbound {
            $Priority_ob = Get-NextAvailablePriority -nsgName $i.NSGName -resourceGroupName $i.ResourceGroupName
            $Priority_ob
            Write-Output "Next available priority number on " $i.NSGName " to create " $i.RuleName " is" $Priority_ob
            Create_Outbound_rules -denyRuleName $i.RuleName -DestinationIp $i.IP -Direction $i.Kind -nsg $nsgs -Priority $Priority_ob
        }
    }
}
#validating post completion of creating rules with same rules from file
$NSGsWithoutRuleValidate = @()
foreach ($rows in $excelData) {
    Write-Output "Checking rules for" $rows.Name 
    $Name_file = $rows.'Name'
    $ruleExists = $false
 
    $nsgs = Get-AzNetworkSecurityGroup 
    foreach ($nsg in $nsgs) {
        $Nsgrules = $nsg.SecurityRules
        if (-not (Check-RuleExists -ruleName $Name_File -nsgRules $nsg.SecurityRules)) {
            Write-Host "Adding rule to NSGWithoutRule" -ForegroundColor Red
            $NSGsWithoutRuleValidate += [PSCustomObject]@{
                NSGName = $nsg.Name
                ResourceGroupName = $nsg.ResourceGroupName
                RuleName = $Name_File
                Kind = $rows.Kind
                IP = $rows.IP
                NSG = $nsg
            }
        }else 
        {
            
        } 
    }
}
if(!$NSGsWithoutRuleValidate){
    Write-Output "All the rules are created successfully -- NSGsWithoutRule is Empty"
}else{
  Write-Error "Few Rules are still pending -- Please check the below results"
  $NSGsWithoutRuleValidate
}
