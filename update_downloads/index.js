const yaml = require('yaml');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

function load_config() {
    const config = {};
    config.repo_folder = process.env.TARI_WEBSITE_REPO;
    if (!config.repo_folder) {
        throw "TARI_WEBSITE_REPO environment variable must be configured";
    }
    const dl = process.env.DOWNLOADS_YML_PATH || "_data/downloads.yml";
    config.downloads_path = path.join(config.repo_folder, dl);
    const bin = process.env.BINARIES_PATH || "_binaries";
    config.binaries_path = path.join(config.repo_folder, bin);
    return config;
}

function load_metadata(config) {
    let downloads = fs.readFileSync(config.downloads_path, 'utf8');
    let doc = yaml.parse(downloads);
    const fn = (section) => update_metadata(config, section);
    const latest = doc.map(fn).filter(f => !!f);
    return {doc, latest};
}

function update_metadata(config, os) {
    // Ignore libwallet
    if (os.filter_spec && os.filter_spec === "libwallet") {
        return;
    }
    console.log(`Updating ${os.type}`);
    console.log(`Looking for most recent ${os.filter_spec} version..`);
    const filename = find_most_recent(config.binaries_path, os.filter_spec);
    // TODO -- fix brittle hardcoding below
    os.download = `binaries/${filename}`;
    let hash = calc_checksum(path.join(config.binaries_path, filename));
    os.checksum = hash;
    return path.join(config.binaries_path, filename);
}

function find_most_recent(path, substr) {
    let files = fs.readdirSync(path);
    let matches = files.filter((f) => f.match(substr));
    matches = matches.map((fileName) => {
        return {
            name: fileName,
            time: fs.statSync(path + '/' + fileName).mtime.getTime()
        };
    }).sort((a, b) => a.time - b.time)
        .map((v) => v.name);
    console.log(`${matches.length} version found. Selecting ${matches[0]}`);
    return matches[0]
}

function calc_checksum(filename) {
    console.log(`Calculating checksum for ${filename}`);
    const fd = fs.readFileSync(filename);
    const hash = crypto.createHash('sha256');
    // hash.setEncoding('hex');
    hash.update(fd);
    return hash.digest('hex');
}

function main() {
    let config;
    try {
        config = load_config();
    } catch (e) {
        console.error(e);
        process.exit(1);
    }
    const {doc, latest} = load_metadata(config);
    const update  = yaml.stringify(doc);
    fs.writeFileSync(config.downloads_path, update, 'utf8')
}

main();

