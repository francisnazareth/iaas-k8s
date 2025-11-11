# Kubernetes Infrastructure on Azure

This repository contains Bicep templates to deploy a Kubernetes infrastructure on Azure using Infrastructure as Code (IaC).

## Architecture

The deployment creates the following resources:

- **Resource Group**: Container for all Azure resources
- **Virtual Network**: 10.0.0.0/20 address space with two subnets:
  - `snet-k8s` (10.0.0.0/24): For Kubernetes nodes
  - `AzureBastionSubnet` (10.0.1.0/26): For Azure Bastion
- **Azure Bastion**: Secure RDP/SSH connectivity (Standard SKU)
- **Virtual Machines**:
  - 1x Master node (k8s-master)
  - 2x Worker nodes (k8s-worker1, k8s-worker2)
  - All VMs: Ubuntu 22.04 LTS, Standard_D4ads_v5 (4 vCPUs, 16 GB RAM)

## Prerequisites

- Azure CLI installed
- Azure subscription
- SSH key pair generated (stored in C:\Users\fnazaret\Downloads\)

## Project Structure

```
.
├── main.bicep                      # Main orchestration template
├── main.bicepparam                 # Parameters file
├── modules/
│   ├── resourceGroup.bicep        # Resource group module
│   ├── virtualNetwork.bicep       # Virtual network module
│   ├── bastion.bicep              # Azure Bastion module
│   ├── masterNode.bicep           # Master node VM module
│   └── workerNodes.bicep          # Worker nodes VMs module
└── k8s-config.sh                  # Kubernetes initialization script
```

## Deployment

Deploy the infrastructure using Azure CLI:

```powershell
az deployment sub create --name k8s --location canadacentral --template-file main.bicep --parameters .\main.bicepparam
```

## Configuration

### Initialization Scripts

The deployment uses custom scripts to configure each VM:

- **Master Init Script**: Configures the Kubernetes master node
- **Worker Init Script**: Configures the Kubernetes worker nodes

Both scripts:
1. Disable swap
2. Load required kernel modules (overlay, br_netfilter)
3. Configure sysctl settings for Kubernetes networking
4. Install and configure containerd runtime
5. Install Kubernetes components (kubelet, kubeadm, kubectl) v1.34

### Customization

Edit `main.bicepparam` to customize:
- Location (default: canadacentral)
- VM sizes
- Network address spaces
- Resource naming
- Initialization scripts

## Access

Connect to VMs via Azure Bastion using SSH with your private key:

```bash
ssh -i /path/to/id_rsa azureuser@<vm-private-ip>
```

## Clean Up

To delete all resources:

```powershell
az group delete --name rg-k8s-dev-cc-01 --yes
```

## License

MIT
