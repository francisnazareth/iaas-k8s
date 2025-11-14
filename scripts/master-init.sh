#!/bin/bash
# Note: For Azure CNI, pods get IPs from the VNet subnet
# Remove POD_CIDR as Azure CNI uses VNet address space
CONTROL_PLANE_IP=$(hostname -I | awk '{print $1}')
swapoff -a
sed -i '/swap/d' /etc/fstab
modprobe overlay
modprobe br_netfilter
echo "br_netfilter" | tee -a /etc/modules-load.d/containerd.conf
echo "overlay" | tee /etc/modules-load.d/containerd.conf
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system
apt-get update
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
# Initialize without --pod-network-cidr for Azure CNI
kubeadm init --apiserver-advertise-address=$CONTROL_PLANE_IP --service-dns-domain=cluster.local
mkdir -p /home/azureuser/.kube
cp -i /etc/kubernetes/admin.conf /home/azureuser/.kube/config
chown azureuser:azureuser /home/azureuser/.kube/config
KUBECONFIG=/home/azureuser/.kube/config
echo "=== Step 8: Install Azure CNI ==="
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
      "mode": "bridge",
      "bridge": "azure0",
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

echo "=== Step 8a: Wait for CoreDNS to be ready ==="
kubectl --kubeconfig /home/azureuser/.kube/config wait --for=condition=ready pod -l k8s-app=kube-dns -n kube-system --timeout=300s
echo "=== Step 8b: Configure CoreDNS to forward external DNS to Azure DNS ==="
cat <<'EOFCOREDNS' | kubectl --kubeconfig /home/azureuser/.kube/config apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . 168.63.129.16
        cache 30
        loop
        reload
        loadbalance
    }
EOFCOREDNS
echo "=== Step 8c: Restart CoreDNS to apply configuration ==="
kubectl --kubeconfig /home/azureuser/.kube/config rollout restart deployment coredns -n kube-system
kubectl --kubeconfig /home/azureuser/.kube/config rollout status deployment coredns -n kube-system --timeout=120s
echo "=== Azure CNI and CoreDNS configured successfully ==="
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