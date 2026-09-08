# This branch is a laboratory, not the product

This is `Dkijas/simutrans`, a personal fork used to rehearse the macOS signing
workflow. **Nothing here should be merged anywhere.**

The workflow being rehearsed cannot be run in `simutrans/simutrans` yet:
GitHub only offers `workflow_dispatch` for a workflow that already exists on
the repository's default branch, so it has to be committed there first. That
would mean asking a maintainer to commit something that has never been
executed. This fork exists so it can be executed first.

## Every difference from the production branch

Three, and no more. All are listed here so that the production patch can be
checked against this list.

### 0. Two synthetic-rehearsal workflows that do not exist in production

    lab-synthetic-retention-producer.yml
    lab-synthetic-retention-consumer.yml

They rehearse the retention transport with a fake package: the producer
stores one, the consumer recovers it from a different run on a different
runner. They build nothing, sign nothing, touch no Developer ID and no
notarization credential, and declare no `environment:`, so no production
secret is reachable from them at all.

The key they use is published in the workflow files and marked TEST-ONLY, and
the payload is synthetic. So what they demonstrate is **transport and
integrity** - that a container survives GitHub's artifact storage and comes
back byte for byte. They demonstrate nothing about confidentiality or about
custody of a real key, and must not be described as if they did.

### 1. Eight publishing workflows are deleted

    makeobj.yml                    -> release asset
    nightly-android.yml            -> release assets + Google Play
    nightly-macos-arm.yml          -> release asset
    nightly-macos-intel.yml        -> release asset
    nightly-ubuntu.yml             -> release asset
    nightly-windows-ms.yml         -> release asset
    nightly-windows64-SDL2-ms.yml  -> release asset
    update-nightly-release.yml     -> moves the Nightly tag, renames the release

All eight are `on: [push]` with no branch filter. Left in place, pushing to
this fork would create a release here and start a Play Store upload. They are
removed so that a push to the lab publishes nothing at all.

`run-tests.yml` is deliberately **kept**. It is `on: [push]` but it publishes
nothing, and removing it would be a change nobody asked for. It fails here for
the same pre-existing reason it fails on `master` upstream.

### 2. The signing job's repository gate is widened

Production:

```yaml
if: github.repository == 'simutrans/simutrans'
```

Lab:

```yaml
if: github.repository == 'simutrans/simutrans' || github.repository == 'Dkijas/simutrans'
```

Without this, the signing job would be skipped here and the point of the
rehearsal — showing that a run with no credentials fails cleanly and produces
nothing that looks signed — could not be demonstrated at all.

## What is NOT changed, and must not be

No trust check is relaxed to make the lab pass:

* the revision still has to be on the default branch's history;
* a tag still grants nothing;
* the Subversion base revision still has to be resolvable, or the run fails;
* the payload check, the certificate validation, the signature verification
  and the final Gatekeeper gate are all untouched.

If any of those had to be weakened to get a green run here, that would be a
finding about the workflow, not a thing to work around.

## Configuration differences from the official repository

Worth knowing when reading a lab result, because they are not the same
environment:

| | `simutrans/simutrans` | this fork |
| --- | --- | --- |
| Default branch | `master`, mirror of SVN trunk | `master`, fast-forwarded to the lab commit |
| Publishing workflows | 8, all `on: [push]` | none |
| `macos-signing` environment | to be created with required reviewers | auto-created empty on first use, no protection rules |
| Signing secrets | to be configured by maintainers | **none, and none will be** |
| Google Play credentials | organisation secrets | not available to a fork |

The empty auto-created environment is itself part of what the rehearsal shows:
it is exactly the state a maintainer would be in before configuring anything,
and the workflow is supposed to stop there with a message naming what is
missing rather than producing an unsigned package.

## No credentials here, ever

No certificate, no `.p12`, no `.p8`, no password is placed in this fork. The
rehearsal that uses a real Developer ID is a separate step, requires separate
authorisation, and does not happen here.
