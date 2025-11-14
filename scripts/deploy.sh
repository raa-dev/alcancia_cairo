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

# Set max fee (3.5 STRK in wei) to ensure resource bounds fit within account balance
# Increased from 2.5 STRK to accommodate IndividualSavings declaration (~2.89 STRK)
# Account should have sufficient balance for all deployments
MAX_FEE="3500000000000000000"

# Function to declare contract with retry logic for network errors
declare_contract_with_retry() {
    local contract_name=$1
    local max_retries=3
    local retry_count=0
    local declare_output=""
    
    while [ $retry_count -lt $max_retries ]; do
        echo -e "${YELLOW}   Attempt $((retry_count + 1))/$max_retries: Declaring contract...${NC}"
        declare_output=$(sncast --profile mainnet declare --contract-name "$contract_name" --max-fee $MAX_FEE 2>&1 || true)
        
        # Check if it's a network/transport error (retryable)
        if echo "$declare_output" | grep -qi "TransportError\|IncompleteMessage\|Request.*timeout\|connection.*refused"; then
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                echo -e "${YELLOW}   Network error detected, retrying in 5 seconds...${NC}"
                sleep 5
                continue
            else
                echo -e "${RED}   Network error after $max_retries attempts${NC}"
                echo "$declare_output"
                return 1
            fi
        else
            # Not a network error, return the output
            echo "$declare_output"
            return 0
        fi
    done
}

# Deploy contracts
echo -e "\n${YELLOW}=== Deploying Contracts ===${NC}\n"

# 1. Deploy GroupSavings
echo -e "${YELLOW}1. Deploying GroupSavings...${NC}"
DECLARE_OUTPUT=$(declare_contract_with_retry "groupsavings")
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to declare GroupSavings after retries${NC}"
    exit 1
fi
echo "$DECLARE_OUTPUT"

# Extract class hash - check for success or "already declared"
GROUP_SAVINGS_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -i "class hash" | sed -E 's/.*[Cc]lass[[:space:]]+[Hh]ash[[:space:]]*:[[:space:]]*(0x[0-9a-fA-F]+).*/\1/' | head -1)

# If not found in success message, try to extract from "already declared" error
if [ -z "$GROUP_SAVINGS_CLASS_HASH" ]; then
    # Try multiple patterns to extract class hash from error messages
    GROUP_SAVINGS_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "Class with hash (0x[0-9a-fA-F]+)" | sed -E 's/Class with hash (0x[0-9a-fA-F]+)/\1/' | head -1)
    # Also try extracting any 66-character hex string (0x + 64 hex chars)
    if [ -z "$GROUP_SAVINGS_CLASS_HASH" ]; then
        GROUP_SAVINGS_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "0x[0-9a-fA-F]{64}" | head -1)
    fi
    if [ -n "$GROUP_SAVINGS_CLASS_HASH" ]; then
        echo -e "${YELLOW}  Class already declared, using existing class hash${NC}"
    fi
fi

# If still not found, check for other errors (but not "already declared")
if [ -z "$GROUP_SAVINGS_CLASS_HASH" ]; then
    if echo "$DECLARE_OUTPUT" | grep -qi "already declared"; then
        # Try to extract class hash from "already declared" message
        GROUP_SAVINGS_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "0x[0-9a-fA-F]{64}" | head -1)
        if [ -n "$GROUP_SAVINGS_CLASS_HASH" ]; then
            echo -e "${YELLOW}  Class already declared, using existing class hash${NC}"
        else
            echo -e "${RED}Class already declared but could not extract class hash${NC}"
            echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
            exit 1
        fi
    elif echo "$DECLARE_OUTPUT" | grep -qi "TransportError\|IncompleteMessage"; then
        # Network error that wasn't caught by retry - this shouldn't happen but handle it
        echo -e "${RED}Network error persisted after retries${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    elif echo "$DECLARE_OUTPUT" | grep -qi "error\|panic\|Failed"; then
        # Other errors - check if it's a validation/balance error
        if echo "$DECLARE_OUTPUT" | grep -qi "exceed balance\|ValidateFailure"; then
            echo -e "${RED}Insufficient balance or validation failure${NC}"
            echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
            exit 1
        else
            echo -e "${RED}Declaration failed with errors${NC}"
            echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Failed to get GroupSavings class hash${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}  Class Hash: $GROUP_SAVINGS_CLASS_HASH${NC}"

# If this was a new declaration (not already declared), wait for it to be confirmed
if echo "$DECLARE_OUTPUT" | grep -qi "Success: Declaration completed"; then
    echo -e "${YELLOW}   Waiting for declaration to be confirmed on-chain (30 seconds)...${NC}"
    sleep 30
fi

# Deploy GroupSavings (constructor takes admin address)
echo -e "${YELLOW}   Deploying contract...${NC}"
DEPLOY_OUTPUT=$(sncast --profile mainnet deploy \
    --class-hash $GROUP_SAVINGS_CLASS_HASH \
    --constructor-calldata $DEPLOYER_ADDRESS \
    --max-fee $MAX_FEE 2>&1 | tee /dev/stderr)
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
DECLARE_OUTPUT=$(declare_contract_with_retry "yieldmanager")
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to declare YieldManager after retries${NC}"
    exit 1
fi
echo "$DECLARE_OUTPUT"

# Extract class hash - check for success or "already declared"
YIELD_MANAGER_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -i "class hash" | sed -E 's/.*[Cc]lass[[:space:]]+[Hh]ash[[:space:]]*:[[:space:]]*(0x[0-9a-fA-F]+).*/\1/' | head -1)

# If not found in success message, try to extract from "already declared" error
if [ -z "$YIELD_MANAGER_CLASS_HASH" ]; then
    # Try multiple patterns to extract class hash from error messages
    YIELD_MANAGER_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "Class with hash (0x[0-9a-fA-F]+)" | sed -E 's/Class with hash (0x[0-9a-fA-F]+)/\1/' | head -1)
    # Also try extracting any 66-character hex string (0x + 64 hex chars)
    if [ -z "$YIELD_MANAGER_CLASS_HASH" ]; then
        YIELD_MANAGER_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "0x[0-9a-fA-F]{64}" | head -1)
    fi
    if [ -n "$YIELD_MANAGER_CLASS_HASH" ]; then
        echo -e "${YELLOW}  Class already declared, using existing class hash${NC}"
    fi
fi

# If still not found, check for other errors
if [ -z "$YIELD_MANAGER_CLASS_HASH" ]; then
    if echo "$DECLARE_OUTPUT" | grep -qi "already declared"; then
        # Try to extract class hash from "already declared" message
        YIELD_MANAGER_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "0x[0-9a-fA-F]{64}" | head -1)
        if [ -n "$YIELD_MANAGER_CLASS_HASH" ]; then
            echo -e "${YELLOW}  Class already declared, using existing class hash${NC}"
        else
            echo -e "${RED}Class already declared but could not extract class hash${NC}"
            echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
            exit 1
        fi
    elif echo "$DECLARE_OUTPUT" | grep -qi "TransportError\|IncompleteMessage"; then
        # Network error that wasn't caught by retry - this shouldn't happen but handle it
        echo -e "${RED}Network error persisted after retries${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    elif echo "$DECLARE_OUTPUT" | grep -qi "error\|panic\|Failed"; then
        # Other errors - check if it's a validation/balance error
        if echo "$DECLARE_OUTPUT" | grep -qi "exceed balance\|ValidateFailure"; then
            echo -e "${RED}Insufficient balance or validation failure${NC}"
            echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
            exit 1
        else
            echo -e "${RED}Declaration failed with errors${NC}"
            echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Failed to get YieldManager class hash${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}  Class Hash: $YIELD_MANAGER_CLASS_HASH${NC}"

# If this was a new declaration (not already declared), wait for it to be confirmed
if echo "$DECLARE_OUTPUT" | grep -qi "Success: Declaration completed"; then
    echo -e "${YELLOW}   Waiting for declaration to be confirmed on-chain (30 seconds)...${NC}"
    sleep 30
fi

# Deploy YieldManager (constructor takes admin address)
echo -e "${YELLOW}   Deploying contract...${NC}"
DEPLOY_OUTPUT=$(sncast --profile mainnet deploy \
    --class-hash $YIELD_MANAGER_CLASS_HASH \
    --constructor-calldata $DEPLOYER_ADDRESS \
    --max-fee $MAX_FEE 2>&1 | tee /dev/stderr)
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
DECLARE_OUTPUT=$(declare_contract_with_retry "individualsavings")
if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to declare IndividualSavings after retries${NC}"
    exit 1
fi
echo "$DECLARE_OUTPUT"

# Extract class hash - check for success or "already declared"
INDIVIDUAL_SAVINGS_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -i "class hash" | sed -E 's/.*[Cc]lass[[:space:]]+[Hh]ash[[:space:]]*:[[:space:]]*(0x[0-9a-fA-F]+).*/\1/' | head -1)

# If not found in success message, try to extract from "already declared" error
if [ -z "$INDIVIDUAL_SAVINGS_CLASS_HASH" ]; then
    # Try multiple patterns to extract class hash from error messages
    INDIVIDUAL_SAVINGS_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "Class with hash (0x[0-9a-fA-F]+)" | sed -E 's/Class with hash (0x[0-9a-fA-F]+)/\1/' | head -1)
    # Also try extracting any 66-character hex string (0x + 64 hex chars)
    if [ -z "$INDIVIDUAL_SAVINGS_CLASS_HASH" ]; then
        INDIVIDUAL_SAVINGS_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "0x[0-9a-fA-F]{64}" | head -1)
    fi
    if [ -n "$INDIVIDUAL_SAVINGS_CLASS_HASH" ]; then
        echo -e "${YELLOW}  Class already declared, using existing class hash${NC}"
    fi
fi

# If still not found, check for other errors
if [ -z "$INDIVIDUAL_SAVINGS_CLASS_HASH" ]; then
    if echo "$DECLARE_OUTPUT" | grep -qi "already declared"; then
        # Try to extract class hash from "already declared" message
        INDIVIDUAL_SAVINGS_CLASS_HASH=$(echo "$DECLARE_OUTPUT" | grep -oE "0x[0-9a-fA-F]{64}" | head -1)
        if [ -n "$INDIVIDUAL_SAVINGS_CLASS_HASH" ]; then
            echo -e "${YELLOW}  Class already declared, using existing class hash${NC}"
        else
            echo -e "${RED}Class already declared but could not extract class hash${NC}"
            echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
            exit 1
        fi
    elif echo "$DECLARE_OUTPUT" | grep -qi "TransportError\|IncompleteMessage"; then
        # Network error that wasn't caught by retry - this shouldn't happen but handle it
        echo -e "${RED}Network error persisted after retries${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    elif echo "$DECLARE_OUTPUT" | grep -qi "error\|panic\|Failed"; then
        # Other errors - check if it's a validation/balance error
        if echo "$DECLARE_OUTPUT" | grep -qi "exceed balance\|ValidateFailure"; then
            echo -e "${RED}Insufficient balance or validation failure${NC}"
            echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
            exit 1
        else
            echo -e "${RED}Declaration failed with errors${NC}"
            echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Failed to get IndividualSavings class hash${NC}"
        echo -e "${RED}Full output: $DECLARE_OUTPUT${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}  Class Hash: $INDIVIDUAL_SAVINGS_CLASS_HASH${NC}"

# If this was a new declaration (not already declared), wait for it to be confirmed
if echo "$DECLARE_OUTPUT" | grep -qi "Success: Declaration completed"; then
    echo -e "${YELLOW}   Waiting for declaration to be confirmed on-chain (30 seconds)...${NC}"
    sleep 30
fi

# Deploy IndividualSavings (constructor takes owner address)
echo -e "${YELLOW}   Deploying contract...${NC}"
DEPLOY_OUTPUT=$(sncast --profile mainnet deploy \
    --class-hash $INDIVIDUAL_SAVINGS_CLASS_HASH \
    --constructor-calldata $DEPLOYER_ADDRESS \
    --max-fee $MAX_FEE 2>&1 | tee /dev/stderr)
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

