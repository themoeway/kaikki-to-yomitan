const { readFileSync, writeFileSync } = require('fs');

const tagOrder = JSON.parse(readFileSync('data/language/tag_order.json'));

const tagOrderAll = [];

for (const [, tags] of Object.entries(tagOrder)) {
    tagOrderAll.push(...tags);
}

// sorts tags to follow `tag_order.json`
// tags not in tag_order are simply added to end of array

function sortTags(targetIso, tags) {
    if (targetIso !== 'en') return tags;

    return tags.sort((a, b) => {
        const indexA = tagOrderAll.indexOf(a);
        const indexB = tagOrderAll.indexOf(b);

        // Check if the tags are in tagOrder
        const isInOrderA = indexA !== -1;
        const isInOrderB = indexB !== -1;

        // Handle cases where both tags are in tagOrder or both are not
        if ((isInOrderA && isInOrderB) || (!isInOrderA && !isInOrderB)) {
            return indexA - indexB;
        }

        // Place the tag that is in tagOrder before the one that is not
        return isInOrderA ? -1 : 1;
    });
}

// sorts inflection entries to be nearby similar inflections

function similarSort(tags) {
    return tags.sort((a, b) => {
        const aWords = a.split(' ');
        const bWords = b.split(' ');

        // Check if the second word exists before comparing
        const mainComparison = (aWords[1] || '').localeCompare(bWords[1] || '');

        if (mainComparison !== 0) {
            return mainComparison;
        }

        for (let i = 0; i < Math.min(aWords.length, bWords.length); i++) {
            if (aWords[i] !== bWords[i]) {
                return aWords[i].localeCompare(bWords[i]);
            }
        }

        return aWords.length - bWords.length;
    });
}


function writeInBatches(tempPath, inputArray, filenamePrefix, batchSize = 100000) {
    consoleOverwrite(`Writing ${inputArray.length.toLocaleString()} entries of ${filenamePrefix}...`);

    let bankIndex = 0;

    while (inputArray.length > 0) {
        const batch = inputArray.splice(0, batchSize);
        bankIndex += 1;
        const filename = `${tempPath}/${filenamePrefix}${bankIndex}.json`;
        const content = JSON.stringify(batch, null, 2);

        writeFileSync(filename, content);
    }
}

function clearConsoleLine() {
    process.stdout.write('\r\x1b[K'); // \r moves the cursor to the beginning of the line, \x1b[K clears the line
}

function consoleOverwrite(text) {
    clearConsoleLine();
    process.stdout.write(text);
}

module.exports = { sortTags, similarSort, writeInBatches, consoleOverwrite, clearConsoleLine };