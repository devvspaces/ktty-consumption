const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');
const BOOK_ABI = require("./../out/KttyWorldBooks.sol/KttyWorldBooks.json").abi;
require('dotenv').config();

// Configuration
const BATCH_SIZE = 10; // Books per transaction
const BOOKS_FILE = path.join(__dirname, 'all-books.json');
const PROGRESS_FILE = path.join(__dirname, 'books-loaded-progress.json');

/**
 * Sleep for specified milliseconds
 */
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Load progress from file or create new progress
 */
function loadProgress() {
    if (fs.existsSync(PROGRESS_FILE)) {
        try {
            const progress = JSON.parse(fs.readFileSync(PROGRESS_FILE, 'utf8'));
            console.log('📋 Loaded existing progress:', progress);
            return progress;
        } catch (error) {
            console.warn('⚠️  Error reading progress file, starting fresh:', error.message);
        }
    }

    return {
        lastLoadedBookId: 0,
        totalBooks: 0,
        batchesCompleted: 0,
        batchesRemaining: 0,
        lastTransactionHash: null,
        timestamp: new Date().toISOString(),
        status: 'not_started'
    };
}

/**
 * Save progress to file
 */
function saveProgress(progress) {
    progress.timestamp = new Date().toISOString();
    fs.writeFileSync(PROGRESS_FILE, JSON.stringify(progress, null, 2));
    console.log('💾 Progress saved');
}

/**
 * Validate book structure
 */
function validateBook(book, index) {
    const requiredFields = ['bookId', 'nftId', 'series', 'toolIds', 'goldenTicketId', 'hasGoldenTicket'];

    for (const field of requiredFields) {
        if (book[field] === undefined || book[field] === null) {
            throw new Error(`Book ${index + 1} missing required field: ${field}`);
        }
    }

    if (book.bookId !== index + 1) {
        throw new Error(`Book at index ${index} has incorrect bookId ${book.bookId}, expected ${index + 1}`);
    }

    if (!Array.isArray(book.toolIds) || book.toolIds.length !== 3) {
        throw new Error(`Book ${book.bookId} has invalid toolIds array`);
    }

    if (typeof book.series !== 'string' || book.series.trim() === '') {
        throw new Error(`Book ${book.bookId} has invalid series`);
    }
}

/**
 * Prepare batch data for contract call
 */
function prepareBatchData(books) {
    const bookIds = [];
    const nftIds = [];
    const toolIds = [];
    const goldenTicketIds = [];
    const series = [];

    for (const book of books) {
        bookIds.push(book.bookId);
        nftIds.push(book.nftId);
        toolIds.push(book.toolIds);
        goldenTicketIds.push(book.goldenTicketId);
        series.push(book.series);
    }

    return {
        bookIds,
        nftIds,
        toolIds,
        goldenTicketIds,
        series
    };
}

/**
 * Check if a book is already loaded in the contract
 */
async function isBookLoaded(contract, bookId) {
    try {
        const book = await contract.getBook(bookId);
        return book.nftId > 0; // If nftId is set, book exists
    } catch (error) {
        return false;
    }
}

/**
 * Load books with retry logic
 */
async function loadBooksWithRetry(contract, to, batchData, batchNumber, maxRetries = 3) {
    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            console.log(`📤 Sending batch ${batchNumber} (attempt ${attempt}/${maxRetries})...`);

            const tx = await contract.batchMintBooks(
                to,
                batchData.bookIds,
                batchData.nftIds,
                batchData.toolIds,
                batchData.goldenTicketIds,
                batchData.series,
                {
                    gasLimit: 3000000, // Adjust as needed
                    maxPriorityFeePerGas: ethers.utils.parseUnits("20", "gwei"), // Add this
                    maxFeePerGas: ethers.utils.parseUnits("50", "gwei") // Add this
                }
            );

            console.log(`⏳ Transaction sent: ${tx.hash}`);
            console.log('⏳ Waiting for confirmation...');

            const receipt = await tx.wait();

            if (receipt.status === 1) {
                console.log(`✅ Batch ${batchNumber} successful! Gas used: ${receipt.gasUsed.toString()}`);
                return { success: true, hash: tx.hash, gasUsed: receipt.gasUsed.toString() };
            } else {
                throw new Error('Transaction failed');
            }

        } catch (error) {
            console.error(`❌ Batch ${batchNumber} attempt ${attempt} failed:`, error.message);

            if (attempt === maxRetries) {
                return { success: false, error: error.message };
            }

            // Exponential backoff
            const delayMs = Math.pow(2, attempt) * 1000;
            console.log(`⏳ Retrying in ${delayMs / 1000} seconds...`);
            await sleep(delayMs);
        }
    }
}

/**
 * Main function to load books
 */
async function loadBooks() {
    console.log('📚 Starting KTTY World Books Loading...\n');

    // Validate environment
    if (!process.env.PRIVATE_KEY) {
        throw new Error('PRIVATE_KEY not found in environment variables');
    }

    if (!process.env.RPC_URL) {
        throw new Error('RPC_URL not found in environment variables');
    }

    if (!process.env.BOOKS_ADDRESS) {
        throw new Error('BOOKS_ADDRESS not found in environment variables');
    }

    if (!process.env.MINTING_CONTRACT_ADDRESS) {
        throw new Error('MINTING_CONTRACT_ADDRESS not found in environment variables');
    }

    // Load books data
    if (!fs.existsSync(BOOKS_FILE)) {
        throw new Error(`Books file not found: ${BOOKS_FILE}`);
    }

    const books = JSON.parse(fs.readFileSync(BOOKS_FILE, 'utf8'));
    console.log(`📖 Loaded ${books.length} books from ${BOOKS_FILE}`);

    // Validate all books
    console.log('🔍 Validating book data...');
    books.forEach((book, index) => validateBook(book, index));
    console.log('✅ All books validated successfully');

    // Load progress
    const progress = loadProgress();
    progress.totalBooks = books.length;

    // Setup provider and contract
    const provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
    const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
    const contract = new ethers.Contract(process.env.BOOKS_ADDRESS, BOOK_ABI, wallet);

    console.log(`🔗 Connected to RPC: ${process.env.RPC_URL}`);
    console.log(`👤 Wallet address: ${wallet.address}`);
    console.log(`📄 Books address: ${process.env.BOOKS_ADDRESS}`);

    // Check if we're the owner
    try {
        const owner = await contract.owner();
        if (owner.toLowerCase() !== wallet.address.toLowerCase()) {
            throw new Error(`Wallet ${wallet.address} is not the contract owner ${owner}`);
        }
        console.log('✅ Confirmed wallet is contract owner');
    } catch (error) {
        throw new Error(`Failed to verify ownership: ${error.message}`);
    }

    // Determine starting point
    let startBookId = progress.lastLoadedBookId + 1;
    const booksToLoad = books.filter(book => book.bookId >= startBookId);

    if (booksToLoad.length === 0) {
        console.log('🎉 All books already loaded!');
        progress.status = 'completed';
        saveProgress(progress);
        return;
    }

    console.log(`\n📋 Loading status:`);
    console.log(`   - Last loaded book ID: ${progress.lastLoadedBookId}`);
    console.log(`   - Starting from book ID: ${startBookId}`);
    console.log(`   - Books remaining: ${booksToLoad.length}`);

    // Process in batches
    progress.status = 'in_progress';
    const batches = [];
    for (let i = 0; i < booksToLoad.length; i += BATCH_SIZE) {
        batches.push(booksToLoad.slice(i, i + BATCH_SIZE));
    }

    progress.batchesRemaining = batches.length;
    console.log(`📦 Will process ${batches.length} batches of up to ${BATCH_SIZE} books each\n`);

    // Process each batch
    for (let batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        const batch = batches[batchIndex];
        const batchNumber = progress.batchesCompleted + batchIndex + 1;

        console.log(`\n🔄 Processing batch ${batchNumber}/${progress.batchesCompleted + batches.length}`);
        console.log(`📚 Books in this batch: ${batch.map(b => b.bookId).join(', ')}`);

        // Check if any books in this batch are already loaded
        const notLoadedBooks = [];
        for (const book of batch) {
            const isLoaded = await isBookLoaded(contract, book.bookId);
            if (!isLoaded) {
                notLoadedBooks.push(book);
            } else {
                console.log(`⏭️  Book ${book.bookId} already loaded, skipping`);
            }
        }

        if (notLoadedBooks.length === 0) {
            console.log('⏭️  All books in this batch already loaded, moving to next batch');
            progress.batchesCompleted++;
            progress.lastLoadedBookId = Math.max(...batch.map(b => b.bookId));
            saveProgress(progress);
            continue;
        }

        // Prepare batch data
        const batchData = prepareBatchData(notLoadedBooks);

        // Load books with retry
        const result = await loadBooksWithRetry(contract, process.env.MINTING_CONTRACT_ADDRESS, batchData, batchNumber);

        if (result.success) {
            progress.batchesCompleted++;
            progress.lastLoadedBookId = Math.max(...batch.map(b => b.bookId));
            progress.lastTransactionHash = result.hash;
            progress.batchesRemaining = batches.length - batchIndex - 1;
            saveProgress(progress);

            console.log(`✅ Batch ${batchNumber} completed successfully`);
            console.log(`📊 Progress: ${progress.batchesCompleted}/${progress.batchesCompleted + progress.batchesRemaining} batches`);

        } else {
            progress.status = 'failed';
            progress.error = result.error;
            saveProgress(progress);

            console.error(`\n❌ Batch ${batchNumber} failed: ${result.error}`);
            console.error('💾 Progress saved. You can re-run this script to continue from where it left off.');
            process.exit(1);
        }

        // Add delay between batches to avoid rate limiting
        if (batchIndex < batches.length - 1) {
            console.log('⏳ Waiting 2 seconds before next batch...');
            await sleep(2000);
        }
    }

    // Final validation
    console.log('\n🔍 Final validation...');
    let allLoaded = true;
    for (const book of books) {
        const isLoaded = await isBookLoaded(contract, book.bookId);
        if (!isLoaded) {
            console.error(`❌ Book ${book.bookId} not found in contract`);
            allLoaded = false;
        }
    }

    if (allLoaded) {
        progress.status = 'completed';
        console.log('\n🎉 All books loaded successfully!');
        console.log(`📊 Final stats:`);
        console.log(`   - Total books: ${progress.totalBooks}`);
        console.log(`   - Batches completed: ${progress.batchesCompleted}`);
        console.log(`   - Last transaction: ${progress.lastTransactionHash}`);
    } else {
        progress.status = 'validation_failed';
        console.error('\n❌ Final validation failed! Some books are missing.');
    }

    saveProgress(progress);
}

// Run the script
if (require.main === module) {
    loadBooks()
        .then(() => {
            console.log('\n✅ Script completed successfully');
            process.exit(0);
        })
        .catch((error) => {
            console.error('\n❌ Script failed:', error.message);
            console.error(error.stack);
            process.exit(1);
        });
}

module.exports = { loadBooks };