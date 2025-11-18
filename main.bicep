targetScope = 'subscription'

@description('The Azure region where the resource group will be deployed')
param location string = 'eastus'

@description('The name of the resource group')
param resourceGroupName string

@description('Tags to apply to the resource group')
param tags object = {}

@description('The name of the virtual network')
param vnetName string

@description('The address space for the virtual network')
param vnetAddressPrefix string

@description('The name of the Kubernetes subnet')
param k8sSubnetName string

@description('The address prefix for the Kubernetes subnet')
param k8sSubnetPrefix string

@description('The address prefix for the Azure Bastion subnet')
param bastionSubnetPrefix string

@description('The name of the Azure Bastion')
param bastionName string

@description('The SKU for Azure Bastion')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param bastionSkuName string = 'Standard'

@description('SSH public key for VM authentication')
@secure()
param sshPublicKey string

@description('Admin username for VMs')
param adminUsername string

@description('VM size for Kubernetes nodes')
param vmSize string

@description('Base name for the Key Vault (will be appended with unique suffix)')
param keyVaultBaseName string = 'kv-k8s-dev-cc'

@description('Number of worker nodes to create')
@minValue(1)
@maxValue(10)
param workerNodeCount int = 2

@description('OS disk size in GB for VMs')
@minValue(30)
@maxValue(2048)
param osDiskSizeGB int = 128

@description('Azure Arc cluster name')
param arcClusterName string = 'arc-k8s-cluster'

// Load initialization scripts from external files
var masterInitScript = loadTextContent('scripts/master-init.sh')
var workerInitScript = loadTextContent('scripts/worker-init.sh')

// Generate unique Key Vault name with random suffix
var keyVaultName = '${keyVaultBaseName}-${substring(uniqueString(subscription().id, resourceGroupName), 0, 5)}'

// Module to create the resource group
module rg './modules/resourceGroup.bicep' = {
  scope: subscription()
  params: {
    location: location
    name: resourceGroupName
    tags: tags
  }
}

// Module to create shared managed identity for all Kubernetes VMs
module k8sIdentity './modules/managedIdentity.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    identityName: 'id-k8s-vms'
    tags: tags
  }
  dependsOn: [
    rg
  ]
}

// Module to assign Contributor role to the managed identity on the resource group
module contributorRole './modules/roleAssignment.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    principalId: k8sIdentity.outputs.principalId
    roleDefinitionId: 'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor role
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    rg
  ]
}

// Module to create the virtual network
module vnet './modules/virtualNetwork.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    name: vnetName
    location: location
    addressPrefix: vnetAddressPrefix
    tags: tags
    subnets: [
      {
        name: k8sSubnetName
        addressPrefix: k8sSubnetPrefix
      }
      {
        name: 'AzureBastionSubnet'
        addressPrefix: bastionSubnetPrefix
      }
    ]
  }
  dependsOn: [
    rg
  ]
}

// Module to create Key Vault
module keyVault './modules/keyVault.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    keyVaultName: keyVaultName
    tags: tags
    tenantId: subscription().tenantId
    managedIdentityPrincipalId: k8sIdentity.outputs.principalId
    enableRbacAuthorization: true
  }
  dependsOn: [
    rg
  ]
}

// Module to create Azure Bastion
module bastion './modules/bastion.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    name: bastionName
    location: location
    bastionSubnetId: vnet.outputs.subnets[2].id
    tags: tags
    skuName: bastionSkuName
  }
}

// Module to create master node
module masterNode './modules/masterNode.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    subnetId: vnet.outputs.subnets[0].id
    tags: tags
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmSize: vmSize
    masterName: 'k8s-master'
    managedIdentityId: k8sIdentity.outputs.identityId
    osDiskSizeGB: osDiskSizeGB
    initScript: replace(replace(replace(replace(masterInitScript, '__KEY_VAULT_NAME__', keyVaultName), '__RESOURCE_GROUP_NAME__', resourceGroupName), '__ARC_CLUSTER_NAME__', arcClusterName), '__LOCATION__', location)
  }
  dependsOn: [
    keyVault
    contributorRole
  ]
}

// Module to create worker nodes as VMSS
module workerVMSS './modules/workerVMSS.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    subnetId: vnet.outputs.subnets[0].id
    tags: tags
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmSize: vmSize
    vmssName: 'vmss-k8s-workers'
    instanceCount: workerNodeCount
    managedIdentityId: k8sIdentity.outputs.identityId
    osDiskSizeGB: osDiskSizeGB
    initScript: replace(workerInitScript, '__KEY_VAULT_NAME__', keyVaultName)
  }
  dependsOn: [
    keyVault
    masterNode
  ]
}

output resourceGroupName string = rg.outputs.name
output resourceGroupId string = rg.outputs.id
output resourceGroupLocation string = rg.outputs.location
output vnetName string = vnet.outputs.name
output vnetId string = vnet.outputs.id
output subnets array = vnet.outputs.subnets
output bastionName string = bastion.outputs.name
output bastionId string = bastion.outputs.id
output bastionPublicIpAddress string = bastion.outputs.publicIpAddress
output masterNode object = {
  name: masterNode.outputs.name
  id: masterNode.outputs.id
  privateIpAddress: masterNode.outputs.privateIpAddress
}
output workerVMSS object = {
  name: workerVMSS.outputs.name
  id: workerVMSS.outputs.id
  instanceCount: workerVMSS.outputs.instanceCount
}
