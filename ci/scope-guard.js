#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const { execSync } = require('node:child_process');

function isJunkPath(filePath) {
  if (!filePath || typeof filePath !== 'string') return false;
  const norm = filePath.replace(/\\/g, '/').replace(/^\.\//, '');
  return (
    norm === '.sfdx' ||
    norm.startsWith('.sfdx/') ||
    norm.includes('/.sfdx/') ||
    norm === '.claude' ||
    norm.startsWith('.claude/') ||
    norm.includes('/.claude/') ||
    norm === 'data' ||
    norm.startsWith('data/') ||
    norm.toLowerCase().endsWith('.zip')
  );
}

function checkJunkPaths(changedFiles = []) {
  const failures = [];
  for (const item of changedFiles) {
    const filePath = typeof item === 'string' ? item : item?.path;
    const oldPath = typeof item === 'object' ? item?.oldPath : null;
    if (filePath && isJunkPath(filePath)) {
      failures.push(`Junk path not allowed: ${filePath}`);
    } else if (oldPath && isJunkPath(oldPath)) {
      failures.push(`Junk path not allowed: ${oldPath}`);
    }
  }
  return failures;
}

function checkNamespace(sfdxProject) {
  const proj =
    typeof sfdxProject === 'string' ? JSON.parse(sfdxProject) : sfdxProject;
  if (!proj || proj.namespace !== 'dbt') {
    const current = proj ? JSON.stringify(proj.namespace) : 'missing';
    return `sfdx-project.json 'namespace' at HEAD must be 'dbt' (found: ${current})`;
  }
  return null;
}

function hasReleaseLabel(labels) {
  if (!labels) return false;
  const list = Array.isArray(labels) ? labels : String(labels).split(',');
  return list.some((l) => l.trim().toLowerCase() === 'release');
}

function havePackageAliasesChanged(baseProject, headProject) {
  const baseAliases = baseProject?.packageAliases || {};
  const headAliases = headProject?.packageAliases || {};
  const baseKeys = Object.keys(baseAliases);
  const headKeys = Object.keys(headAliases);
  if (baseKeys.length !== headKeys.length) return true;
  for (const k of headKeys) {
    if (baseAliases[k] !== headAliases[k]) return true;
  }
  return false;
}

function getVersionMap(project) {
  const dirs = project?.packageDirectories || [];
  const map = {};
  dirs.forEach((d, i) => {
    const key = d.package || d.path || String(i);
    map[key] = d.versionNumber;
  });
  return map;
}

function haveVersionNumbersChanged(baseProject, headProject) {
  const baseMap = getVersionMap(baseProject);
  const headMap = getVersionMap(headProject);
  const baseKeys = Object.keys(baseMap);
  const headKeys = Object.keys(headMap);
  if (baseKeys.length !== headKeys.length) return true;
  for (const k of headKeys) {
    if (baseMap[k] !== headMap[k]) return true;
  }
  return false;
}

function checkReleaseChanges(baseProject, headProject, labels = []) {
  if (!baseProject || !headProject) return [];
  const base =
    typeof baseProject === 'string' ? JSON.parse(baseProject) : baseProject;
  const head =
    typeof headProject === 'string' ? JSON.parse(headProject) : headProject;

  if (hasReleaseLabel(labels)) return [];

  const problems = [];
  if (havePackageAliasesChanged(base, head)) {
    problems.push("packageAliases changed without 'release' label");
  }
  if (haveVersionNumbersChanged(base, head)) {
    problems.push("versionNumber changed without 'release' label");
  }
  return problems;
}

function isMetadataFile(filePath, packageDirs = ['Timesheet']) {
  if (!filePath || typeof filePath !== 'string') return false;
  const norm = filePath.replace(/\\/g, '/').replace(/^\.\//, '');
  return (
    packageDirs.some((dir) => norm === dir || norm.startsWith(`${dir}/`)) ||
    norm.endsWith('-meta.xml')
  );
}

function checkDeletedMetadata(changedFiles = [], packageDirs = ['Timesheet']) {
  const warnings = [];
  for (const item of changedFiles) {
    if (typeof item === 'object' && item !== null) {
      if (item.status === 'D' && isMetadataFile(item.path, packageDirs)) {
        warnings.push(`Deleted metadata file: ${item.path}`);
      }
    }
  }
  return warnings;
}

function parseDiffNameStatus(diffOutput) {
  if (!diffOutput || typeof diffOutput !== 'string') return [];
  const lines = diffOutput.trim().split(/\r?\n/);
  const items = [];
  for (const line of lines) {
    if (!line.trim()) continue;
    const parts = line.split('\t');
    const status = parts[0].trim();
    if (status.startsWith('R') || status.startsWith('C')) {
      const oldPath = parts[1] ? parts[1].trim() : '';
      const newPath = parts[2] ? parts[2].trim() : '';
      items.push({ status, path: newPath, oldPath });
    } else {
      const filePath = parts[1] ? parts[1].trim() : '';
      items.push({ status, path: filePath });
    }
  }
  return items;
}

function parseExpectedFiles(prBody) {
  if (typeof prBody !== 'string') {
    return { hasHeading: false, expectedFiles: [] };
  }
  const headingRegex = /^##\s+Files expected to change\b.*$/im;
  const match = headingRegex.exec(prBody);
  if (!match) {
    return { hasHeading: false, expectedFiles: [] };
  }

  const afterHeading = prBody.slice(match.index + match[0].length);
  const nextHeadingMatch = /^#{1,6}\s+/m.exec(afterHeading);
  const sectionContent = nextHeadingMatch
    ? afterHeading.slice(0, nextHeadingMatch.index)
    : afterHeading;

  const lines = sectionContent.split(/\r?\n/);
  const files = [];
  for (let line of lines) {
    line = line.replace(/<!--[\s\S]*?-->/g, '').trim();
    if (!line) continue;
    line = line.replace(/^[-*+]\s+/, '').replace(/^\d+\.\s+/, '').trim();
    line = line.replace(/^`+|`+$/g, '').trim();
    const linkMatch = /^\[([^\]]+)\]\(([^)]+)\)$/.exec(line);
    if (linkMatch) {
      line = linkMatch[1].trim();
    }
    line = line.replace(/\\/g, '/').replace(/^\.\//, '').trim();
    if (/^(\(none\)|none|n\/a)$/i.test(line)) continue;
    if (line.length > 0) {
      files.push(line);
    }
  }
  return { hasHeading: true, expectedFiles: files };
}

function checkPrBodyExpectations(prBody, changedFiles = []) {
  const { hasHeading, expectedFiles } = parseExpectedFiles(prBody);
  const warnings = [];

  if (!hasHeading) {
    warnings.push("No '## Files expected to change' heading found in PR body");
    return warnings;
  }

  const changedPaths = changedFiles.map((f) => {
    const raw = typeof f === 'string' ? f : f?.path || '';
    return raw.replace(/\\/g, '/').replace(/^\.\//, '');
  });

  const expectedSet = new Set(expectedFiles);
  const changedSet = new Set(changedPaths);

  for (const file of expectedFiles) {
    if (!changedSet.has(file)) {
      warnings.push(`Claimed file was not changed: ${file}`);
    }
  }

  for (const file of changedPaths) {
    if (!expectedSet.has(file)) {
      warnings.push(`Changed file was not listed in PR body: ${file}`);
    }
  }

  return warnings;
}

function validateScope({
  changedFiles = [],
  headProject = null,
  baseProject = null,
  labels = [],
  prBody = null,
  packageDirs = ['Timesheet']
} = {}) {
  const failures = [];
  const warnings = [];

  failures.push(...checkJunkPaths(changedFiles));

  const nsError = checkNamespace(headProject);
  if (nsError) {
    failures.push(nsError);
  }

  failures.push(...checkReleaseChanges(baseProject, headProject, labels));

  warnings.push(...checkDeletedMetadata(changedFiles, packageDirs));
  warnings.push(...checkPrBodyExpectations(prBody, changedFiles));

  return { failures, warnings };
}

function main() {
  const baseRef = process.env.BASE_REF || 'origin/appexchange';
  const prBodyFile = process.env.PR_BODY_FILE;
  const prLabels = process.env.PR_LABELS || '';

  let diffOutput = '';
  try {
    diffOutput = execSync(`git diff --name-status ${baseRef}...HEAD`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    });
  } catch (err) {
    console.error(`FAIL: git diff --name-status ${baseRef}...HEAD failed: ${err.message}`);
    process.exit(1);
  }

  const changedFiles = parseDiffNameStatus(diffOutput);

  let headProject = null;
  const projectPath = path.resolve(process.cwd(), 'sfdx-project.json');
  if (fs.existsSync(projectPath)) {
    try {
      headProject = JSON.parse(fs.readFileSync(projectPath, 'utf8'));
    } catch (err) {
      console.error(`FAIL: Failed to parse sfdx-project.json at HEAD: ${err.message}`);
      process.exit(1);
    }
  }

  let baseProject = null;
  const sfdxChanged = changedFiles.some((f) => f.path === 'sfdx-project.json');
  if (sfdxChanged) {
    try {
      const baseContent = execSync(`git show ${baseRef}:sfdx-project.json`, {
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe']
      });
      baseProject = JSON.parse(baseContent);
    } catch {
      baseProject = null;
    }
  } else {
    baseProject = headProject;
  }

  let prBody = null;
  if (prBodyFile && fs.existsSync(prBodyFile)) {
    try {
      prBody = fs.readFileSync(prBodyFile, 'utf8');
    } catch (err) {
      console.warn(`WARN: Failed to read PR_BODY_FILE: ${err.message}`);
    }
  }

  const packageDirs = (headProject?.packageDirectories || [])
    .map((d) => d.path)
    .filter(Boolean);
  if (packageDirs.length === 0) packageDirs.push('Timesheet');

  const { failures, warnings } = validateScope({
    changedFiles,
    headProject,
    baseProject,
    labels: prLabels,
    prBody,
    packageDirs
  });

  for (const warn of warnings) {
    console.warn(`WARN: ${warn}`);
  }

  if (failures.length > 0) {
    for (const fail of failures) {
      console.error(`FAIL: ${fail}`);
    }
    process.exit(1);
  }

  console.log('Scope guard passed.');
  process.exit(0);
}

if (require.main === module) {
  main();
}

module.exports = {
  isJunkPath,
  isMetadataFile,
  checkJunkPaths,
  checkNamespace,
  havePackageAliasesChanged,
  haveVersionNumbersChanged,
  hasReleaseLabel,
  checkReleaseChanges,
  parseDiffNameStatus,
  parseExpectedFiles,
  checkPrBodyExpectations,
  checkDeletedMetadata,
  validateScope,
  main
};
