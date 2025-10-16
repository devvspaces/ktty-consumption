const fs = require('fs');
const path = require('path');

// Read the JSON files
const airdropList = JSON.parse(fs.readFileSync(path.join(__dirname, 'aidroplist.json'), 'utf8'));
const teamList = JSON.parse(fs.readFileSync(path.join(__dirname, 'teamlist.json'), 'utf8'));
const bookDistributions = JSON.parse(fs.readFileSync(path.join(__dirname, 'book-distributions.json'), 'utf8'));

// Extract all IDs from book-distributions.json
const bookDistributionIds = new Set();

// Handle pool1 and pool2 (arrays)
if (Array.isArray(bookDistributions.pool1)) {
  bookDistributions.pool1.forEach(id => bookDistributionIds.add(id));
}
if (Array.isArray(bookDistributions.pool2)) {
  bookDistributions.pool2.forEach(id => bookDistributionIds.add(id));
}

// Handle pool3 (object with buckets)
if (bookDistributions.pool3 && typeof bookDistributions.pool3 === 'object') {
  Object.values(bookDistributions.pool3).forEach(bucket => {
    if (Array.isArray(bucket)) {
      bucket.forEach(id => bookDistributionIds.add(id));
    }
  });
}

// Convert to Sets for efficient lookups
const airdropSet = new Set(airdropList);
const teamSet = new Set(teamList);

// Find clashes between airdroplist and book-distributions
const airdropClashes = airdropList.filter(id => bookDistributionIds.has(id));

// Find clashes between teamlist and book-distributions
const teamClashes = teamList.filter(id => bookDistributionIds.has(id));

// Find clashes between airdroplist and teamlist
const airdropTeamClashes = airdropList.filter(id => teamSet.has(id));

// Display results
console.log('=== ID CLASH ANALYSIS ===\n');

console.log(`Total IDs in aidroplist.json: ${airdropList.length}`);
console.log(`Total IDs in teamlist.json: ${teamList.length}`);
console.log(`Total IDs in book-distributions.json: ${bookDistributionIds.size}\n`);

console.log('--- CLASHES BETWEEN AIDROPLIST AND BOOK-DISTRIBUTIONS ---');
if (airdropClashes.length > 0) {
  console.log(`Found ${airdropClashes.length} clashes:`);
  console.log(airdropClashes.sort((a, b) => a - b));
} else {
  console.log('No clashes found');
}

console.log('\n--- CLASHES BETWEEN TEAMLIST AND BOOK-DISTRIBUTIONS ---');
if (teamClashes.length > 0) {
  console.log(`Found ${teamClashes.length} clashes:`);
  console.log(teamClashes.sort((a, b) => a - b));
} else {
  console.log('No clashes found');
}

console.log('\n--- CLASHES BETWEEN AIDROPLIST AND TEAMLIST ---');
if (airdropTeamClashes.length > 0) {
  console.log(`Found ${airdropTeamClashes.length} clashes:`);
  console.log(airdropTeamClashes.sort((a, b) => a - b));
} else {
  console.log('No clashes found');
}

// Summary
const totalClashes = new Set([...airdropClashes, ...teamClashes, ...airdropTeamClashes]);
console.log(`\n=== SUMMARY ===`);
console.log(`Total unique IDs with clashes: ${totalClashes.size}`);