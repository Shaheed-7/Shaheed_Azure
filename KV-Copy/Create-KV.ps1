$Location = 'centralindia'
$RgName = 'KeyVault_Shaheed'
$kvName = 'KV-Shaheed'
$KvName2 = 'KV-Shaheed-Copy'
$secretname = 'VeryImp1'
$secretname2 = 'VeryImp-copy'
$secretoriginal= 'OrewaKaizokuOuNiNaaru'
$secureString = ConvertTo-SecureString -String $secretoriginal -AsPlainText -Force
$secureString
function CreateKV{

param(
[string]$KvName
)
$kvexist = Get-AzKeyVault -VaultName $kvName -ErrorAction SilentlyContinue
if (!$kvexist){
Write-Host "$kvexist is not present in $RgName"
Write-Host "Creating KeyVault $kvexist......."
New-AzKeyVault -Location $Location -Name $KvName -ResourceGroupName $RgName
}
if ($kvexist){
Write-Host "$KvName is provisioned successfully"
}
}

function UpdateKVSecret{
param(
[string]$secretname,
[System.Security.SecureString]$secretoriginal
)
$secretexists = Get-AzKeyVaultSecret -VaultName $KvName -Name $secretname -ErrorAction SilentlyContinue
if(!$secretexists){
Write-Host "$secretname is not present in $KvName"
Write-Host "Creating secret $secretname......."
Set-AzKeyVaultSecret -Name $secretname -SecretValue $secretoriginal -VaultName $kvName
if ($secretexists){
Write-Host "$secretname is created successfully"
}
}
else{Write-Host "$secretname is already present in $KvName"}
#Set-AzKeyVaultSecret -Name $secretname -SecretValue $secretoriginal -VaultName $kvName
}

$Rgexist = Get-AzResourceGroup -Name $RgName -ErrorAction SilentlyContinue
If( !$Rgexist ){
  New-AzResourceGroup -Location $Location -Name $RgName
  CreateKV $kvName
}
else{
  Write-Host "RgName already exists"
  $kvexist = Get-AzKeyVault -VaultName $kvName
  if(!$kvexist){
    CreateKV $kvName
  }
  else{
  Write-Host "$KvName already exists"

  }
}

updateKVSecret -secretname $secretname -secretoriginal $secureString

