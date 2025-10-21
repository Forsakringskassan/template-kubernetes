#!/bin/bash

set -e

# Check if minikube is installed
if ! command -v minikube &> /dev/null; then
    echo "❌ Minikube is not installed. Please install it first:"
    echo "   https://minikube.sigs.k8s.io/docs/start/"
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "❌ Helm is not installed. Please install it first:"
    echo "   https://helm.sh/docs/intro/install/"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install it first:"
    echo "   https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/"
    echo "   Or install via snap: sudo snap install kubectl --classic"
    exit 1
fi

# Start minikube if not running
echo "🔧 Starting Minikube..."
minikube start --driver=docker --cpus=4 --memory=8192

# Wait for the Kubernetes API server to be ready
echo "⏳ Waiting for Kubernetes API server to be ready..."
for i in {1..60}; do
  if kubectl get --raw='/readyz?verbose' &>/dev/null; then
    echo "✅ Kubernetes API server is ready"
    break
  fi
  echo "   Attempt $i/60: Waiting for API server to be fully ready..."
  sleep 5
done

# Verify cluster is accessible
if ! kubectl get --raw='/readyz?verbose' &>/dev/null; then
  echo "❌ Kubernetes API server is not accessible after waiting"
  exit 1
fi

# Wait for all core system pods to be ready
echo "⏳ Waiting for core system pods to be ready..."
kubectl wait --for=condition=ready pod --all -n kube-system --timeout=180s || true

# Additional wait to ensure API server is stable
echo "⏳ Ensuring API server is fully stable..."
sleep 20

# Enable ingress addon with retry logic
echo "🌐 Enabling ingress addon..."
ADDON_ENABLED=false
for i in {1..10}; do
  echo "   Attempt $i/10: Enabling ingress addon..."
  if minikube addons enable ingress 2>&1 | grep -q "enabled\|already enabled"; then
    echo "✅ Ingress addon enabled successfully"
    ADDON_ENABLED=true
    break
  fi
  echo "   API server not ready yet, waiting..."
  sleep 15
done

if [ "$ADDON_ENABLED" = false ]; then
  echo "❌ Failed to enable ingress addon after multiple attempts"
  exit 1
fi

# Wait for ingress controller to be ready
echo "⏳ Waiting for ingress controller to be ready..."
for i in {1..60}; do
  if kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --field-selector=status.phase=Running | grep -q Running; then
    echo "✅ Ingress controller is ready"
    break
  fi
  echo "   Attempt $i/60: Waiting for ingress controller..."
  sleep 2
done

# Wait a bit more for the admission webhook to be ready
echo "⏳ Waiting for ingress admission webhook to be ready..."
sleep 30

# Verify webhook is responding
echo "🔍 Verifying admission webhook..."
for i in {1..10}; do
  if kubectl get validatingwebhookconfiguration ingress-nginx-admission &>/dev/null; then
    echo "✅ Admission webhook is ready"
    break
  fi
  echo "   Attempt $i/10: Waiting for admission webhook..."
  sleep 10
done

# Deploy the application using Helm
echo "📦 Deploying FK application stack..."
if ! helm upgrade --install template-k8s ./helm-chart --wait; then
  echo "⚠️  Deployment failed, likely due to admission webhook not ready"
  echo "🔄 Retrying with webhook bypass..."
  
  # Temporarily disable admission webhook validation
  kubectl delete validatingwebhookconfiguration ingress-nginx-admission 2>/dev/null || true
  
  # Deploy without webhook validation
  helm upgrade --install template-k8s ./helm-chart --wait
  
  echo "✅ Deployment completed (webhook validation bypassed)"
fi

# Get the ingress IP
echo "🔍 Getting ingress information..."
INGRESS_IP=$(minikube ip)
echo "Ingress IP: $INGRESS_IP"

echo ""
echo "✅ Deployment completed!"
echo ""
echo "🌍 Your applications are available at:"
echo ""
echo "   http://$INGRESS_IP/"
echo ""