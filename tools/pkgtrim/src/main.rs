use std::collections::{HashMap, HashSet};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

#[derive(Default)]
struct Package {
    name: String,
    version: String,
    size: u64,
    dependency: bool,
    depends: Vec<String>,
    optional: Vec<String>,
    provides: Vec<String>,
}

#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Summary,
    Orphans,
    Debug,
    Runtimes,
}

fn normalize_dependency(raw: &str) -> String {
    let before_description = raw.split(':').next().unwrap_or(raw).trim();
    before_description
        .split(['<', '>', '='])
        .next()
        .unwrap_or(before_description)
        .trim()
        .to_string()
}

fn sections(text: &str) -> HashMap<String, Vec<String>> {
    let mut result: HashMap<String, Vec<String>> = HashMap::new();
    let mut current = String::new();
    for line in text.lines() {
        if line.starts_with('%') && line.ends_with('%') {
            current = line.trim_matches('%').to_string();
        } else if !line.is_empty() && !current.is_empty() {
            result.entry(current.clone()).or_default().push(line.to_string());
        }
    }
    result
}

fn first(fields: &HashMap<String, Vec<String>>, key: &str) -> String {
    fields
        .get(key)
        .and_then(|values| values.first())
        .cloned()
        .unwrap_or_default()
}

fn load_packages() -> Result<Vec<Package>, String> {
    let database = Path::new("/var/lib/pacman/local");
    let entries = fs::read_dir(database)
        .map_err(|error| format!("cannot read {}: {error}", database.display()))?;
    let mut packages = Vec::new();
    for entry in entries.flatten() {
        let desc = entry.path().join("desc");
        let Ok(text) = fs::read_to_string(desc) else {
            continue;
        };
        let fields = sections(&text);
        let name = first(&fields, "NAME");
        if name.is_empty() {
            continue;
        }
        packages.push(Package {
            name,
            version: first(&fields, "VERSION"),
            size: first(&fields, "SIZE").parse().unwrap_or(0),
            dependency: first(&fields, "REASON") == "1",
            depends: fields.get("DEPENDS").cloned().unwrap_or_default(),
            optional: fields.get("OPTDEPENDS").cloned().unwrap_or_default(),
            provides: fields.get("PROVIDES").cloned().unwrap_or_default(),
        });
    }
    packages.sort_by(|left, right| left.name.cmp(&right.name));
    Ok(packages)
}

fn load_protected() -> HashSet<String> {
    let mut protected = HashSet::new();
    let Some(home) = env::var_os("HOME") else {
        return protected;
    };
    let path = PathBuf::from(home).join(".config/pkgtrim/protect");
    if let Ok(text) = fs::read_to_string(path) {
        for line in text.lines() {
            let name = line.split('#').next().unwrap_or("").trim();
            if !name.is_empty() {
                protected.insert(name.to_string());
            }
        }
    }
    protected
}

fn human_size(bytes: u64) -> String {
    let mib = bytes as f64 / 1_048_576.0;
    if mib >= 1024.0 {
        format!("{:.2} GiB", mib / 1024.0)
    } else {
        format!("{mib:.1} MiB")
    }
}

fn versioned_electron(name: &str) -> bool {
    name.strip_prefix("electron")
        .is_some_and(|suffix| !suffix.is_empty() && suffix.bytes().all(|byte| byte.is_ascii_digit()))
}

fn main() -> ExitCode {
    let mut mode = Mode::Summary;
    let mut names_only = false;
    for argument in env::args().skip(1) {
        match argument.as_str() {
            "--orphans" => mode = Mode::Orphans,
            "--debug" => mode = Mode::Debug,
            "--runtimes" => mode = Mode::Runtimes,
            "--names" => names_only = true,
            "-h" | "--help" => {
                println!("usage: pkgtrim [--orphans|--debug|--runtimes] [--names]");
                println!("protection file: ~/.config/pkgtrim/protect (one package per line)");
                return ExitCode::SUCCESS;
            }
            _ => {
                eprintln!("pkgtrim: unknown option: {argument}");
                return ExitCode::from(2);
            }
        }
    }

    let packages = match load_packages() {
        Ok(packages) => packages,
        Err(error) => {
            eprintln!("pkgtrim: {error}");
            return ExitCode::FAILURE;
        }
    };
    let protected = load_protected();
    let installed: HashMap<&str, usize> = packages
        .iter()
        .enumerate()
        .map(|(index, package)| (package.name.as_str(), index))
        .collect();
    let mut providers: HashMap<String, Vec<usize>> = HashMap::new();
    for (index, package) in packages.iter().enumerate() {
        for provided in &package.provides {
            providers.entry(normalize_dependency(provided)).or_default().push(index);
        }
    }
    let mut required_by = vec![0usize; packages.len()];
    let mut optional_for = vec![0usize; packages.len()];
    for package in &packages {
        for raw in &package.depends {
            let dependency = normalize_dependency(raw);
            if let Some(index) = installed.get(dependency.as_str()).copied() {
                required_by[index] += 1;
            } else if let Some(indexes) = providers.get(&dependency) {
                for index in indexes {
                    required_by[*index] += 1;
                }
            }
        }
        for raw in &package.optional {
            let dependency = normalize_dependency(raw);
            if let Some(index) = installed.get(dependency.as_str()).copied() {
                optional_for[index] += 1;
            } else if let Some(indexes) = providers.get(&dependency) {
                for index in indexes {
                    optional_for[*index] += 1;
                }
            }
        }
    }

    let mut candidates: Vec<(usize, &Package, &str)> = packages
        .iter()
        .enumerate()
        .filter_map(|(index, package)| {
            let kind = if package.name.ends_with("-debug") {
                "debug"
            } else if versioned_electron(&package.name) && required_by[index] == 0 {
                "runtime"
            } else if package.dependency && required_by[index] == 0 && optional_for[index] == 0 {
                "orphan"
            } else {
                return None;
            };
            let selected = match mode {
                Mode::Summary => true,
                Mode::Orphans => kind == "orphan",
                Mode::Debug => kind == "debug",
                Mode::Runtimes => kind == "runtime",
            };
            selected.then_some((index, package, kind))
        })
        .collect();
    candidates.sort_by(|left, right| right.1.size.cmp(&left.1.size));

    if names_only {
        for (_, package, _) in &candidates {
            if !protected.contains(&package.name) {
                println!("{}", package.name);
            }
        }
        return ExitCode::SUCCESS;
    }

    let reclaimable: u64 = candidates
        .iter()
        .filter(|(_, package, _)| !protected.contains(&package.name))
        .map(|(_, package, _)| package.size)
        .sum();
    println!("installed={} candidates={} reclaimable={}", packages.len(), candidates.len(), human_size(reclaimable));
    println!("SIZE       KIND     OPT  PACKAGE VERSION");
    for (index, package, kind) in candidates.iter().take(60) {
        let marker = if protected.contains(&package.name) { "protected" } else { "" };
        println!(
            "{:<10} {:<8} {:>3}  {} {} {}",
            human_size(package.size), kind, optional_for[*index], package.name, package.version, marker
        );
    }
    ExitCode::SUCCESS
}
