# LAB ONLY

Disposable rehearsal of a patch to `.github/macos`, on real GitHub macOS runners. Not part of the
product, and not a base for anything.

- `base/` is SVN r12378, `candidate/` is the same with the patch applied. Their workflow files are
  inert here, because GitHub only reads `.github/workflows` at the top of the tree.
- `tests/` holds simulators and synthetic fixtures. There are no certificates, keys or credentials,
  and the keys in the tests protect nothing.
- `.github/workflows/lab-synthetic-retention-producer.yml` is the only workflow on this branch and
  runs only when dispatched by hand.
