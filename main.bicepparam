using './main.bicep'

param location = 'canadacentral'
param resourceGroupName = 'rg-k8s-dev-cc-01'
param vnetName = 'vnet-k8s-dev-cc-01'
param vnetAddressPrefix = '10.0.0.0/20'
param k8sSubnetName = 'snet-k8s'
param k8sSubnetPrefix = '10.0.0.0/24'
param bastionSubnetPrefix = '10.0.1.0/26'
param bastionName = 'bastion-k8s-dev-cc-01'
param bastionSkuName = 'Standard'
param keyVaultBaseName = 'kv-k8s-dev-cc'
param adminUsername = 'azureuser'
param vmSize = 'Standard_D4ads_v5'
param workerNodeCount = 3
param osDiskSizeGB = 128
param sshPublicKey = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDcK945AY0BUVDFbObXAx5eRXNcFemXqSYx9kLRLjRPewT3oYcqOwxdG248UsHuzgDR+vJ03ckRrfrU8UGOUeyp1W/58J+AvYLnVJY/IM4H4IXCDpVJJahyPeAoE+dLjjjDUroWEMK6xyKq2nAadgyMv4ZrmI5J+aeHt1HMCh7tFEBTwPioX1F1Ko1Vp5h4JjPu5eGdPwkZhzF15NtzLsD1oQMP5tJhPm3CYT9CFOe0yYgLIYIpzwCK1p6ieGn+W7pIdnXgfl33MfklbRz6J0pX5ON2/UUGPA+nTWS5X6HxqO4D0AOrbmMV0qIZbGYa8BkaPRn0WvTOd5fVx3HnEuCJ francis@SandboxHost-638984344195749261'
param tags = {
  environment: 'dev'
  project: 'containers-infra'
}

param masterInitScript = '''
POD_CIDR="192.168.0.0/16"
CONTROL_PLANE_IP=$(hostname -I | awk '{print $1}')
echo "=== step 1: disabling swap ==="
swapoff -a
sed -i '/swap/d' /etc/fstab
echo "=== step 2: loading kernel modules ==="
modprobe overlay
modprobe br_netfilter
echo "br_netfilter" | tee -a /etc/modules-load.d/containerd.conf
echo "overlay" | tee /etc/modules-load.d/containerd.conf
echo "=== Step 3: Apply sysctl Settings ==="
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
echo "=== Step 4: Install containerd ==="
apt-get update
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd
echo "=== Step 5: Install Kubernetes v1.34 ==="
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
echo "=== Step 6: Initialize Control Plane ==="
kubeadm init --apiserver-advertise-address=$CONTROL_PLANE_IP --pod-network-cidr=$POD_CIDR
echo "=== Master node initialization script completed ==="
echo "=== Step 7: Configure kubectl for current user ==="
mkdir -p /home/azureuser/.kube
cp -i /etc/kubernetes/admin.conf /home/azureuser/.kube/config
chown azureuser:azureuser /home/azureuser/.kube/config
KUBECONFIG=/home/azureuser/.kube/config
echo "=== Step 8: Install Calico CNI ==="
kubectl  --kubeconfig /home/azureuser/.kube/config apply -f https://docs.projectcalico.org/manifests/calico.yaml
echo "=== Step 9: Install Azure CLI ==="
curl -sL https://aka.ms/InstallAzureCLIDeb | bash
echo "=== Step 10: Login to Azure using managed identity ==="
az login --identity
echo "=== Step 11: Wait for Key Vault permissions to propagate ==="
sleep 30
echo "=== Step 12: Generate and store kubeadm join command in Key Vault ==="
JOIN_COMMAND=$(kubeadm token create --print-join-command)
MAX_RETRIES=5
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if az keyvault secret set --vault-name __KEY_VAULT_NAME__ --name "kubeadm-join-command" --value "$JOIN_COMMAND" 2>/dev/null; then
    echo "Join command successfully stored in Key Vault"
    break
  fi
  echo "Failed to store secret in Key Vault (attempt $((RETRY_COUNT+1))/$MAX_RETRIES). Retrying in 10 seconds..."
  sleep 10
  RETRY_COUNT=$((RETRY_COUNT+1))
done
if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "ERROR: Failed to store join command in Key Vault after $MAX_RETRIES attempts"
  echo "WARNING: Worker nodes will not be able to join the cluster automatically"
fi
echo "=== Master node setup completed ==="
'''
param workerInitScript = '''
echo "=== step 1: disabling swap ===".
swapoff -a
sed -i '/swap/d' /etc/fstab
echo "=== step 2: loading kernel modules ===" 
modprobe overlay
modprobe br_netfilter
echo "br_netfilter" | tee -a /etc/modules-load.d/containerd.conf
echo "overlay" | tee /etc/modules-load.d/containerd.conf
echo "=== Step 3: Apply sysctl Settings ==="
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
echo "=== Step 4: Install containerd ==="
apt-get update
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd
echo "=== Step 5: Install Kubernetes v1.34 ==="
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
echo "=== Step 6: Install Azure CLI ==="
curl -sL https://aka.ms/InstallAzureCLIDeb | bash
echo "=== Step 7: Login to Azure using managed identity ==="
az login --identity
echo "=== Step 8: Retrieve join command from Key Vault ==="
# Wait for the join command to be available (master node might still be initializing)
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  JOIN_COMMAND=$(az keyvault secret show --vault-name __KEY_VAULT_NAME__ --name "kubeadm-join-command" --query value -o tsv 2>/dev/null)
  if [ -n "$JOIN_COMMAND" ]; then
    echo "Join command retrieved successfully"
    break
  fi
  echo "Waiting for join command to be available... (attempt $((RETRY_COUNT+1))/$MAX_RETRIES)"
  sleep 10
  RETRY_COUNT=$((RETRY_COUNT+1))
done
if [ -z "$JOIN_COMMAND" ]; then
  echo "ERROR: Failed to retrieve join command from Key Vault after $MAX_RETRIES attempts"
  exit 1
fi
echo "=== Step 9: Join the Kubernetes cluster ==="
eval $JOIN_COMMAND
echo "=== Worker node successfully joined the cluster ==="
'''
