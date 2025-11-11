@description('The Azure region where the master VM will be deployed')
param location string

@description('The resource ID of the subnet where master VM will be deployed')
param subnetId string

@description('Tags to apply to the master VM')
param tags object = {}

@description('The admin username for the VM')
param adminUsername string

@description('SSH public key for VM authentication')
@secure()
param sshPublicKey string

@description('VM size/SKU')
param vmSize string

@description('The name of the master VM')
param masterName string = 'k8s-master'

@description('Initialization script to run on master VM')
param initScript string

// Create network interface for master VM
resource masterNic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: '${masterName}-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// Create master virtual machine
resource masterVm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: masterName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: '${masterName}-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 128
      }
    }
    osProfile: {
      computerName: masterName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: masterNic.id
        }
      ]
    }
  }
}

// Deploy Custom Script Extension to run initialization script on master VM
resource masterExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  name: 'k8s-master-config'
  parent: masterVm
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {
      script: base64(initScript)
    }
  }
}

@description('Master VM name')
output name string = masterVm.name

@description('Master VM resource ID')
output id string = masterVm.id

@description('Master VM private IP address')
output privateIpAddress string = masterNic.properties.ipConfigurations[0].properties.privateIPAddress
