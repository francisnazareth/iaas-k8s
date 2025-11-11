@description('The name of the virtual network')
param name string

@description('The Azure region where the virtual network will be deployed')
param location string

@description('The address space for the virtual network')
param addressPrefix string

@description('Tags to apply to the virtual network')
param tags object = {}

type subnetType = {
  @description('The name of the subnet')
  name: string
  @description('The address prefix for the subnet')
  addressPrefix: string
}

@description('Array of subnets to create')
param subnets subnetType[]

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [for subnet in subnets: {
      name: subnet.name
      properties: {
        addressPrefix: subnet.addressPrefix
      }
    }]
  }
}

@description('The name of the virtual network')
output name string = virtualNetwork.name

@description('The resource ID of the virtual network')
output id string = virtualNetwork.id

@description('The subnets in the virtual network')
output subnets array = [for (subnet, i) in subnets: {
  name: virtualNetwork.properties.subnets[i].name
  id: virtualNetwork.properties.subnets[i].id
  addressPrefix: virtualNetwork.properties.subnets[i].properties.addressPrefix
}]
