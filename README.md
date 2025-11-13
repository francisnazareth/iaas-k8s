# Kubernetes Cluster (IAAS) on Azure

This repository contains Bicep templates to deploy a Kubernetes cluster on Azure using Infrastructure as Code (IaC).

## Features 

- Single command based installation for the cluster. 
- Worker nodes are provisioned through a virtual machine scale set.
- If you scale up the scale-set, worker nodes automatically join the kubernetes cluster. 
- In-bound access can be controlled by internal load balancer.
- Outbound traffic can be routed through Firewall, using Route Tables. 

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
- Generate SSH Keys
  ```ssh-keygen -m PEM -t rsa -b 2048```
- Copy the contents of public key to line 14 (sshPublicKey) in main.bicepparam
- Store the private key. This key will be needed to login to virtual machines. 
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
Once the script finishes execution, login to the master VM using Azure bastion.  
  -- Authentication Type:  SSH Private Key from Local File. 
  -- User name: azureuser 
  -- use the private key 

- On master node, verify that all nodes are ready by executing the command
```
kubectl get nodes
```
- The output should resemble the following:
```
NAME          STATUS   ROLES           AGE    VERSION
k8s-master    Ready    control-plane   152m   v1.34.1
k8s-worker1   Ready    <none>          39m    v1.34.1
k8s-worker2   Ready    <none>          28m    v1.34.1
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