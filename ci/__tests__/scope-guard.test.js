const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
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
  validateScope
} = require('../scope-guard');

describe('Scope Guard Unit Tests', () => {
  describe('namespace checks', () => {
    it('fails when namespace is blanked in sfdx-project.json', () => {
      const result = checkNamespace({ namespace: '' });
      assert.ok(result);
      assert.match(result, /namespace.*must be 'dbt'/);

      const validation = validateScope({
        headProject: { namespace: '' },
        baseProject: { namespace: 'dbt' },
        changedFiles: [],
        prBody: '## Files expected to change\n'
      });
      assert.equal(validation.failures.length, 1);
      assert.match(validation.failures[0], /namespace.*must be 'dbt'/);
    });

    it('fails when namespace is missing or null', () => {
      assert.ok(checkNamespace(null));
      assert.ok(checkNamespace({}));
      assert.ok(checkNamespace({ namespace: null }));
      assert.ok(checkNamespace({ namespace: 'other' }));
    });

    it('passes when namespace is dbt', () => {
      assert.equal(checkNamespace({ namespace: 'dbt' }), null);
    });
  });

  describe('junk path checks', () => {
    it('fails when a path is under .sfdx/', () => {
      assert.equal(isJunkPath('.sfdx/tools/test.json'), true);
      const fails = checkJunkPaths(['.sfdx/tools/test.json']);
      assert.equal(fails.length, 1);
      assert.match(fails[0], /Junk path not allowed/);
    });

    it('fails when a path is under .claude/', () => {
      assert.equal(isJunkPath('.claude/settings.json'), true);
      assert.equal(isJunkPath('.claude/worktrees/agent.json'), true);
      const fails = checkJunkPaths(['.claude/worktrees/agent.json']);
      assert.equal(fails.length, 1);
      assert.match(fails[0], /Junk path not allowed/);
    });

    it('fails when a path is under data/', () => {
      assert.equal(isJunkPath('data/export.json'), true);
      assert.equal(isJunkPath('data/scratch.csv'), true);
      const fails = checkJunkPaths([{ path: 'data/scratch.csv' }]);
      assert.equal(fails.length, 1);
      assert.match(fails[0], /Junk path not allowed/);
    });

    it('fails when a path ends with .zip', () => {
      assert.equal(isJunkPath('bundle.zip'), true);
      assert.equal(isJunkPath('Timesheet/staticresources/asset.ZIP'), true);
      const fails = checkJunkPaths(['archive.zip']);
      assert.equal(fails.length, 1);
      assert.match(fails[0], /Junk path not allowed/);
    });

    it('passes for legitimate paths', () => {
      assert.equal(isJunkPath('Timesheet/main/default/classes/TimesheetController.cls'), false);
      assert.equal(isJunkPath('sfdx-project.json'), false);
      assert.equal(isJunkPath('.github/workflows/ci.yml'), false);
      const fails = checkJunkPaths(['Timesheet/main/default/classes/TimesheetController.cls']);
      assert.equal(fails.length, 0);
    });
  });

  describe('PR body expectation checks', () => {
    it('warns when a claimed file in PR body was not changed', () => {
      const prBody = `
## What changed
Added timesheet feature

## Files expected to change
- Timesheet/main/default/classes/TimesheetController.cls
- Timesheet/main/default/classes/TimesheetControllerTest.cls
`;
      const changedFiles = [
        { status: 'M', path: 'Timesheet/main/default/classes/TimesheetController.cls' }
      ];

      const warnings = checkPrBodyExpectations(prBody, changedFiles);
      assert.equal(warnings.length, 1);
      assert.match(warnings[0], /Claimed file was not changed: Timesheet\/main\/default\/classes\/TimesheetControllerTest\.cls/);

      const validation = validateScope({
        headProject: { namespace: 'dbt' },
        baseProject: { namespace: 'dbt' },
        changedFiles,
        prBody
      });
      assert.equal(validation.failures.length, 0);
      assert.equal(validation.warnings.length, 1);
    });

    it('warns when an unclaimed file changed', () => {
      const prBody = `
## Files expected to change
- Timesheet/main/default/classes/TimesheetController.cls
`;
      const changedFiles = [
        { status: 'M', path: 'Timesheet/main/default/classes/TimesheetController.cls' },
        { status: 'A', path: 'Timesheet/main/default/classes/Unexpected.cls' }
      ];

      const warnings = checkPrBodyExpectations(prBody, changedFiles);
      assert.equal(warnings.length, 1);
      assert.match(warnings[0], /Changed file was not listed in PR body: Timesheet\/main\/default\/classes\/Unexpected\.cls/);
    });

    it('warns when ## Files expected to change heading is missing', () => {
      const prBody = `
## What changed
Updated documentation
`;
      const warnings = checkPrBodyExpectations(prBody, ['README.md']);
      assert.equal(warnings.length, 1);
      assert.match(warnings[0], /No '## Files expected to change' heading found/);
    });

    it('produces no warnings when claimed files and changed files match exactly', () => {
      const prBody = `
## Files expected to change
- \`Timesheet/main/default/classes/Foo.cls\`
- [Timesheet/main/default/classes/Bar.cls](link)
`;
      const changedFiles = [
        'Timesheet/main/default/classes/Foo.cls',
        'Timesheet/main/default/classes/Bar.cls'
      ];
      const warnings = checkPrBodyExpectations(prBody, changedFiles);
      assert.equal(warnings.length, 0);
    });
  });

  describe('version bump and packageAliases checks with and without label', () => {
    const baseProject = {
      namespace: 'dbt',
      packageDirectories: [
        { package: 'Timesheet', versionNumber: '2.33.0.NEXT' }
      ],
      packageAliases: {
        Timesheet: '0Ho4W000000wkQiSAI'
      }
    };

    it('fails when versionNumber bumped without release label', () => {
      const headProject = {
        namespace: 'dbt',
        packageDirectories: [
          { package: 'Timesheet', versionNumber: '2.34.0.NEXT' }
        ],
        packageAliases: {
          Timesheet: '0Ho4W000000wkQiSAI'
        }
      };

      const problemsNoLabel = checkReleaseChanges(baseProject, headProject, []);
      assert.equal(problemsNoLabel.length, 1);
      assert.match(problemsNoLabel[0], /versionNumber changed without 'release' label/);

      const problemsWrongLabel = checkReleaseChanges(baseProject, headProject, 'bugfix,feature');
      assert.equal(problemsWrongLabel.length, 1);
    });

    it('passes when versionNumber bumped with release label', () => {
      const headProject = {
        namespace: 'dbt',
        packageDirectories: [
          { package: 'Timesheet', versionNumber: '2.34.0.NEXT' }
        ],
        packageAliases: {
          Timesheet: '0Ho4W000000wkQiSAI'
        }
      };

      const result1 = checkReleaseChanges(baseProject, headProject, ['release']);
      assert.equal(result1.length, 0);

      const result2 = checkReleaseChanges(baseProject, headProject, 'feature, release');
      assert.equal(result2.length, 0);
    });

    it('fails when packageAliases changed without release label', () => {
      const headProject = {
        ...baseProject,
        packageAliases: {
          ...baseProject.packageAliases,
          'Timesheet@2.34.0-1': '04tbm000000uRNJAA2'
        }
      };

      const problems = checkReleaseChanges(baseProject, headProject, '');
      assert.equal(problems.length, 1);
      assert.match(problems[0], /packageAliases changed without 'release' label/);
    });

    it('passes when packageAliases changed with release label', () => {
      const headProject = {
        ...baseProject,
        packageAliases: {
          ...baseProject.packageAliases,
          'Timesheet@2.34.0-1': '04tbm000000uRNJAA2'
        }
      };

      const problems = checkReleaseChanges(baseProject, headProject, ['release']);
      assert.equal(problems.length, 0);
    });
  });

  describe('deleted metadata warning checks', () => {
    it('warns when a metadata file is deleted', () => {
      const changedFiles = [
        { status: 'D', path: 'Timesheet/main/default/classes/OldClass.cls' }
      ];
      const warnings = checkDeletedMetadata(changedFiles);
      assert.equal(warnings.length, 1);
      assert.match(warnings[0], /Deleted metadata file: Timesheet\/main\/default\/classes\/OldClass\.cls/);
    });

    it('does not warn when a non-metadata file is deleted', () => {
      const changedFiles = [{ status: 'D', path: 'README.md' }];
      const warnings = checkDeletedMetadata(changedFiles);
      assert.equal(warnings.length, 0);
    });
  });

  describe('diff parsing and end-to-end validateScope', () => {
    it('parses git diff --name-status output accurately', () => {
      const raw = `M\tTimesheet/main/default/classes/Foo.cls\nA\tTimesheet/main/default/classes/Bar.cls\nD\tTimesheet/main/default/classes/Old.cls\nR100\told/path.js\tnew/path.js\n`;
      const parsed = parseDiffNameStatus(raw);
      assert.equal(parsed.length, 4);
      assert.deepEqual(parsed[0], { status: 'M', path: 'Timesheet/main/default/classes/Foo.cls' });
      assert.deepEqual(parsed[1], { status: 'A', path: 'Timesheet/main/default/classes/Bar.cls' });
      assert.deepEqual(parsed[2], { status: 'D', path: 'Timesheet/main/default/classes/Old.cls' });
      assert.deepEqual(parsed[3], { status: 'R100', path: 'new/path.js', oldPath: 'old/path.js' });
    });

    it('passes with zero failures and zero warnings for valid changes', () => {
      const baseProject = {
        namespace: 'dbt',
        packageDirectories: [{ package: 'Timesheet', versionNumber: '2.33.0.NEXT' }],
        packageAliases: { Timesheet: '0Ho1' }
      };
      const headProject = { ...baseProject };
      const changedFiles = [
        { status: 'M', path: 'Timesheet/main/default/classes/Foo.cls' }
      ];
      const prBody = `## Files expected to change\n- Timesheet/main/default/classes/Foo.cls\n`;

      const result = validateScope({
        changedFiles,
        headProject,
        baseProject,
        prBody
      });
      assert.equal(result.failures.length, 0);
      assert.equal(result.warnings.length, 0);
    });
  });
});
