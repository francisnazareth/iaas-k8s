@description('The Azure region where the worker VMSS will be deployed')
param location string

@description('The resource ID of the subnet where worker VMSS will be deployed')
param subnetId string

@description('Tags to apply to the worker VMSS')
param tags object = {}

@description('The admin username for the VMs')
param adminUsername string

@description('SSH public key for VM authentication')
@secure()
param sshPublicKey string

@description('VM size/SKU')
param vmSize string

@description('Name of the VMSS')
param vmssName string = 'vmss-k8s-workers'

@description('Number of worker node instances')
param instanceCount int = 2

@description('The resource ID of the managed identity to use')
param managedIdentityId string

@description('OS disk size in GB')
param osDiskSizeGB int = 128

@description('Initialization script to run on worker VMs')
param initScript string

// Create Virtual Machine Scale Set for worker nodes
resource workerVMSS 'Microsoft.Compute/virtualMachineScaleSets@2024-03-01' = {
  name: vmssName
  location: location
  tags: tags
  sku: {
    name: vmSize
    tier: 'Standard'
    capacity: instanceCount
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Manual'
    }
    singlePlacementGroup: true
    virtualMachineProfile: {
      storageProfile: {
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
          diskSizeGB: osDiskSizeGB
        }
      }
      osProfile: {
        computerNamePrefix: 'k8s-worker'
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
        networkInterfaceConfigurations: [
          {
            name: 'worker-nic'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: subnetId
                    }
                  }
                }
              ]
            }
          }
        ]
      }
      extensionProfile: {
        extensions: [
          {
            name: 'k8s-worker-config'
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
        ]
      }
    }
  }
}

@description('VMSS name')
output name string = workerVMSS.name

@description('VMSS resource ID')
output id string = workerVMSS.id

@description('VMSS instance count')
output instanceCount int = workerVMSS.sku.capacity
