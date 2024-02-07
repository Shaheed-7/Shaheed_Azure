Install-Module -Name "Az.Accounts" -Scope CurrentUser -Force -AllowClobber
Import-Module -Name "Az.Accounts"
Connect-AzAccount -Tenant "98c29f8a-1be1-454c-a666-50f4804cca9c"
$sub = Get-AzSubscription
$sub.Name
$sub.Id
$sub.SubscriptionId
$AdApp= New-AzADApplication -DisplayName "Connection_to_ADO"
Write-Output "Successfully created the AD App"
$AdApp.AppId