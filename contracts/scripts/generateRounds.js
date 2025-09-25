#!/usr/bin/env node

/**
 * Round Timestamp Generator
 * 
 * Generates Solidity-formatted timestamp constants for multiple rounds
 * with customizable durations and start dates.
 * 
 * Usage Examples:
 * node scripts/generateRounds.js --start "2024-01-01" --duration "2 days"
 * node scripts/generateRounds.js --start "2024-01-01" --duration "1 day" --single
 * node scripts/generateRounds.js --start "2024-01-01" --duration "6 hours" --rounds 6
 * 
 * @author KTTY World Development Team
 */

// Parse command line arguments
function parseArgs() {
    const args = process.argv.slice(2);
    const options = {
        start: null,
        duration: '2 days',
        rounds: 4,
        single: false,
        help: false
    };

    for (let i = 0; i < args.length; i++) {
        switch (args[i]) {
            case '--start':
            case '-s':
                options.start = args[i + 1];
                i++;
                break;
            case '--duration':
            case '-d':
                options.duration = args[i + 1];
                i++;
                break;
            case '--rounds':
            case '-r':
                options.rounds = parseInt(args[i + 1]);
                i++;
                break;
            case '--single':
                options.single = true;
                break;
            case '--help':
            case '-h':
                options.help = true;
                break;
            default:
                console.warn(`Unknown option: ${args[i]}`);
        }
    }

    return options;
}

// Show help information
function showHelp() {
    console.log(`
Round Timestamp Generator

Usage: node scripts/generateRounds.js [options]

Options:
  --start, -s <date>        Start date (required)
                            Formats: "2024-01-01", "Jan 1, 2024", timestamp
  
  --duration, -d <duration> Duration between start and end (default: "2 days")
                            Formats: "2 days", "24 hours", "1440 minutes"
  
  --rounds, -r <number>     Number of rounds to generate (default: 4)
  
  --single                  Generate only one start/end pair
  
  --help, -h                Show this help message

Examples:
  # Generate 4 rounds with 2-day duration
  node scripts/generateRounds.js --start "2024-01-01" --duration "2 days"
  
  # Generate single round with 1-day duration
  node scripts/generateRounds.js --start "2024-01-01" --duration "1 day" --single
  
  # Generate 6 rounds with 6-hour duration
  node scripts/generateRounds.js --start "2024-01-01" --duration "6 hours" --rounds 6

Output Format:
  uint256 constant ROUND1_START = 1758326400; // Jan 1, 2024 00:00:00 UTC
  uint256 constant ROUND1_END = 1758412800;   // Jan 2, 2024 00:00:00 UTC
    `);
}

// Parse various date formats into a Date object
function parseDate(dateString) {
    if (!dateString) {
        throw new Error('Date string is required');
    }

    // Try parsing as Unix timestamp (if it's all numbers)
    if (/^\d+$/.test(dateString)) {
        const timestamp = parseInt(dateString);
        // If it looks like seconds (not milliseconds), convert to milliseconds
        if (timestamp < 1e12) {
            return new Date(timestamp * 1000);
        } else {
            return new Date(timestamp);
        }
    }

    // Try parsing various date formats
    const date = new Date(dateString);
    
    if (isNaN(date.getTime())) {
        throw new Error(`Invalid date format: ${dateString}`);
    }

    return date;
}

// Parse duration string into milliseconds
function parseDuration(durationString) {
    if (!durationString) {
        throw new Error('Duration string is required');
    }

    const duration = durationString.toLowerCase().trim();
    
    // Extract number and unit
    const match = duration.match(/^(\d+(?:\.\d+)?)\s*(day|days|hour|hours|minute|minutes|second|seconds|d|h|m|s)$/);
    
    if (!match) {
        throw new Error(`Invalid duration format: ${durationString}. Use formats like "2 days", "24 hours", "1440 minutes"`);
    }

    const value = parseFloat(match[1]);
    const unit = match[2];

    // Convert to milliseconds
    switch (unit) {
        case 'day':
        case 'days':
        case 'd':
            return value * 24 * 60 * 60 * 1000;
        case 'hour':
        case 'hours':
        case 'h':
            return value * 60 * 60 * 1000;
        case 'minute':
        case 'minutes':
        case 'm':
            return value * 60 * 1000;
        case 'second':
        case 'seconds':
        case 's':
            return value * 1000;
        default:
            throw new Error(`Unknown time unit: ${unit}`);
    }
}

// Format date for comment (e.g., "Jan 1, 2024 00:00:00 UTC")
function formatDateComment(date) {
    const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    
    const month = months[date.getUTCMonth()];
    const day = date.getUTCDate();
    const year = date.getUTCFullYear();
    const hours = date.getUTCHours().toString().padStart(2, '0');
    const minutes = date.getUTCMinutes().toString().padStart(2, '0');
    const seconds = date.getUTCSeconds().toString().padStart(2, '0');
    
    return `${month} ${day}, ${year} ${hours}:${minutes}:${seconds} UTC`;
}

// Convert Date to Unix timestamp (seconds)
function dateToUnixTimestamp(date) {
    return Math.floor(date.getTime() / 1000);
}

// Generate a single round
function generateRound(roundNumber, startDate, endDate) {
    const startTimestamp = dateToUnixTimestamp(startDate);
    const endTimestamp = dateToUnixTimestamp(endDate);
    const startComment = formatDateComment(startDate);
    const endComment = formatDateComment(endDate);
    
    return {
        startLine: `uint256 constant ROUND${roundNumber}_START = ${startTimestamp}; // ${startComment}`,
        endLine: `uint256 constant ROUND${roundNumber}_END = ${endTimestamp};   // ${endComment}`
    };
}

// Generate multiple rounds
function generateRounds(startDate, durationMs, numRounds) {
    const rounds = [];
    let currentStart = new Date(startDate);
    
    for (let i = 1; i <= numRounds; i++) {
        const currentEnd = new Date(currentStart.getTime() + durationMs);
        const round = generateRound(i, currentStart, currentEnd);
        rounds.push(round);
        
        // Next round starts where this one ends
        currentStart = new Date(currentEnd);
    }
    
    return rounds;
}

// Main function
function main() {
    const options = parseArgs();
    
    if (options.help) {
        showHelp();
        return;
    }
    
    if (!options.start) {
        console.error('Error: Start date is required. Use --start or -s option.');
        console.log('Use --help for usage information.');
        process.exit(1);
    }
    
    try {
        // Parse inputs
        const startDate = parseDate(options.start);
        const durationMs = parseDuration(options.duration);
        const numRounds = options.single ? 1 : options.rounds;
        
        // Validate inputs
        if (numRounds < 1 || numRounds > 100) {
            throw new Error('Number of rounds must be between 1 and 100');
        }
        
        // Generate rounds
        const rounds = generateRounds(startDate, durationMs, numRounds);
        
        // Output results
        console.log('// Generated Round Timestamps');
        console.log('// Copy and paste into your Solidity contract');
        console.log('');
        
        rounds.forEach(round => {
            console.log(`    ${round.startLine}`);
            console.log(`    ${round.endLine}`);
            if (rounds.indexOf(round) < rounds.length - 1) {
                console.log('');
            }
        });
        
    } catch (error) {
        console.error(`Error: ${error.message}`);
        process.exit(1);
    }
}

// Run the script
if (require.main === module) {
    main();
}

module.exports = {
    parseDate,
    parseDuration,
    formatDateComment,
    dateToUnixTimestamp,
    generateRound,
    generateRounds
};