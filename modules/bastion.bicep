@description('The name of the Azure Bastion')
param name string

@description('The Azure region where the Azure Bastion will be deployed')
param location string

@description('The resource ID of the Azure Bastion subnet')
param bastionSubnetId string

@description('Tags to apply to the Azure Bastion')
param tags object = {}

@description('The name of the SKU for Azure Bastion')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param skuName string

// Create a public IP for Azure Bastion
resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: 'pip-${name}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Create Azure Bastion
resource bastionHost 'Microsoft.Network/bastionHosts@2024-01-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
}

@description('The name of the Azure Bastion')
output name string = bastionHost.name

@description('The resource ID of the Azure Bastion')
output id string = bastionHost.id

@description('The public IP address ID of the Azure Bastion')
output publicIpId string = bastionPublicIp.id

@description('The public IP address of the Azure Bastion')
output publicIpAddress string = bastionPublicIp.properties.ipAddress
