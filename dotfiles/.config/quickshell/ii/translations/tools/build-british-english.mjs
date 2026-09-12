#!/usr/bin/env node
// Print the complete British English catalogue, or verify it with --check.
// Run from any directory. Source strings remain unchanged as translation keys.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const base = JSON.parse(fs.readFileSync(path.join(root, 'translations/en_US.json'), 'utf8'));
const keys = new Set(Object.keys(base));
function scan(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
        if (['.git', 'debug', 'node_modules', 'translations'].includes(entry.name)) continue;
        const filename = path.join(directory, entry.name);
        if (entry.isDirectory()) scan(filename);
        else if (/\.(qml|js)$/.test(entry.name) && !/^test[_-]/.test(entry.name)) {
            const source = fs.readFileSync(filename, 'utf8');
            const literal = /Translation\.tr\s*\(\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`)/gs;
            for (const match of source.matchAll(literal)) {
                // Interpolated strings have no fixed catalogue key.
                if (match[1].startsWith('`') && match[1].includes('${')) continue;
                const key = vm.runInNewContext(match[1], Object.create(null), { timeout: 50 });
                if (key.length) keys.add(key);
            }
        }
    }
}
scan(root);

const spelling = {
    color: 'colour', colors: 'colours', colored: 'coloured', coloring: 'colouring',
    colorize: 'colourise', colorized: 'colourised', colorization: 'colourisation',
    center: 'centre', centers: 'centres', centered: 'centred', centering: 'centring',
    favorite: 'favourite', favorites: 'favourites',
    customize: 'customise', customized: 'customised', customizing: 'customising', customization: 'customisation',
    personalize: 'personalise', personalized: 'personalised', personalization: 'personalisation',
    organize: 'organise', organized: 'organised', organizing: 'organising', organization: 'organisation',
    optimize: 'optimise', optimized: 'optimised', optimizing: 'optimising', optimization: 'optimisation',
    initialize: 'initialise', initialized: 'initialised', initializing: 'initialising', initialization: 'initialisation',
    synchronize: 'synchronise', synchronized: 'synchronised', synchronizing: 'synchronising', synchronization: 'synchronisation',
    analyze: 'analyse', analyzed: 'analysed', analyzing: 'analysing', analyzer: 'analyser',
    recognize: 'recognise', recognized: 'recognised', recognizing: 'recognising',
    authorize: 'authorise', authorized: 'authorised', authorizing: 'authorising', authorization: 'authorisation',
    minimize: 'minimise', minimized: 'minimised', minimizing: 'minimising',
    maximize: 'maximise', maximized: 'maximised', maximizing: 'maximising',
    behavior: 'behaviour', behaviors: 'behaviours',
    canceled: 'cancelled', canceling: 'cancelling', labeled: 'labelled', labeling: 'labelling',
    gray: 'grey', grays: 'greys', grayscale: 'greyscale',
    dialog: 'dialogue', dialogs: 'dialogues', license: 'licence', licenses: 'licences',
    catalog: 'catalogue', catalogs: 'catalogues', analog: 'analogue', airplane: 'aeroplane',
};
function british(text) {
    // Preserve inline code, links, command flags, paths and technical identifiers.
    return text.split(/(`[^`]*`|https?:\/\/\S+|--[\w-]+|\b[\w]+[._][\w.]+\b)/g)
        .map((part, index) => index % 2 ? part : part.replace(/\b[A-Za-z]+\b/g, word => {
            const replacement = spelling[word.toLowerCase()];
            if (!replacement) return word;
            if (word === word.toUpperCase()) return replacement.toUpperCase();
            return /^[A-Z]/.test(word) ? replacement[0].toUpperCase() + replacement.slice(1) : replacement;
        })).join('');
}
const output = Object.fromEntries([...keys].sort().map(key => [key, british(base[key] || key)]));
if (process.argv.includes('--check')) {
    const actual = JSON.parse(fs.readFileSync(path.join(root, 'translations/en_GB.json'), 'utf8'));
    const missing = [...keys].filter(key => typeof actual[key] !== 'string' || !actual[key].length);
    const mismatched = [...keys].filter(key => actual[key] !== output[key]);
    const placeholders = text => (text.match(/%[1-9]\d*|%n|\$\{[^}]+\}/g) || []).sort().join('|');
    const broken = [...keys].filter(key => placeholders(key) !== placeholders(actual[key] || ''));
    if (missing.length || mismatched.length || broken.length) {
        console.error(JSON.stringify({ missing, mismatched, broken }, null, 2));
        process.exitCode = 1;
    } else console.log(`PASS: ${keys.size} British English entries; all source keys and placeholders covered.`);
} else {
    process.stdout.write(JSON.stringify(output, null, 2) + '\n');
}
