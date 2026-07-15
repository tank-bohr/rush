// semantic-release config for the `live` release branch (rush-qr5.2).
//
// Versions are derived from Conventional Commits merged into `live`:
// fix/perf → patch, feat → minor, `!`/BREAKING CHANGE footer → major; other
// types (ci, build, docs, chore, refactor, test) never release. The release
// commit created here owns lib/rush/version.rb, Gemfile.lock's own-gem line
// and CHANGELOG.md on `live` — never edit those versions on `main`.
//
// Publishing to RubyGems is deliberately NOT done here: the GitHub Release
// below (created with an app token so it can trigger workflows) fires
// publish.yml, which pushes via OIDC trusted publishing with attestations.

// Bump the version constant and the lockfile's own-gem entry, then fail the
// release early if either substitution missed.
const bump = [
  `sed -i "s/VERSION = '[^']*'/VERSION = '\${nextRelease.version}'/" lib/rush/version.rb`,
  // Both lockfile lines carry the version: PATH specs (4-space) and CHECKSUMS
  // (2-space); the DEPENDENCIES entry is versionless and unaffected.
  `sed -i -E "s/^( +rush-shell) \\([0-9][^)]*\\)/\\1 (\${nextRelease.version})/" Gemfile.lock`,
  `grep -q "VERSION = '\${nextRelease.version}'" lib/rush/version.rb`,
  `grep -q "rush-shell (\${nextRelease.version})" Gemfile.lock`,
].join(' && ')

export default {
  branches: ['live'],
  plugins: [
    ['@semantic-release/commit-analyzer', { preset: 'conventionalcommits' }],
    ['@semantic-release/release-notes-generator', { preset: 'conventionalcommits' }],
    '@semantic-release/changelog',
    ['@semantic-release/exec', { prepareCmd: bump }],
    [
      '@semantic-release/git',
      {
        assets: ['CHANGELOG.md', 'lib/rush/version.rb', 'Gemfile.lock'],
        message: 'chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}',
      },
    ],
    '@semantic-release/github',
  ],
}
