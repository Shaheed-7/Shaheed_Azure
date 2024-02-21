param(
    [string]$SourceKV = 'KV-Shaheed',
    [string]$OriginalSecretName = 'VeryImp1',
    [string]$DestinationKV = 'KV-Shaheed-Copy',
    [string]$DestinationSecretName = 'VeryImp-copy'
)


try {
    
    $sourceSecret = Get-AzKeyVaultSecret -VaultName $SourceKV -Name $OriginalSecretName -ErrorAction Stop
    $secureSecretValue = $sourceSecret.SecretValue
    $destinationSecret = Set-AzKeyVaultSecret -VaultName $DestinationKV -Name $DestinationSecretName -SecretValue $secureSecretValue -ErrorAction Stop
    Write-Output "Secret '$OriginalSecretName' from Key Vault '$SourceKV' copied successfully to Key Vault '$DestinationKV' with name '$DestinationSecretName'."
} catch {
    Write-Error "Failed to copy secret: $_"
}
