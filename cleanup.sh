#!/bin/bash

set -e

# Check if minikube is running
if minikube status &>/dev/null; then
  # Remove the Helm release
  echo "📦 Removing Helm release..."
  helm uninstall template-k8s 2>/dev/null || echo "Release not found, continuing..."
fi

# Delete Minikube cluster completely
echo "�️  Deleting Minikube cluster..."
minikube delete

echo "✅ Cleanup completed!"
