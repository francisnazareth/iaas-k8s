#!/bin/bash
# Disable swap
swapoff -a
sed -i '/swap/d' /etc/fstab
# Load required kernel modules
modprobe overlay
modprobe br_netfilter
echo "br_netfilter" | tee -a /etc/modules-load.d/containerd.conf
echo "overlay" | tee -a /etc/modules-load.d/containerd.conf

# Configure sysctl for Kubernetes networking
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
# Install containerd
apt-get update
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# Install Kubernetes components
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "=== Installing Azure CNI ==="
# Download and install Azure CNI plugin
wget https://github.com/Azure/azure-container-networking/releases/download/v1.5.36/azure-vnet-cni-linux-amd64-v1.5.36.tgz -O /tmp/azure-vnet-cni.tgz
mkdir -p /opt/cni/bin
tar -xzf /tmp/azure-vnet-cni.tgz -C /opt/cni/bin
chmod +x /opt/cni/bin/*
# Create Azure CNI configuration
mkdir -p /etc/cni/net.d
cat <<EOFCNI > /etc/cni/net.d/10-azure.conflist
{
  "cniVersion": "0.3.0",
  "name": "azure",
  "plugins": [
    {
      "type": "azure-vnet",
      "mode": "transparent",
      "ipam": {
        "type": "azure-vnet-ipam"
      }
    },
    {
      "type": "portmap",
      "capabilities": {
        "portMappings": true
      },
      "snat": true
    }
  ]
}
EOFCNI
# Ensure kubelet uses CNI
if ! grep -q -- "--network-plugin=cni" /var/lib/kubelet/kubeadm-flags.env; then
  sed -i 's/$/ --network-plugin=cni/' /var/lib/kubelet/kubeadm-flags.env
fi
# Restart kubelet to pick up CNI configuration
echo "=== Restarting kubelet ==="
systemctl restart kubelet
echo "=== Step 7: Install Azure CLI ==="
curl -sL https://aka.ms/InstallAzureCLIDeb | bash
echo "=== Step 8: Login to Azure using managed identity ==="
az login --identity
echo "=== Step 9: Retrieve join command from Key Vault ==="
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
echo "=== Step 10: Join the Kubernetes cluster ==="
eval $JOIN_COMMAND
echo "=== Worker node successfully joined the cluster ==="