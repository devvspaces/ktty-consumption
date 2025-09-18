const fs = require('fs');
const path = require('path');

/**
 * Extract type from metadata attributes
 */
function extractType(metadata) {
    const typeAttribute = metadata.attributes.find(attr => attr.trait_type === "Type");
    return typeAttribute ? typeAttribute.value : "Unknown";
}

/**
 * Aggregate all companion metadata into a single JSON file
 */
function aggregateCompanionMetadata() {
    console.log('📦 Aggregating KTTY World Companions Metadata...\n');
    
    // Input directory
    const inputDir = path.join(__dirname, '..', 'metadata', 'companions');
    if (!fs.existsSync(inputDir)) {
        throw new Error(`Input directory not found: ${inputDir}`);
    }
    
    // Output directory and file
    const outputDir = path.join(__dirname);
    const outputFile = path.join(outputDir, 'aggregated-companions.json');
    
    // Create output directory if it doesn't exist
    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
    }
    
    const aggregatedData = [];
    const expectedTokenIds = 60;
    let foundFiles = 0;
    
    console.log(`🔍 Reading metadata files from: ${inputDir}`);
    
    // Process each token ID from 1 to 60
    for (let tokenId = 1; tokenId <= expectedTokenIds; tokenId++) {
        const filename = `${tokenId}.json`;
        const filepath = path.join(inputDir, filename);
        
        if (!fs.existsSync(filepath)) {
            console.warn(`⚠️  Missing metadata file: ${filename}`);
            continue;
        }
        
        try {
            // Read and parse metadata file
            const metadataContent = fs.readFileSync(filepath, 'utf8');
            const metadata = JSON.parse(metadataContent);
            
            // Extract required information
            const aggregatedItem = {
                tokenId: tokenId,
                name: metadata.name,
                type: extractType(metadata)
            };
            
            aggregatedData.push(aggregatedItem);
            foundFiles++;
            
            // Progress indicator
            if (tokenId % 10 === 0) {
                console.log(`✅ Processed ${tokenId}/${expectedTokenIds} files`);
            }
            
        } catch (error) {
            console.error(`❌ Error processing ${filename}:`, error.message);
        }
    }
    
    // Validate we found all expected files
    if (foundFiles !== expectedTokenIds) {
        console.warn(`⚠️  Expected ${expectedTokenIds} files, found ${foundFiles}`);
    }
    
    // Sort by token ID to ensure proper order (should already be ordered)
    aggregatedData.sort((a, b) => a.tokenId - b.tokenId);
    
    // Write aggregated data to output file
    fs.writeFileSync(outputFile, JSON.stringify(aggregatedData, null, 2));
    
    // Generate summary statistics
    const typeCounts = {};
    aggregatedData.forEach(item => {
        typeCounts[item.type] = (typeCounts[item.type] || 0) + 1;
    });
    
    console.log(`\n📋 Aggregation Summary:`);
    console.log(`   - Total NFTs processed: ${foundFiles}`);
    console.log(`   - Type distribution:`);
    Object.entries(typeCounts).forEach(([type, count]) => {
        console.log(`     • ${type}: ${count}`);
    });
    
    console.log(`\n🎉 Successfully aggregated companion metadata to: ${outputFile}`);
    
    // Show first few entries as example
    console.log(`\n📋 Sample entries:`);
    aggregatedData.slice(0, 3).forEach(item => {
        console.log(`   - Token ${item.tokenId}: ${item.name} (${item.type})`);
    });
    
    if (aggregatedData.length > 3) {
        console.log(`   ... and ${aggregatedData.length - 3} more`);
    }
    
    return {
        outputFile,
        totalItems: aggregatedData.length,
        typeCounts,
        data: aggregatedData
    };
}

// Run the script if called directly
if (require.main === module) {
    try {
        aggregateCompanionMetadata();
    } catch (error) {
        console.error('❌ Error aggregating companion metadata:', error);
        process.exit(1);
    }
}

module.exports = { aggregateCompanionMetadata };