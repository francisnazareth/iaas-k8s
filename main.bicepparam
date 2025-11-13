using './main.bicep'

param location = 'eastus2'
param resourceGroupName = 'rg-k8s-dev-eu-01'
param vnetName = 'vnet-k8s-dev-eu-01'
param vnetAddressPrefix = '10.0.0.0/20'
param k8sSubnetName = 'snet-k8s'
param k8sSubnetPrefix = '10.0.0.0/24'
param bastionSubnetPrefix = '10.0.1.0/26'
param bastionName = 'bastion-k8s-dev-eu-01'
param bastionSkuName = 'Standard'
param keyVaultBaseName = 'kv-k8s-dev-eu'
param adminUsername = 'azureuser'
param vmSize = 'Standard_D4ds_v4'
param workerNodeCount = 3
param osDiskSizeGB = 128
param sshPublicKey = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDcK945AY0BUVDFbObXAx5eRXNcFemXqSYx9kLRLjRPewT3oYcqOwxdG248UsHuzgDR+vJ03ckRrfrU8UGOUeyp1W/58J+AvYLnVJY/IM4H4IXCDpVJJahyPeAoE+dLjjjDUroWEMK6xyKq2nAadgyMv4ZrmI5J+aeHt1HMCh7tFEBTwPioX1F1Ko1Vp5h4JjPu5eGdPwkZhzF15NtzLsD1oQMP5tJhPm3CYT9CFOe0yYgLIYIpzwCK1p6ieGn+W7pIdnXgfl33MfklbRz6J0pX5ON2/UUGPA+nTWS5X6HxqO4D0AOrbmMV0qIZbGYa8BkaPRn0WvTOd5fVx3HnEuCJ francis@SandboxHost-638984344195749261'
param tags = {
  environment: 'dev'
  project: 'containers-infra'
}
