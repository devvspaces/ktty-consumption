const { MerkleTree } = require('merkletreejs');
const { keccak256 } = require('js-sha3');
const { ethers } = require('ethers');
const fs = require('fs');

// Function to hash address using the same method as the contract
function hashAddress(address) {
    const cleanAddr = address.replace('0x', '').toLowerCase();
    return keccak256(Buffer.from(cleanAddr, 'hex'));
}

// List of addresses for testing (including test addresses from Foundry)
const addresses = [
    '0x29E3b139f4393aDda86303fcdAa35F60Bb7092bF', // user1 from makeAddr("user1")
    '0x1D96F2f6BeF1202E4Ce1Ff6Dad0c2CB002861d3e', // user2 from makeAddr("user2") 
    '0xc0A55e2205B289a967823662B841Bd67Aa362Aec', // user3 from makeAddr("user3")
    '0x90561e5Cd8025FA6F52d849e8867C14A77C94BA0', // user4 from makeAddr("user4")
    '0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9', // Additional test addresses
    '0x2546BcD3c84621e976D8185a91A922aE77ECEc30',
    '0xA0Ca70DFB6Fb79fD5EF160D3EAc677868547ffEF',
    '0xd8C4E87473bc36B6d1A22e4fbB5Bf3681c26B3C1',
    '0xC792F91084F131e18adcBE28045737b94ac5C922',
    '0x0DE92325AC09eC459Fe02625c144Ee07B3115dA1',
    '0x2E9eB05347148Ad9bf7bc001092a8fD353D774cf',
];

function generateMerkleTree() {
    console.log('Generating Merkle Tree for Round 3 whitelist...\n');

    // Hash all addresses
    const hashedAddresses = addresses.map(addr => {
        const hash = hashAddress(addr);
        console.log(`Address: ${addr} -> Hash: ${hash}`);
        return hash;
    });

    console.log('\nBuilding Merkle Tree...');

    // Create merkle tree
    const tree = new MerkleTree(hashedAddresses, keccak256, {
        sortPairs: true,
        hashLeaves: false // We already hashed the leaves
    });

    const root = tree.getHexRoot();
    console.log(`\nMerkle Root: ${root}`);

    // Generate proofs for each address
    const merkleData = {
        root: root,
        addresses: []
    };

    console.log('\nGenerating proofs:');

    addresses.forEach((address, index) => {
        const hashedAddress = hashedAddresses[index];
        const proof = tree.getHexProof(hashAddress(address));

        const addressData = {
            address: address,
            hashedAddress: hashedAddress,
            proof: proof,
            isValid: tree.verify(proof, hashedAddress, root)
        };

        merkleData.addresses.push(addressData);

        console.log(`\nAddress: ${address}`);
        console.log(`  Hash: ${hashedAddress}`);
        console.log(`  Proof: [${proof.map(p => `"${p}"`).join(', ')}]`);
        console.log(`  Valid: ${addressData.isValid}`);
    });

    // Add some non-whitelisted addresses for negative testing
    const nonWhitelistedAddresses = [
        '0x000000000000000000000000000000000000dEaD', // Burn address
        '0x1111111111111111111111111111111111111111'  // Another test address
    ];

    console.log('\n\nTesting non-whitelisted addresses:');
    nonWhitelistedAddresses.forEach(address => {
        const hashedAddress = hashAddress(address);
        const proof = []; // Empty proof for non-whitelisted
        const isValid = tree.verify(proof, hashedAddress, root);

        merkleData.addresses.push({
            address: address,
            hashedAddress: hashedAddress,
            proof: proof,
            isValid: isValid,
            isWhitelisted: false
        });

        console.log(`\nNon-whitelisted Address: ${address}`);
        console.log(`  Hash: ${hashedAddress}`);
        console.log(`  Valid with empty proof: ${isValid}`);
    });

    // Save to JSON file
    const outputPath = './scripts/merkleData.json';
    fs.writeFileSync(outputPath, JSON.stringify(merkleData, null, 2));

    console.log(`\n✅ Merkle tree data saved to ${outputPath}`);

    // Generate Solidity test constants
    console.log('\n📋 Solidity Test Constants:');
    console.log(`bytes32 constant MERKLE_ROOT = ${root};`);
    console.log('\n// Whitelisted addresses with proofs:');

    merkleData.addresses.filter(addr => addr.isWhitelisted !== false).forEach((addr, index) => {
        console.log(`// ${addr.address}`);
        console.log(`address constant USER${index + 1} = ${addr.address};`);
        if (addr.proof.length > 0) {
            console.log(`bytes32[] memory user${index + 1}Proof = new bytes32[](${addr.proof.length});`);
            addr.proof.forEach((proofElement, proofIndex) => {
                console.log(`user${index + 1}Proof[${proofIndex}] = ${proofElement};`);
            });
        } else {
            console.log(`bytes32[] memory user${index + 1}Proof = new bytes32[](0); // Single leaf or root`);
        }
        console.log('');
    });

    return merkleData;
}

// Run the script
if (require.main === module) {
    try {
        generateMerkleTree();
    } catch (error) {
        console.error('Error generating merkle tree:', error);
        process.exit(1);
    }
}

module.exports = { generateMerkleTree, hashAddress };