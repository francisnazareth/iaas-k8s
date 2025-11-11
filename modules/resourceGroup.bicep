targetScope = 'subscription'

@description('The name of the resource group')
param name string

@description('The Azure region where the resource group will be deployed')
param location string

@description('Tags to apply to the resource group')
param tags object = {}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: name
  location: location
  tags: tags
}

@description('The name of the resource group')
output name string = resourceGroup.name

@description('The resource ID of the resource group')
output id string = resourceGroup.id

@description('The location of the resource group')
output location string = resourceGroup.location
