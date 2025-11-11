@description('The Azure region where the worker VMs will be deployed')
param location string

@description('The resource ID of the subnet where worker VMs will be deployed')
param subnetId string

@description('Tags to apply to the worker VMs')
param tags object = {}

@description('The admin username for the VMs')
param adminUsername string = 'azureuser'

@description('SSH public key for VM authentication')
@secure()
param sshPublicKey string

@description('VM size/SKU')
param vmSize string = 'Standard_D4ads_v5'

@description('Array of worker VM names')
param workerNames array = [
  'k8s-worker1'
  'k8s-worker2'
]

@description('Initialization script to run on worker VMs')
param initScript string

// Create network interfaces for worker VMs
resource workerNics 'Microsoft.Network/networkInterfaces@2024-01-01' = [for (workerName, i) in workerNames: {
  name: '${workerName}-nic'
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
}]

// Create worker virtual machines
resource workerVms 'Microsoft.Compute/virtualMachines@2024-03-01' = [for (workerName, i) in workerNames: {
  name: workerName
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
        name: '${workerName}-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 30
      }
    }
    osProfile: {
      computerName: workerName
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
          id: workerNics[i].id
        }
      ]
    }
  }
}]

// Deploy Custom Script Extension to run initialization script on worker VMs
resource workerExtensions 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (workerName, i) in workerNames: {
  name: 'k8s-worker-config'
  parent: workerVms[i]
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
}]

@description('Array of worker VM information')
output workers array = [for (workerName, i) in workerNames: {
  name: workerVms[i].name
  id: workerVms[i].id
  privateIpAddress: workerNics[i].properties.ipConfigurations[0].properties.privateIPAddress
}]
