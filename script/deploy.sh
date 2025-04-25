#!/bin/bash
# LambdaPay Production Deployment Script
# This script deploys the LambdaPay contract to a specific network using environment variables

# Usage:
# ./scripts/deploy.sh [network] [options]
#
# Example:
# ./scripts/deploy.sh mainnet --verify

set -e  # Exit on error

NETWORK=${1:-mainnet}
SCRIPT="script/deploy/LambdaPay.s.sol:LambdaPayDeploy"
OPTIONS=""

# Check for deterministic deployment flag
USE_CREATE2=false
if [[ "$*" == *"--create2"* ]]; then
  USE_CREATE2=true
  SCRIPT="script/deploy/LambdaPayCreate2.s.sol:LambdaPayCreate2Deploy"
fi

# Check for verification flag
if [[ "$*" == *"--verify"* ]]; then
  OPTIONS+=" --verify"
fi

# Load environment variables
if [ -f ".env.$NETWORK" ]; then
  echo "Loading environment from .env.$NETWORK"
  set -a
  source .env.$NETWORK
  set +a
else
  echo "Error: Environment file .env.$NETWORK not found"
  exit 1
fi

# Print deployment info
echo "Deploying LambdaPay to $NETWORK network"
echo "RPC URL: $ETH_RPC_URL"
echo "Contract size handling: Using legacy transactions for large contracts"

if [ "$USE_CREATE2" = true ]; then
  echo "Deployment mode: CREATE2 (deterministic address)"
  
  # First get the address without deploying
  echo "Calculating expected address..."
  forge script $SCRIPT --rpc-url $ETH_RPC_URL --sig "getAddress()" -vv
  
  # Ask for confirmation
  read -p "Proceed with deployment? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment cancelled"
    exit 1
  fi
else
  echo "Deployment mode: Standard deployment"
fi

# Execute deployment
echo "Executing deployment..."
forge script $SCRIPT --rpc-url $ETH_RPC_URL --broadcast --private-key $PRIVATE_KEY $OPTIONS --legacy -vvv

echo "Deployment completed successfully" 