const fs = require('fs');
const path = require('path');

// Fixed image URL as specified
const IMAGE_URL = "https://cdn.roninchain.com/imgineer/rnm/original/0xcd36c37185f80f688a91a9a272c1bf35eb33c6be/5622-bafybeiefetjg7leslvy7f3ya7ykjuvfq24lmyjgbhgy27rsq3ndgb4swc4.png?w=500";

// Generic trait options for randomization
const TRAIT_OPTIONS = {
    Background: [
        "Starlit Constellations", "Mystic Forest", "Crystal Caverns", "Floating Islands", 
        "Neon City", "Ancient Ruins", "Cosmic Void", "Cherry Blossoms", "Volcanic Landscape", 
        "Underwater Palace", "Northern Lights", "Desert Oasis"
    ],
    Base: [
        "Weiss", "Shadow", "Golden", "Silver", "Crimson", "Azure", "Emerald", "Violet", 
        "Coral", "Ivory", "Obsidian", "Rose"
    ],
    Tail: [
        "None", "Fluffy", "Long", "Curled", "Spiked", "Feathered", "Striped", "Glowing", 
        "Metallic", "Crystal"
    ],
    Clothes: [
        "Dual Cape", "Royal Robe", "Battle Armor", "Ninja Suit", "Wizard Cloak", 
        "Pirate Coat", "Knight's Mail", "Elegant Dress", "Casual Wear", "School Uniform", 
        "Formal Suit", "Adventure Gear"
    ],
    Eyes: [
        "Dark Eyepatch", "Glowing", "Heterochromia", "Star-shaped", "Mechanical", 
        "Crystal", "Flame", "Ice", "Lightning", "Rainbow", "Galaxy", "Normal"
    ],
    Mouth: [
        "Sewn Shut", "Smiling", "Frowning", "Neutral", "Fanged", "Stitched", 
        "Glowing", "Robotic", "Musical", "Speechless"
    ],
    Head: [
        "None", "Crown", "Hat", "Helmet", "Bandana", "Headband", "Horns", 
        "Antenna", "Halo", "Flower Crown", "Goggles", "Mask"
    ],
    Identity: [
        "Abyss", "Light", "Shadow", "Fire", "Water", "Earth", "Air", "Ice", 
        "Lightning", "Nature", "Void", "Cosmic", "Ancient", "Modern", "Mystical"
    ],
    Expression: [
        "Absolute", "Cheerful", "Serious", "Mysterious", "Playful", "Wise", 
        "Fierce", "Calm", "Excited", "Determined", "Gentle", "Bold"
    ],
    Nametag: [
        "Empty", "Hero", "Guardian", "Warrior", "Mage", "Scout", "Leader", 
        "Rebel", "Sage", "Champion", "Explorer", "Keeper"
    ]
};

// Distribution requirements
const DISTRIBUTION = {
    "Null KTTY": 40,
    "1/1 KTTY": 7,
    "Core KTTY": 13
};

/**
 * Shuffle array using Fisher-Yates algorithm
 */
function shuffleArray(array) {
    const shuffled = [...array];
    for (let i = shuffled.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
    }
    return shuffled;
}

/**
 * Get random element from array
 */
function getRandomElement(array) {
    return array[Math.floor(Math.random() * array.length)];
}

/**
 * Create trait distribution array
 */
function createTraitDistribution() {
    const distribution = [];
    
    // Add required quantities for each type
    for (let i = 0; i < DISTRIBUTION["Null KTTY"]; i++) {
        distribution.push("Null KTTY");
    }
    for (let i = 0; i < DISTRIBUTION["1/1 KTTY"]; i++) {
        distribution.push("1/1 KTTY");
    }
    for (let i = 0; i < DISTRIBUTION["Core KTTY"]; i++) {
        distribution.push("Core KTTY");
    }
    
    // Shuffle to randomize order
    return shuffleArray(distribution);
}

/**
 * Generate metadata for a single NFT
 */
function generateNFTMetadata(tokenId, kttyType) {
    const paddedId = tokenId.toString().padStart(4, '0');
    
    const metadata = {
        name: `KTTY World Companions #${paddedId}`,
        image: IMAGE_URL,
        attributes: [
            {
                trait_type: "Background",
                value: getRandomElement(TRAIT_OPTIONS.Background)
            },
            {
                trait_type: "Base",
                value: getRandomElement(TRAIT_OPTIONS.Base)
            },
            {
                trait_type: "Type",
                value: kttyType
            },
            {
                trait_type: "Tail",
                value: getRandomElement(TRAIT_OPTIONS.Tail)
            },
            {
                trait_type: "Clothes",
                value: getRandomElement(TRAIT_OPTIONS.Clothes)
            },
            {
                trait_type: "Eyes",
                value: getRandomElement(TRAIT_OPTIONS.Eyes)
            },
            {
                trait_type: "Mouth",
                value: getRandomElement(TRAIT_OPTIONS.Mouth)
            },
            {
                trait_type: "Head",
                value: getRandomElement(TRAIT_OPTIONS.Head)
            },
            {
                trait_type: "Identity",
                value: getRandomElement(TRAIT_OPTIONS.Identity)
            },
            {
                trait_type: "Expression",
                value: getRandomElement(TRAIT_OPTIONS.Expression)
            },
            {
                trait_type: "Nametag",
                value: getRandomElement(TRAIT_OPTIONS.Nametag)
            }
        ]
    };
    
    return metadata;
}

/**
 * Main function to generate all companion metadata
 */
function generateCompanionMetadata() {
    console.log('🎯 Generating KTTY World Companions Metadata...\n');
    
    // Create output directory
    const outputDir = path.join(__dirname, '..', 'metadata', 'companions');
    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
        console.log(`📁 Created directory: ${outputDir}`);
    }
    
    // Create trait distribution
    const traitDistribution = createTraitDistribution();
    console.log('📊 Trait Distribution:');
    console.log(`   - NULL KTTY: ${DISTRIBUTION["Null KTTY"]}`);
    console.log(`   - 1/1 KTTY: ${DISTRIBUTION["1/1 KTTY"]}`);
    console.log(`   - CORE KTTY: ${DISTRIBUTION["Core KTTY"]}`);
    console.log(`   - Total: ${traitDistribution.length} NFTs\n`);
    
    // Generate metadata files
    const summary = {
        "Null KTTY": 0,
        "1/1 KTTY": 0,
        "Core KTTY": 0
    };
    
    for (let i = 0; i < 60; i++) {
        const tokenId = i + 1;
        const kttyType = traitDistribution[i];
        
        // Generate metadata
        const metadata = generateNFTMetadata(tokenId, kttyType);
        
        // Write to file
        const filename = `${tokenId}.json`;
        const filepath = path.join(outputDir, filename);
        fs.writeFileSync(filepath, JSON.stringify(metadata, null, 2));
        
        // Update summary
        summary[kttyType]++;
        
        // Progress indicator
        if (tokenId % 10 === 0 || tokenId === 60) {
            console.log(`✅ Generated ${tokenId}/60 metadata files`);
        }
    }
    
    console.log('\n📋 Generation Summary:');
    console.log(`   - NULL KTTY: ${summary["Null KTTY"]} files`);
    console.log(`   - 1/1 KTTY: ${summary["1/1 KTTY"]} files`);
    console.log(`   - CORE KTTY: ${summary["Core KTTY"]} files`);
    console.log(`   - Total: ${summary["Null KTTY"] + summary["1/1 KTTY"] + summary["Core KTTY"]} files`);
    
    console.log(`\n🎉 Successfully generated 60 companion metadata files in: ${outputDir}`);
    
    // Validate distribution
    const expectedTotal = Object.values(DISTRIBUTION).reduce((sum, count) => sum + count, 0);
    if (expectedTotal === 60) {
        console.log('✅ Distribution validation: PASSED');
    } else {
        console.log('❌ Distribution validation: FAILED');
    }
    
    return {
        outputDir,
        summary,
        totalFiles: 60
    };
}

// Run the script if called directly
if (require.main === module) {
    try {
        generateCompanionMetadata();
    } catch (error) {
        console.error('❌ Error generating companion metadata:', error);
        process.exit(1);
    }
}

module.exports = { generateCompanionMetadata };