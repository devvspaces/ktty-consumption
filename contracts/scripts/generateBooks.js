const fs = require('fs');
const path = require('path');

// Tool and collectible configuration
const TOOL_IDS = [1, 2, 3, 4, 5]; // Anvil, Hammer, Tong, Bellow, Eternal Flame
const GOLDEN_TICKET_ID = 1;
const TOOLS_PER_BOOK = 3;

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
 * Generate random tool IDs for a book
 */
function generateRandomToolIds() {
    const toolIds = [];
    for (let i = 0; i < TOOLS_PER_BOOK; i++) {
        toolIds.push(getRandomElement(TOOL_IDS));
    }
    return toolIds;
}

/**
 * Create a book object
 */
function createBook(bookId, nft, hasGoldenTicket = false) {
    return {
        bookId: bookId,
        nftId: nft.tokenId,
        nftType: nft.type,
        toolIds: generateRandomToolIds(),
        goldenTicketId: hasGoldenTicket ? GOLDEN_TICKET_ID : 0,
        hasGoldenTicket: hasGoldenTicket
    };
}

/**
 * Validate NFT distribution meets requirements
 */
function validateNFTDistribution(nfts) {
    const typeCounts = {};
    nfts.forEach(nft => {
        typeCounts[nft.type] = (typeCounts[nft.type] || 0) + 1;
    });
    
    console.log('📊 Input NFT distribution:');
    Object.entries(typeCounts).forEach(([type, count]) => {
        console.log(`   - ${type}: ${count}`);
    });
    
    // Validate we have expected counts
    const expectedCounts = {
        "Null KTTY": 30,
        "1/1 KTTY": 7,
        "Core KTTY": 13
    };
    
    for (const [type, expected] of Object.entries(expectedCounts)) {
        const actual = typeCounts[type] || 0;
        if (actual !== expected) {
            throw new Error(`Expected ${expected} ${type} NFTs, found ${actual}`);
        }
    }
    
    return typeCounts;
}

/**
 * Generate books for Pool 1 and Pool 2
 */
function generatePoolBooks(nullNFTs, poolNumber, startBookId) {
    console.log(`\n🏊‍♂️ Generating Pool ${poolNumber} books...`);
    
    if (nullNFTs.length < 5) {
        throw new Error(`Not enough NULL NFTs for Pool ${poolNumber}. Need 5, have ${nullNFTs.length}`);
    }
    
    const poolNFTs = nullNFTs.splice(0, 5); // Remove 5 NFTs from the array
    const books = [];
    
    for (let i = 0; i < 5; i++) {
        const bookId = startBookId + i;
        const book = createBook(bookId, poolNFTs[i], false); // No golden tickets in pools 1&2
        books.push(book);
    }
    
    console.log(`   - Created ${books.length} books for Pool ${poolNumber}`);
    console.log(`   - Remaining NULL NFTs: ${nullNFTs.length}`);
    
    return books;
}

/**
 * Generate books for a specific bucket
 */
function generateBucketBooks(nfts, bucketNumber, startBookId, hasNullNFTs = true) {
    console.log(`\n🪣 Generating Bucket ${bucketNumber} books...`);
    
    const bucketNFTs = [];
    const books = [];
    
    if (hasNullNFTs) {
        // Buckets 1-5: Need 4 NULL NFTs + 1 other
        const nullNFTs = nfts.filter(nft => nft.type === "Null KTTY");
        const otherNFTs = nfts.filter(nft => nft.type !== "Null KTTY");
        
        if (nullNFTs.length < 4) {
            throw new Error(`Not enough NULL NFTs for Bucket ${bucketNumber}. Need 4, have ${nullNFTs.length}`);
        }
        if (otherNFTs.length < 1) {
            throw new Error(`Not enough non-NULL NFTs for Bucket ${bucketNumber}. Need 1, have ${otherNFTs.length}`);
        }
        
        // Take 4 NULL NFTs and 1 other
        bucketNFTs.push(...nullNFTs.splice(0, 4));
        bucketNFTs.push(otherNFTs.splice(0, 1)[0]);
        
    } else {
        // Buckets 6-8: Only non-NULL NFTs
        const otherNFTs = nfts.filter(nft => nft.type !== "Null KTTY");
        
        if (otherNFTs.length < 5) {
            throw new Error(`Not enough non-NULL NFTs for Bucket ${bucketNumber}. Need 5, have ${otherNFTs.length}`);
        }
        
        bucketNFTs.push(...otherNFTs.splice(0, 5));
        
        // Remove these NFTs from the main array
        bucketNFTs.forEach(nft => {
            const index = nfts.findIndex(n => n.tokenId === nft.tokenId);
            if (index !== -1) nfts.splice(index, 1);
        });
    }
    
    // Shuffle bucket NFTs
    const shuffledBucketNFTs = shuffleArray(bucketNFTs);
    
    // Create books (2 with golden tickets, 3 without)
    for (let i = 0; i < 5; i++) {
        const bookId = startBookId + i;
        const hasGoldenTicket = i < 2; // First 2 books get golden tickets
        const book = createBook(bookId, shuffledBucketNFTs[i], hasGoldenTicket);
        books.push(book);
    }
    
    console.log(`   - Created ${books.length} books for Bucket ${bucketNumber}`);
    console.log(`   - Books with golden tickets: ${books.filter(b => b.hasGoldenTicket).length}`);
    
    return books;
}

/**
 * Main function to generate all books
 */
function generateBooks() {
    console.log('📚 Generating KTTY World Books...\n');
    
    // Read remaining NFTs
    const remainingFile = path.join(__dirname, 'remaining-nfts.json');
    if (!fs.existsSync(remainingFile)) {
        throw new Error(`Remaining NFTs file not found: ${remainingFile}`);
    }
    
    const remainingNFTs = JSON.parse(fs.readFileSync(remainingFile, 'utf8'));
    console.log(`📖 Loaded ${remainingNFTs.length} remaining NFTs`);
    
    // Validate input distribution
    validateNFTDistribution(remainingNFTs);
    
    // Separate NFTs by type
    let nullNFTs = remainingNFTs.filter(nft => nft.type === "Null KTTY");
    let otherNFTs = remainingNFTs.filter(nft => nft.type !== "Null KTTY");
    
    // Shuffle all arrays for randomness
    nullNFTs = shuffleArray(nullNFTs);
    otherNFTs = shuffleArray(otherNFTs);
    
    console.log(`\n🔀 Shuffled NFTs:`);
    console.log(`   - NULL NFTs: ${nullNFTs.length}`);
    console.log(`   - Other NFTs: ${otherNFTs.length}`);
    
    const allBooks = [];
    const distributions = {
        pool1: [],
        pool2: [],
        pool3: {
            bucket1: [],
            bucket2: [],
            bucket3: [],
            bucket4: [],
            bucket5: [],
            bucket6: [],
            bucket7: [],
            bucket8: []
        }
    };
    
    let currentBookId = 1;
    
    // Generate Pool 1 books (5 NULL NFTs, no golden tickets)
    const pool1Books = generatePoolBooks(nullNFTs, 1, currentBookId);
    allBooks.push(...pool1Books);
    distributions.pool1 = shuffleArray(pool1Books.map(book => book.bookId));
    currentBookId += 5;
    
    // Generate Pool 2 books (5 NULL NFTs, no golden tickets)
    const pool2Books = generatePoolBooks(nullNFTs, 2, currentBookId);
    allBooks.push(...pool2Books);
    distributions.pool2 = shuffleArray(pool2Books.map(book => book.bookId));
    currentBookId += 5;
    
    console.log(`\n📊 After pools generation:`);
    console.log(`   - NULL NFTs remaining: ${nullNFTs.length}`);
    console.log(`   - Other NFTs remaining: ${otherNFTs.length}`);
    console.log(`   - Total NFTs remaining: ${nullNFTs.length + otherNFTs.length}`);
    
    // Combine remaining NFTs for bucket generation
    const remainingForBuckets = [...nullNFTs, ...otherNFTs];
    
    // Generate Bucket books
    for (let bucketNum = 1; bucketNum <= 8; bucketNum++) {
        const hasNullNFTs = bucketNum <= 5; // Only buckets 1-5 can have NULL NFTs
        
        const bucketBooks = generateBucketBooks(
            remainingForBuckets, 
            bucketNum, 
            currentBookId, 
            hasNullNFTs
        );
        
        allBooks.push(...bucketBooks);
        distributions.pool3[`bucket${bucketNum}`] = shuffleArray(bucketBooks.map(book => book.bookId));
        currentBookId += 5;
        
        console.log(`   - NFTs remaining after bucket ${bucketNum}: ${remainingForBuckets.length}`);
    }
    
    // Final validation
    console.log(`\n🔍 Final validation:`);
    console.log(`   - Total books created: ${allBooks.length}`);
    console.log(`   - Expected: 50`);
    
    if (allBooks.length !== 50) {
        throw new Error(`Expected 50 books, created ${allBooks.length}`);
    }
    
    // Validate golden ticket distribution
    const booksWithGoldenTickets = allBooks.filter(book => book.hasGoldenTicket);
    console.log(`   - Books with golden tickets: ${booksWithGoldenTickets.length}`);
    console.log(`   - Expected: 16 (2 per bucket × 8 buckets)`);
    
    if (booksWithGoldenTickets.length !== 16) {
        throw new Error(`Expected 16 books with golden tickets, found ${booksWithGoldenTickets.length}`);
    }
    
    // Validate NFT type distribution in books
    const bookTypeCounts = {};
    allBooks.forEach(book => {
        bookTypeCounts[book.nftType] = (bookTypeCounts[book.nftType] || 0) + 1;
    });
    
    console.log(`   - Book NFT type distribution:`);
    Object.entries(bookTypeCounts).forEach(([type, count]) => {
        console.log(`     • ${type}: ${count}`);
    });
    
    // Save outputs
    const allBooksFile = path.join(__dirname, 'all-books.json');
    const distributionsFile = path.join(__dirname, 'book-distributions.json');
    
    fs.writeFileSync(allBooksFile, JSON.stringify(allBooks, null, 2));
    fs.writeFileSync(distributionsFile, JSON.stringify(distributions, null, 2));
    
    console.log(`\n💾 Saved all books to: ${allBooksFile}`);
    console.log(`💾 Saved distributions to: ${distributionsFile}`);
    
    // Show samples
    console.log(`\n📋 Sample books (first 3):`);
    allBooks.slice(0, 3).forEach(book => {
        console.log(`   - Book ${book.bookId}: NFT ${book.nftId} (${book.nftType}), Tools [${book.toolIds.join(', ')}], Golden Ticket: ${book.hasGoldenTicket}`);
    });
    
    console.log(`\n🎉 Successfully generated 50 books with proper distribution!`);
    
    return {
        allBooksFile,
        distributionsFile,
        totalBooks: allBooks.length,
        goldenTicketBooks: booksWithGoldenTickets.length,
        typeCounts: bookTypeCounts
    };
}

// Run the script if called directly
if (require.main === module) {
    try {
        generateBooks();
    } catch (error) {
        console.error('❌ Error generating books:', error);
        process.exit(1);
    }
}

module.exports = { generateBooks };