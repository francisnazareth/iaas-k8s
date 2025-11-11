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

@description('Initialization script for master node')
param masterInitScript string
param workerInitScript string

// Module to create the resource group
module rg './modules/resourceGroup.bicep' = {
  scope: subscription()
  params: {
    location: location
    name: resourceGroupName
    tags: tags
  }
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

// Module to create Azure Bastion
module bastion './modules/bastion.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    name: bastionName
    location: location
    bastionSubnetId: vnet.outputs.subnets[1].id
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
    initScript: masterInitScript
  }
}

// Module to create worker nodes
module workerNodes './modules/workerNodes.bicep' = {
  scope: resourceGroup(resourceGroupName)
  params: {
    location: location
    subnetId: vnet.outputs.subnets[0].id
    tags: tags
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmSize: vmSize
    workerNames: [
      'k8s-worker1'
      'k8s-worker2'
    ]
    initScript: workerInitScript
  }
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
output workerNodes array = workerNodes.outputs.workers
