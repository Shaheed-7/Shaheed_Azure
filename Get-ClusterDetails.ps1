import-module -Name "Microsoft.ServiceFabric.Powershell.Http"
import-module -Name "AzureDataMonitorModule"
import-module -Name "Az.ServiceFabric"
import-module -Name "ServiceFabric"
 
 
$vaultName = ""
$vaultName2 = ""
$subscription = Get-AutomationVariable -Name 'workspaceSubscription'
$automantionconnectionname = ''
$workspaceId = Get-AutomationVariable -Name 'workspaceGuid'
$MailFrom = ""
$MailTo = ""
 
function Parse-TargetDate {
    param (
        [string]$targetDate
    )
 
    $parts = $targetDate -split ', '
    $day = $parts[1]
    $time = $parts[2]
    $currentMonth = Get-Date -Format 'MM'
    $currentYear = Get-Date -Format 'yyyy'
     # Construct the 'Target Date' as a string in the format 'yyyy-      MM-dd'
    $targetDateFormatted = "{0}-{1:00}-{2:00}" -f $currentYear, $currentMonth, $day
 
    $combinedDateTime = "$targetDateFormatted $time"
    $targetDateObject = Get-Date $combinedDateTime
 
    return $targetDateObject
}
 
 
try {
    
    $Conn = Get-AutomationConnection -Name ''
  
    #Connect to Azure Account
    $connectAz= Connect-AzAccount -CertificateThumbprint $Conn.CertificateThumbprint -ApplicationId $Conn.ApplicationId -Tenant $Conn.TenantId -ServicePrincipal  
    Select-AzSubscription -Subscription $subscription
    $subscription
 
    $table = @()
    $tableData = @()
    $targetDatesTable = @()
    $data = @()
 
    $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
    
    Select-AzSubscription -Subscription $subscription
 
    Write-Output $table
 
     $sfUrl = @(""
       ) 
     
     if (-not($certCollection.Count -gt 0)) {  
            $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
            $secret = Get-AzKeyVaultSecret -VaultName $vaultName -Name ''
            $secrettext = [System.Net.NetworkCredential]::new("", $secret.SecretValue).Password
            $appId = $Conn.ApplicationId
            $kvSecretBytes = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($secrettext))
            $jsonCert = ConvertFrom-Json($kvSecretBytes)
            $certBytes = [System.Convert]::FromBase64String($jsonCert.data)
            $certCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
            $certCollection.Import($certBytes, $jsonCert.password, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)
        }
    
    #write-output ("Service Fabric URL : {0}" -f $sfUrl)
    foreach($url in $sfUrl){
        try{
            $connection = Connect-SFCluster -X509Credential -ClientCertificate $certCollection[0] -ConnectionEndpoint $url -ServerCertThumbprint $certCollection[0].Thumbprint
            write-output ("Connected to : {0}" -f $url)
            $applications = Get-SFApplication
            foreach ($app in $applications) {
 
                $services = Get-SFService -ApplicationId $app.ApplicationId
                #$services.ServiceName
                foreach ($service in $services) {
                    
                    #Write-Output "Service Name: $($service.ServiceName)"
                    $partitions = Get-SFPartition -ServiceId $service.ServiceId
                    #$partitions.PartitionId
                    foreach ($partition in $partitions) {
                        #Write-Output "Partition ID: $($partition.PartitionId)"
                        $replica = Get-SFReplica -PartitionId $partition.PartitionId
                        $replicaCount = $replica | Measure-Object | Select-Object -ExpandProperty Count
                        #$replicaCount
                        $rowData = @{
                        "ClusterName" = $url
                        "Application" = $app.ApplicationId
                        "Service" = $Service.ServiceName
                        "Partition" = $partition.PartitionId
                        "ReplicaCount" = $replicaCount
                    }
                    $data += New-Object PSObject -Property $rowData
                    }
                    
                }
            }
        
        }
        catch{
            Write-Output "Failed to connect to $url. Error: $_"
        }
    }
    Write-Output $data
 
    $tableHTML = ($data | ConvertTo-Html -Fragment) -replace '<table>','<table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse;">'
    #$tableHTML
    $htmlbody = "<html>
    <body>
    <h2>Service Fabric Details Table</h2>
    <table>
    <tr>
    <th>ClusterName</th>
    <th>Application</th>
    <th>Service</th>
    <th>Partition</th>
    <th>Replica Count</th>
    </tr>"
    
    foreach ($row in $data) {
        $htmlbody += "
        <tr>
        <td>$($row.ClusterName)</td>
        <td>$($row.Application)</td>
        <td>$($row.Service)</td>
        <td>$($row.Partition)</td>
        <td>$($row.ReplicaCount)</td>
        </tr>"
    }
    $htmlbody += "
    </table>
    </body>
    </html>
    "
    
 
 
    $Subject = "PRD-EMEA Cluster details"
    $APIkey = Get-AutomationVariable -Name ''
    if ($APIkey) {     
       Invoke-SendMail -MailTo $MailTo -MailFrom $MailFrom -Subject $Subject -Body $htmlbody  -ApiKey $APIkey
    }
    else { 
        Write-Output ("Automation variable of key is not found.")
    }
   
 
}
catch {    
    Write-Error -Message $_.Exception
    throw $_.Exception
}
