#!/bin/bash
set -e

echo "=== Cleaning Up Kind Cluster ==="
echo ""

# Ask for confirmation
# read -p "Are you sure you want to delete the Kind cluster? (y/N) " -n 1 -r
# echo
# if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#     echo "Cleanup cancelled."
#     exit 0
# fi

# Delete Kind cluster
echo "Deleting Kind cluster..."
kind delete cluster --name mop

echo ""
echo "SUCCESS: Cleanup complete!"
echo ""