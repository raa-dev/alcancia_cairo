#!/bin/bash

# Deployment script for Alcancia contracts
# This script reads private and public keys from .env file and deploys all contracts

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Alcancia Contracts Deployment Script ===${NC}\n"

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    exit 1
fi

# Source .env file
source .env

# Check if required variables are set
if [ -z "$ARGENT_PRIVATE_KEY" ] || [ -z "$ARGENT_PUBLIC_KEY" ]; then
    echo -e "${RED}Error: ARGENT_PRIVATE_KEY or ARGENT_PUBLIC_KEY not set in .env file!${NC}"
    exit 1
fi

echo -e "${YELLOW}Using account: ${ARGENT_PUBLIC_KEY:0:10}...${NC}\n"

# Ensure account exists in default location
mkdir -p "$HOME/.starknet_accounts"

# Create/update account file in default location (sncast expects this format)
if [ ! -f "$HOME/.starknet_accounts/starknet_open_zeppelin_accounts.json" ] || ! grep -q "argent_deployer" "$HOME/.starknet_accounts/starknet_open_zeppelin_accounts.json" 2>/dev/null; then
    cat > "$HOME/.starknet_accounts/starknet_open_zeppelin_accounts.json" << EOF
{
  "alpha-sepolia": {},
  "alpha-mainnet": {
    "argent_deployer": {
      "private_key": "$ARGENT_PRIVATE_KEY",
      "public_key": "$ARGENT_PUBLIC_KEY",
      "address": "$ARGENT_ADDRESS",
      "type": "open_zeppelin",
      "deployed": true
    }
  }
}
EOF
    echo -e "${GREEN}✓ Account file created/updated${NC}"
else
    echo -e "${GREEN}✓ Account file already exists${NC}"
fi

# Build contracts
echo -e "\n${YELLOW}Building contracts...${NC}"
scarb build
echo -e "${GREEN}✓ Contracts built successfully${NC}"

# Get the deployer address (public key)
DEPLOYER_ADDRESS=$ARGENT_ADDRESS

# Set max fee (2.5 ETH in wei) to ensure resource bounds fit within account balance
# Account has ~3.3 ETH, so 2.5 ETH leaves buffer for multiple transactions
MAX_FEE="2500000000000000000"

# Deploy contracts
echo -e "\n${YELLOW}=== Deploying Contracts ===${NC}\n"

# 1. Deploy GroupSavings
echo -e "${YELLOW}1. Deploying GroupSavings...${NC}"
echo -e "${YELLOW}   Declaring contract...${NC}"
DECLARE_OUTPUT=$(sncast --profile mainnet declare --contract-name groupsavings --max-fee $MAX_FEE 2>&1)
echo "$DECLARE_OUTPUT"

# Extract class hash - check for success or "already declared"
GROUP_SAVINGS_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -i "class hash" | sed -E 's/.*[Cc]lass[[:space:]]+[Hh]ash[[:space:]]*:[[:space:]]*(0x[0-9a-fA-F]+).*/\1/' | head -1)

# If not found in success message, try to extract from "already declared" error
if [ -z "$GROUP_SAVINGS_CLASS_HASH" ]; then
    GROUP_SAVINGS_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "Class with hash (0x[0-9a-fA-F]+)" | sed -E 's/Class with hash (0x[0-9a-fA-F]+)/\1/' | head -1)
    if [ -n "$GROUP_SAVINGS_CLASS_HASH" ]; then
        echo -e "${YELLOW}  Class already declared, using existing class hash${NC}"
    fi
fi

# If still not found, check for other errors (but not "already declared")
if [ -z "$GROUP_SAVINGS_CLASS_HASH" ]; then
    if echo "$DECLARE_OUTPUT" | grep -qi "already declared"; then
        echo -e "${RED}Class already declared but could not extract class hash${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    elif echo "$DECLARE_OUTPUT" | grep -qi "error"; then
        echo -e "${RED}Declaration failed with errors${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    else
        echo -e "${RED}Failed to get GroupSavings class hash${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}  Class Hash: $GROUP_SAVINGS_CLASS_HASH${NC}"

# Deploy GroupSavings (constructor takes admin address)
echo -e "${YELLOW}   Deploying contract...${NC}"
DEPLOY_OUTPUT=$(sncast --profile mainnet deploy \
    --class-hash $GROUP_SAVINGS_CLASS_HASH \
    --constructor-calldata $DEPLOYER_ADDRESS \
    --max-fee $MAX_FEE 2>&1)
echo "$DEPLOY_OUTPUT"
GROUP_SAVINGS_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -i "contract address" | sed -E 's/.*[Cc]ontract[[:space:]]+[Aa]ddress[[:space:]]*:[[:space:]]*(0x[0-9a-fA-F]+).*/\1/' | head -1)

if [ -z "$GROUP_SAVINGS_ADDRESS" ]; then
    echo -e "${RED}Failed to deploy GroupSavings${NC}"
    echo -e "${RED}Full output: $DEPLOY_OUTPUT${NC}"
    exit 1
fi

echo -e "${GREEN}✓ GroupSavings deployed at: $GROUP_SAVINGS_ADDRESS${NC}\n"

# 2. Deploy YieldManager
echo -e "${YELLOW}2. Deploying YieldManager...${NC}"
echo -e "${YELLOW}   Declaring contract...${NC}"
DECLARE_OUTPUT=$(sncast --profile mainnet declare --contract-name yieldmanager --max-fee $MAX_FEE 2>&1)
echo "$DECLARE_OUTPUT"

# Extract class hash - check for success or "already declared"
YIELD_MANAGER_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -i "class hash" | sed -E 's/.*[Cc]lass[[:space:]]+[Hh]ash[[:space:]]*:[[:space:]]*(0x[0-9a-fA-F]+).*/\1/' | head -1)

# If not found in success message, try to extract from "already declared" error
if [ -z "$YIELD_MANAGER_CLASS_HASH" ]; then
    YIELD_MANAGER_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "Class with hash (0x[0-9a-fA-F]+)" | sed -E 's/Class with hash (0x[0-9a-fA-F]+)/\1/' | head -1)
    if [ -n "$YIELD_MANAGER_CLASS_HASH" ]; then
        echo -e "${YELLOW}  Class already declared, using existing class hash${NC}"
    fi
fi

# If still not found, check for other errors
if [ -z "$YIELD_MANAGER_CLASS_HASH" ]; then
    if echo "$DECLARE_OUTPUT" | grep -qi "already declared"; then
        echo -e "${RED}Class already declared but could not extract class hash${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    elif echo "$DECLARE_OUTPUT" | grep -qi "error"; then
        echo -e "${RED}Declaration failed with errors${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    else
        echo -e "${RED}Failed to get YieldManager class hash${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}  Class Hash: $YIELD_MANAGER_CLASS_HASH${NC}"

# Deploy YieldManager (constructor takes admin address)
echo -e "${YELLOW}   Deploying contract...${NC}"
DEPLOY_OUTPUT=$(sncast --profile mainnet deploy \
    --class-hash $YIELD_MANAGER_CLASS_HASH \
    --constructor-calldata $DEPLOYER_ADDRESS \
    --max-fee $MAX_FEE 2>&1)
echo "$DEPLOY_OUTPUT"
YIELD_MANAGER_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -i "contract address" | sed -E 's/.*[Cc]ontract[[:space:]]+[Aa]ddress[[:space:]]*:[[:space:]]*(0x[0-9a-fA-F]+).*/\1/' | head -1)

if [ -z "$YIELD_MANAGER_ADDRESS" ]; then
    echo -e "${RED}Failed to deploy YieldManager${NC}"
    echo -e "${RED}Full output: $DEPLOY_OUTPUT${NC}"
    exit 1
fi

echo -e "${GREEN}✓ YieldManager deployed at: $YIELD_MANAGER_ADDRESS${NC}\n"

# 3. Deploy IndividualSavings
echo -e "${YELLOW}3. Deploying IndividualSavings...${NC}"
echo -e "${YELLOW}   Declaring contract...${NC}"
DECLARE_OUTPUT=$(sncast --profile mainnet declare --contract-name individualsavings --max-fee $MAX_FEE 2>&1)
echo "$DECLARE_OUTPUT"

# Extract class hash - check for success or "already declared"
INDIVIDUAL_SAVINGS_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -i "class hash" | sed -E 's/.*[Cc]lass[[:space:]]+[Hh]ash[[:space:]]*:[[:space:]]*(0x[0-9a-fA-F]+).*/\1/' | head -1)

# If not found in success message, try to extract from "already declared" error
if [ -z "$INDIVIDUAL_SAVINGS_CLASS_HASH" ]; then
    INDIVIDUAL_SAVINGS_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "Class with hash (0x[0-9a-fA-F]+)" | sed -E 's/Class with hash (0x[0-9a-fA-F]+)/\1/' | head -1)
    if [ -n "$INDIVIDUAL_SAVINGS_CLASS_HASH" ]; then
        echo -e "${YELLOW}  Class already declared, using existing class hash${NC}"
    fi
fi

# If still not found, check for other errors
if [ -z "$INDIVIDUAL_SAVINGS_CLASS_HASH" ]; then
    if echo "$DECLARE_OUTPUT" | grep -qi "already declared"; then
        echo -e "${RED}Class already declared but could not extract class hash${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    elif echo "$DECLARE_OUTPUT" | grep -qi "error"; then
        echo -e "${RED}Declaration failed with errors${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    else
        echo -e "${RED}Failed to get IndividualSavings class hash${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}  Class Hash: $INDIVIDUAL_SAVINGS_CLASS_HASH${NC}"

# Deploy IndividualSavings (constructor takes owner address)
echo -e "${YELLOW}   Deploying contract...${NC}"
DEPLOY_OUTPUT=$(sncast --profile mainnet deploy \
    --class-hash $INDIVIDUAL_SAVINGS_CLASS_HASH \
    --constructor-calldata $DEPLOYER_ADDRESS \
    --max-fee $MAX_FEE 2>&1)
echo "$DEPLOY_OUTPUT"
INDIVIDUAL_SAVINGS_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -i "contract address" | sed -E 's/.*[Cc]ontract[[:space:]]+[Aa]ddress[[:space:]]*:[[:space:]]*(0x[0-9a-fA-F]+).*/\1/' | head -1)

if [ -z "$INDIVIDUAL_SAVINGS_ADDRESS" ]; then
    echo -e "${RED}Failed to deploy IndividualSavings${NC}"
    echo -e "${RED}Full output: $DEPLOY_OUTPUT${NC}"
    exit 1
fi

echo -e "${GREEN}✓ IndividualSavings deployed at: $INDIVIDUAL_SAVINGS_ADDRESS${NC}\n"

# Save deployed addresses
cat > deployed_addresses_mainnet.txt << EOF
# Alcancia Contracts - Mainnet
# Deployed on: $(date)

GroupSavings:
  Address: $GROUP_SAVINGS_ADDRESS
  Class Hash: $GROUP_SAVINGS_CLASS_HASH

YieldManager:
  Address: $YIELD_MANAGER_ADDRESS
  Class Hash: $YIELD_MANAGER_CLASS_HASH

IndividualSavings:
  Address: $INDIVIDUAL_SAVINGS_ADDRESS
  Class Hash: $INDIVIDUAL_SAVINGS_CLASS_HASH

Deployer Address: $DEPLOYER_ADDRESS
EOF

echo -e "${GREEN}=== Deployment Complete! ===${NC}\n"
echo -e "${GREEN}Deployed addresses saved to: deployed_addresses_mainnet.txt${NC}\n"
echo -e "${YELLOW}Summary:${NC}"
echo -e "  GroupSavings:      $GROUP_SAVINGS_ADDRESS"
echo -e "  YieldManager:      $YIELD_MANAGER_ADDRESS"
echo -e "  IndividualSavings: $INDIVIDUAL_SAVINGS_ADDRESS"

