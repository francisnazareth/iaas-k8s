@description('The Azure region where the VMs will be deployed')
param location string

@description('The resource ID of the subnet where VMs will be deployed')
param subnetId string

@description('Tags to apply to the VMs')
param tags object = {}

@description('The admin username for the VMs')
param adminUsername string = 'azureuser'

@description('SSH public key for VM authentication')
@secure()
param sshPublicKey string

@description('VM size/SKU')
param vmSize string = 'Standard_D4ads_v5'

type vmConfigType = {
  @description('The name of the VM')
  name: string
  @description('The computer name of the VM')
  computerName: string
}

@description('Array of VM configurations')
param vmConfigs vmConfigType[]

@description('Initialization script to run on each VM')
param initScript string = '''
echo "=== step 1: disabling swap ===".
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab
echo "=== step 2: loading kernel modules ===" 
sudo modprobe overlay
sudo modprobe br_netfilter
echo "br_netfilter" | sudo tee -a /etc/modules-load.d/containerd.conf
echo "overlay" | sudo tee /etc/modules-load.d/containerd.conf

echo "=== Step 3: Apply sysctl Settings ==="

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system

echo "=== Step 4: Install containerd ==="
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

echo "=== Step 5: Install Kubernetes v1.34 ==="
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
echo "=== Initialization script completed ==="
'''

// Create network interfaces for each VM
resource networkInterfaces 'Microsoft.Network/networkInterfaces@2024-01-01' = [for (vmConfig, i) in vmConfigs: {
  name: '${vmConfig.name}-nic'
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

// Create virtual machines
resource virtualMachines 'Microsoft.Compute/virtualMachines@2024-03-01' = [for (vmConfig, i) in vmConfigs: {
  name: vmConfig.name
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
        name: '${vmConfig.name}-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 30
      }
    }
    osProfile: {
      computerName: vmConfig.computerName
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
          id: networkInterfaces[i].id
        }
      ]
    }
  }
}]

// Deploy Custom Script Extension to run initialization script on each VM
resource vmExtensions 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = [for (vmConfig, i) in vmConfigs: {
  name: 'k8s-config'
  parent: virtualMachines[i]
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

@description('Array of VM information')
output vms array = [for (vmConfig, i) in vmConfigs: {
  name: virtualMachines[i].name
  id: virtualMachines[i].id
  privateIpAddress: networkInterfaces[i].properties.ipConfigurations[0].properties.privateIPAddress
}]
