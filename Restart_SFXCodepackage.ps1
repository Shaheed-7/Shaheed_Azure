Import-Module -Name "Microsoft.ServiceFabric.Powershell.Http"
Import-Module -Name "AzureDataMonitorModule"
Import-Module -Name "Az.ServiceFabric"
Import-Module -Name "Az.KeyVault"
 
$vaultName = ""
$subscription = Get-AutomationVariable -Name 'workspaceSubscription'
$automantionconnectionname = ''
$workspaceId = Get-AutomationVariable -Name 'workspaceGuid'
$MailFrom = Get-AutomationVariable -Name 'mailFrom'
$MailTo = Get-AutomationVariable -Name 'mailTo'
$count = 0
 
$query = @"
    let window = 1h;
    let Threshold=2106;
    Perf
    | where TimeGenerated >=ago(window)
    | where ObjectName == 'Memory'
    | where CounterName == 'Available MBytes'
    | where _ResourceId contains ""
    | summarize AverageAvailableMemory = avg(CounterValue) by Computer,_ResourceId
    | where AverageAvailableMemory < Threshold
    | join
    (Perf
    | where ObjectName == "Process" and CounterName == "Working Set"
    | where TimeGenerated between (ago(5m) .. now())
    | where _ResourceId contains ""
    | summarize avg(CounterValue) by Computer, _SubscriptionId,_ResourceId, InstanceName,CounterName
    | where avg_CounterValue >= 1500000000
    | where InstanceName != "_Total") on Computer
    | extend VmId = toint(split(_ResourceId, "/")[-1])
    | extend Node = strcat("_prdemean_", VmId)
    | extend ServPkg = case(
    InstanceName == "Microsoft.Azure.ConnectedCar.MonitoringAgent", "MonitoringAgentPkg",
    strcat(InstanceName,"Pkg"))
    | order by avg_CounterValue desc
"@ 
 
 
try {
    # Get the connection "AzureRunAsConnection"
    $Conn = Get-AutomationConnection -Name 'EssRunAsConnection'
  
    #Connect to Azure Account
    $connectAz= Connect-AzAccount -CertificateThumbprint $Conn.CertificateThumbprint -ApplicationId $Conn.ApplicationId -Tenant $Conn.TenantId -ServicePrincipal  
    Select-AzSubscription -Subscription $subscription
    $subscription
    
    $logqueryresponse = Get-InsightsLogQueryResult `
        -workspaceid $workspaceId `
        -query $query
 
    #$logqueryresponse
 
    $table = @()
    foreach ($row in $logqueryresponse) {  
        $hashtable = @{}  
        $hashtable.Add("Computer",$row.Computer)
        $hashtable.Add("AppName",$row.InstanceName)
        $hashtable.Add("Memory Usage",$row.avg_CounterValue) 
        $hashtable.Add("Memory Available",$row.AverageAvailableMemory)
        $hashtable.Add("Instance",$row.Node)
        $hashtable.Add("SFPkg",$row.ServPkg)
        $table += $hashtable
        $count += 1
    }
 
    #$table
    
    $NodeId = $table.Instance
    $SFPkg = $table.SFPkg
    $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
    #$certCollection
    Select-AzSubscription -Subscription $subscription
 
    #Write-Output $table
 
    foreach ($node in $table) {     
        $base36Num = $node.computer.Replace('Name of VMSS','')
        $alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
        $inputarray = $base36Num.tolower().tochararray()
        [array]::reverse($inputarray)
        [long]$instance=0
        $pos=0
        foreach ($c in $inputarray) {
            $instance += $alphabet.IndexOf($c) * [long][Math]::Pow(36, $pos)
            $pos++
        }
        write-output ("VMSS Instance ID : {0}" -f $instance)
    }
 
        if (-not($certCollection.Count -gt 0)) {            
            $secret = Get-AzKeyVaultSecret -VaultName $vaultName -Name 'sfcert'
            $secrettext = [System.Net.NetworkCredential]::new("", $secret.SecretValue).Password
            $appId = $Conn.ApplicationId
            $kvSecretBytes = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrettext))
            $jsonCert = ConvertFrom-Json($kvSecretBytes)
            $certBytes = [System.Convert]::FromBase64String($jsonCert.data)
            $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
            $certCollection.Import($certBytes, $jsonCert.password, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        } 
        $sfUrl =  "SF Endpoint"
 
        write-output ("Service Fabric URL : {0}" -f $sfUrl)
 
    foreach ($node in $table) {
        Connect-SFCluster -X509Credential -ClientCertificate $certCollection[0] -ConnectionEndpoint $sfUrl -ServerCertThumbprint $certCollection[0].Thumbprint
        $nodeName = $node.Instance
        $servpkg = $node.SFPkg
        $sfDeployedApp = Get-SFDeployedApplication -NodeName $nodeName | select-object Name,id
        #Write-Output $sfDeployedApp
        foreach ($application in $sfDeployedApp) {
            $sfDeployedCodepkgList = Get-SFDeployedCodePackageInfoList -ApplicationId $application.id -NodeName $nodeName -ServiceManifestName $servpkg
            #Write-Output $sfDeployedCodepkgList  
            foreach ($svpkg in $sfDeployedCodepkgList) {
                #Write-Output("NodeName: {0} `nApplicationId: {1} `nServiceManifestName: {2}`nCodePackageName: {3}`nCodePackageInstanceId: {4}" -f $nodeName , $sfDeployedApp.id, $svpkg.ServiceManifestName, $svpkg[0].Name, $svpkg[0].MainEntryPoint.InstanceID)
                Restart-SFDeployedCodePackage -NodeName $nodeName -ApplicationId $application.id -ServiceManifestName $sfDeployedCodepkgList.ServiceManifestName -CodePackageName $sfDeployedCodepkgList[0].Name -CodePackageInstanceId $sfDeployedCodepkgList[0].MainEntryPoint.InstanceId
                Write-Output "Restarted Node" $nodeName 
                Write-Output "Restarted PKG " $servpkg 
            }
        }
       
    }
    
    <#do {
        $sfUrl =  "SF Endpoint"
        Connect-SFCluster -X509Credential -ClientCertificate $certCollection[0] -ConnectionEndpoint $sfUrl -ServerCertThumbprint $certCollection[0].Thumbprint
            start-sleep -seconds 3
            $nodedetails = Get-SFNode -NodeName "_prdemean_$instance"
        }
        while ($nodedetails.NodeStatus.ToString() -ne "Up")
        $nodedetails = Get-SFNode -NodeName "_prdemean_$instance"         
        $node.NodeName = $nodedetails.Name.ToString()
        $node.Status = $nodedetails.NodeStatus.ToString()
        write-output $nodeDetails#>        
    if($count -gt 0){   
        Write-Output "Query returned $count results"  
        $htmlTable = @()
        $dateTime = Get-Date
        $Mailmessage = "Business Logic -Nodes Restart Summary"
        $htmlbody = "<div>$Mailmessage</div><h4><font color=green>Execution Time: $($dateTime)</font></h4>"
        $table | foreach-object{        
            $htmlTable += New-Object PSObject -Property $_          
        }
        $htmlbody = $htmlbody + ($htmlTable | ConvertTo-Html -Fragment) + "<br>"
        
        #fetching Send Grid API key and sending Reports through mail
        $Subject = ""
        $APIkey = Get-AutomationVariable -Name ''
        if ($APIkey) {     
            Invoke-SendMail -MailTo $MailTo -MailFrom $MailFrom -Subject $Subject -Body $htmlbody  -ApiKey $APIkey
        }
        else { 
            Write-Output ("Automation variable of key is not found.")
        } 
        $jsonString = $htmlTable | ConvertTo-Json
        write-output($htmlTable)
        write-output($jsonString)
        if ($jsonString) {
            Write-output "Trigger Runbook to log data to Log Analytics"
            .\RUN-PushEventsToMonitoring.ps1 -jsonBody  $jsonString -logType 'Name of table'
        } 
    }
    else{
        Write-Output "Query returned $count results"
    }
 
}
catch {    
    Write-Error -Message $_.Exception
    throw $_.Exception
} 
 
 
