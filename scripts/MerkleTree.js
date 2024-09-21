
const { ethers } = require("ethers");
const fs = require("fs");

// Helper function to hash an address (to create a leaf)
function hashAddress(address) {
    // Ensure the address is properly checksummed
    const checksummedAddress = ethers.utils.getAddress(address);

    // Step 1: Hash the abi.encode equivalent of the address (like keccak256(abi.encode(address)))
    const encodedAddress = ethers.utils.defaultAbiCoder.encode(["address"], [checksummedAddress]);
    const firstHash = ethers.utils.keccak256(encodedAddress);

    // Step 2: Hash the result again (like keccak256(bytes.concat(firstHash)))
    const leaf = ethers.utils.keccak256(firstHash);

    return leaf;
}

// Function to sort and hash pairs, mimicking OpenZeppelin's _hashPair
function hashPair(left, right) {
    // Sort the pair to ensure consistent hashing
    if (left < right) {
        return ethers.utils.keccak256(ethers.utils.concat([left, right]));
    } else {
        return ethers.utils.keccak256(ethers.utils.concat([right, left]));
    }
}

// Function to build the Merkle Tree and return the root
function buildMerkleTree(hashedLeaves) {
    if (hashedLeaves.length === 0) {
        throw new Error("No leaves provided to build the Merkle Tree.");
    }

    let tree = [hashedLeaves]; // Store each level of the tree

    // Continue building the tree until we get the root
    while (tree[tree.length - 1].length > 1) {
        const currentLevel = tree[tree.length - 1];
        const nextLevel = [];

        // Pairwise hash all nodes in the current level
        for (let i = 0; i < currentLevel.length; i += 2) {
            if (i + 1 < currentLevel.length) {
                nextLevel.push(hashPair(currentLevel[i], currentLevel[i + 1]));
            } else {
                // If we have an odd number of nodes, duplicate the last node
                nextLevel.push(currentLevel[i]);
            }
        }

        // Move to the next level
        tree.push(nextLevel);
    }

    // The last element in the final level is the Merkle Root
    return { root: tree[tree.length - 1][0], tree };
}

// Function to generate a Merkle proof for a given leaf
function generateMerkleProof(hashedLeaves, targetLeaf) {
    let index = hashedLeaves.indexOf(targetLeaf);
    if (index === -1) {
        throw new Error("Target leaf not found in the hashed leaves.");
    }

    const proof = [];
    const { tree } = buildMerkleTree(hashedLeaves);

    // Traverse each level of the tree and build the proof
    for (let level = 0; level < tree.length - 1; level++) {
        const currentLevel = tree[level];
        const pairIndex = index % 2 === 0 ? index + 1 : index - 1;

        if (pairIndex < currentLevel.length) {
            proof.push(currentLevel[pairIndex]);
        }

        index = Math.floor(index / 2);
    }

    return proof;
}

// Main function to create a Merkle Tree, get the root, and generate proofs for all addresses
async function main() {
    // Example addresses (replace with actual addresses)
    const addresses = [
        "0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2",
        "0x5B38Da6a701c568545dCfcB03FcB875f56beddC4",
        "0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB",
        "0x617F2E2fD72FD9D5503197092aC168c91465E7f2",
        "0x17F6AD8Ef982297579C203069C1DbfFE4348c372",
        "0x5c6B0f7Bf3E7ce046039Bd8FABdfD3f9F5021678",
        "0x03C6FcED478cBbC9a4FAB34eF9f40767739D1Ff7"
    ];

    // Step 1: Hash each address (with checksum) to create the leaves
    const hashedLeaves = addresses.map(addr => hashAddress(addr));

    // Step 2: Build the Merkle Tree and get the root
    const { root } = buildMerkleTree(hashedLeaves);

    // Step 3: Generate a proof for each address
    const proofs = {};
    addresses.forEach((address) => {
        const targetLeaf = hashAddress(address); // Generate the target leaf
        const proof = generateMerkleProof(hashedLeaves, targetLeaf); // Generate proof
        proofs[address] = {
            proof,
            leaf: targetLeaf
        };
    });

    // Step 4: Prepare JSON data
    const output = {
        root,
        proofs
    };

    // Step 5: Write to JSON file with double quotes (JSON.stringify automatically uses double quotes)
    fs.writeFileSync("proofs.json", JSON.stringify(output, null, 2), "utf-8");

    console.log("Proofs have been written to proofs.json");
}

// Run the main function
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });