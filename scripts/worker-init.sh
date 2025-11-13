#!/bin/bash
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
echo "=== Step 10: Wait for node to be ready and apply label ==="
NODE_NAME=$(hostname)
sleep 15
# Label the node with workload=app1
MAX_LABEL_RETRIES=10
LABEL_RETRY_COUNT=0
while [ $LABEL_RETRY_COUNT -lt $MAX_LABEL_RETRIES ]; do
  if kubectl label node $NODE_NAME workload=app1 --overwrite --kubeconfig=/dev/null 2>/dev/null || \
     ssh -o StrictHostKeyChecking=no azureuser@k8s-master "kubectl label node $NODE_NAME workload=app1 --overwrite" 2>/dev/null; then
    echo "Successfully labeled node $NODE_NAME with workload=app1"
    break
  fi
  echo "Waiting to label node... (attempt $((LABEL_RETRY_COUNT+1))/$MAX_LABEL_RETRIES)"
  sleep 10
  LABEL_RETRY_COUNT=$((LABEL_RETRY_COUNT+1))
done
echo "=== Worker node successfully joined the cluster ==="
