#!/bin/bash
# LambdaPay Test Deployment Script
# This script tests the deployment of LambdaPay on a local Anvil instance

# Usage:
# ./scripts/test.sh [mode]
#
# Modes:
# - standard: Test standard deployment
# - create2: Test CREATE2 deployment (default)

set -e  # Exit on error

MODE=${1:-create2}

if [ "$MODE" = "standard" ]; then
    SCRIPT="script/test/TestLambdaPay.s.sol:TestLambdaPay"
    echo "Testing standard deployment..."
elif [ "$MODE" = "create2" ]; then
    SCRIPT="script/test/TestLambdaPayCreate2.s.sol:TestLambdaPayCreate2"
    echo "Testing CREATE2 deployment..."
else
    echo "Error: Invalid mode. Use 'standard' or 'create2'"
    exit 1
fi

# Start Anvil with contract size limits disabled
echo "Starting Anvil in the background..."
anvil --block-time 1 --disable-code-size-limit > anvil.log 2>&1 &
ANVIL_PID=$!

# Give Anvil time to start and verify it's running
sleep 5
echo "Checking if Anvil is running..."
if ! curl -s -X POST http://localhost:8545 -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /dev/null; then
    echo "Error: Anvil is not running. Check anvil.log for details."
    cat anvil.log
    kill $ANVIL_PID 2>/dev/null || true
    exit 1
fi

echo "Anvil is running with PID $ANVIL_PID"
echo "Running deployment test script..."

# Run the test script with the default anvil private key
forge script $SCRIPT --rpc-url http://localhost:8545 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    --broadcast -vvv --legacy

# Check deployment exit status
DEPLOY_STATUS=$?

# Kill Anvil
echo "Stopping Anvil..."
kill $ANVIL_PID 2>/dev/null || true
wait $ANVIL_PID 2>/dev/null || true

if [ $DEPLOY_STATUS -eq 0 ]; then
    echo "✅ Test deployment completed successfully"
else
    echo "❌ Test deployment failed with status $DEPLOY_STATUS"
    if [ -f "anvil.log" ]; then
        echo "--- Anvil Logs ---"
        tail -n 20 anvil.log
    fi
fi

exit $DEPLOY_STATUS 