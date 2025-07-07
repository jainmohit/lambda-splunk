#!/bin/bash

# Script to destroy the infrastructure

set -e

echo "🗑️  Destroying API Cron Job Infrastructure..."

# Confirm destruction
read -p "Are you sure you want to destroy all resources? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Destruction cancelled."
    exit 1
fi

# Destroy infrastructure
echo "💥 Destroying infrastructure..."
terraform destroy -auto-approve

echo "✅ Infrastructure destroyed successfully!"
