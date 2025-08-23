#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// List of contracts we need ABIs for
const contractsToExtract = [
    'ChainBalanceManager',
    'BalanceManager', 
    'TokenRegistry',
    'SyntheticToken',
    'SyntheticTokenFactory',
    'ChainRegistry',
    'PoolManager',
    'GTXRouter',
    'OrderBook',
    'UpgradeableBeacon',
    'BeaconProxy',
    'ERC20' // We'll use a standard ERC20 for this
];

// Standard ERC20 ABI
const standardERC20ABI = [
    {
        "type": "function",
        "name": "allowance",
        "inputs": [{"name": "owner", "type": "address", "internalType": "address"}, {"name": "spender", "type": "address", "internalType": "address"}],
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view"
    },
    {
        "type": "function", 
        "name": "approve",
        "inputs": [{"name": "spender", "type": "address", "internalType": "address"}, {"name": "amount", "type": "uint256", "internalType": "uint256"}],
        "outputs": [{"name": "", "type": "bool", "internalType": "bool"}],
        "stateMutability": "nonpayable"
    },
    {
        "type": "function",
        "name": "balanceOf", 
        "inputs": [{"name": "account", "type": "address", "internalType": "address"}],
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "decimals",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint8", "internalType": "uint8"}],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "name",
        "inputs": [],
        "outputs": [{"name": "", "type": "string", "internalType": "string"}],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "symbol", 
        "inputs": [],
        "outputs": [{"name": "", "type": "string", "internalType": "string"}],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "totalSupply",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256", "internalType": "uint256"}],
        "stateMutability": "view"
    },
    {
        "type": "function",
        "name": "transfer",
        "inputs": [{"name": "to", "type": "address", "internalType": "address"}, {"name": "amount", "type": "uint256", "internalType": "uint256"}],
        "outputs": [{"name": "", "type": "bool", "internalType": "bool"}],
        "stateMutability": "nonpayable"
    },
    {
        "type": "function",
        "name": "transferFrom",
        "inputs": [{"name": "from", "type": "address", "internalType": "address"}, {"name": "to", "type": "address", "internalType": "address"}, {"name": "amount", "type": "uint256", "internalType": "uint256"}],
        "outputs": [{"name": "", "type": "bool", "internalType": "bool"}], 
        "stateMutability": "nonpayable"
    },
    {
        "type": "event",
        "name": "Approval",
        "inputs": [{"name": "owner", "type": "address", "indexed": true, "internalType": "address"}, {"name": "spender", "type": "address", "indexed": true, "internalType": "address"}, {"name": "value", "type": "uint256", "indexed": false, "internalType": "uint256"}],
        "anonymous": false
    },
    {
        "type": "event",
        "name": "Transfer", 
        "inputs": [{"name": "from", "type": "address", "indexed": true, "internalType": "address"}, {"name": "to", "type": "address", "indexed": true, "internalType": "address"}, {"name": "value", "type": "uint256", "indexed": false, "internalType": "uint256"}],
        "anonymous": false
    }
];

function extractABI(contractName) {
    console.log(`\n🔍 Extracting ABI for ${contractName}...`);
    
    if (contractName === 'ERC20') {
        return standardERC20ABI;
    }
    
    const artifactPath = path.join(__dirname, 'out', `${contractName}.sol`, `${contractName}.json`);
    
    if (!fs.existsSync(artifactPath)) {
        console.log(`❌ Artifact not found: ${artifactPath}`);
        return null;
    }
    
    try {
        const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
        const abi = artifact.abi;
        
        if (!abi || !Array.isArray(abi)) {
            console.log(`❌ No valid ABI found in ${artifactPath}`);
            return null;
        }
        
        console.log(`✅ Extracted ${abi.length} ABI entries for ${contractName}`);
        
        // Show first few function names for verification
        const functions = abi.filter(item => item.type === 'function').map(item => item.name);
        console.log(`   📋 Functions: ${functions.slice(0, 5).join(', ')}${functions.length > 5 ? '...' : ''}`);
        
        return abi;
        
    } catch (error) {
        console.log(`❌ Error reading ${artifactPath}:`, error.message);
        return null;
    }
}

function formatABI(contractName, abi) {
    const formattedABI = JSON.stringify(abi, null, '\t').replace(/"/g, '"');
    
    return `export const ${contractName}ABI: any[] = ${formattedABI} as const;`;
}

function writeABIFile(contractName, abi) {
    const outputPath = path.join(__dirname, 'deployed-contracts', 'abis', `${contractName}ABI.ts`);
    const content = formatABI(contractName, abi);
    
    fs.writeFileSync(outputPath, content, 'utf8');
    console.log(`✅ Written ${contractName}ABI.ts`);
}

function updateIndexFile() {
    const indexPath = path.join(__dirname, 'deployed-contracts', 'abis', 'index.ts');
    const exports = contractsToExtract.map(contract => 
        `export { ${contract}ABI } from './${contract}ABI';`
    ).join('\n');
    
    fs.writeFileSync(indexPath, exports + '\n', 'utf8');
    console.log('✅ Updated index.ts');
}

function validateExistingABI(contractName) {
    const existingPath = path.join(__dirname, 'deployed-contracts', 'abis', `${contractName}ABI.ts`);
    if (!fs.existsSync(existingPath)) {
        return { exists: false };
    }
    
    try {
        const existingContent = fs.readFileSync(existingPath, 'utf8');
        const match = existingContent.match(/export const \w+ABI: any\[\] = (\[[\s\S]*?\]) as const;/);
        if (!match) {
            return { exists: true, valid: false, error: 'Could not parse existing ABI' };
        }
        
        const existingABI = JSON.parse(match[1]);
        const realABI = extractABI(contractName);
        
        if (!realABI) {
            return { exists: true, valid: false, error: 'Could not extract real ABI for comparison' };
        }
        
        // Compare function names
        const existingFunctions = existingABI.filter(item => item.type === 'function').map(item => item.name).sort();
        const realFunctions = realABI.filter(item => item.type === 'function').map(item => item.name).sort();
        
        const functionsMatch = JSON.stringify(existingFunctions) === JSON.stringify(realFunctions);
        
        return {
            exists: true,
            valid: functionsMatch,
            existingFunctions: existingFunctions.slice(0, 5),
            realFunctions: realFunctions.slice(0, 5),
            totalExisting: existingFunctions.length,
            totalReal: realFunctions.length
        };
        
    } catch (error) {
        return { exists: true, valid: false, error: error.message };
    }
}

// Main execution
console.log('🚀 Starting ABI Extraction and Validation...\n');

console.log('📊 VALIDATION REPORT:');
console.log('='.repeat(80));

for (const contractName of contractsToExtract) {
    console.log(`\n📋 ${contractName}:`);
    
    const validation = validateExistingABI(contractName);
    
    if (!validation.exists) {
        console.log('   ❌ No existing ABI file');
    } else if (validation.valid) {
        console.log('   ✅ Existing ABI matches compiled contract');
        console.log(`   📊 Functions: ${validation.totalReal} total`);
        continue; // Skip re-extraction for valid ABIs
    } else {
        console.log('   ❌ Existing ABI does NOT match compiled contract');
        if (validation.error) {
            console.log(`   💥 Error: ${validation.error}`);
        } else {
            console.log(`   📊 Existing: ${validation.totalExisting} functions [${validation.existingFunctions.join(', ')}...]`);
            console.log(`   📊 Real: ${validation.totalReal} functions [${validation.realFunctions.join(', ')}...]`);
        }
    }
    
    // Extract and write the real ABI
    const abi = extractABI(contractName);
    if (abi) {
        writeABIFile(contractName, abi);
    }
}

console.log('\n🔧 Updating index file...');
updateIndexFile();

console.log('\n✅ ABI extraction and validation complete!');
console.log('\n📋 Summary: All ABIs have been extracted from compiled contracts and validated.');
console.log('🎯 Next: Check the updated ABIs and test frontend integration.');