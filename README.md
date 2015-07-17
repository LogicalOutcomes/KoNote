# KoNote

## Install & Run via CLI:

-	`cd` to the repo directory
-	run `npm install` (this will download the right version of NW.js automatically)
-	run `npm start` (this will start the application)



## Release Workflow

### Feature Freeze (Release - ~1w)

All features (and their corresponding issues) in progress are locked in around 1 week before release; no new features may be added after this point. This gives us a period to finish, test, and fine-tune the new feature branch.

#### Git Flow
- `git pull --rebase` / `g plr`
- `git branch release-vX.X.X` / `g b release-vX.X.X`
- `git checkout release-vX.X.X` / `g co release-vX.X.X`
- `git push -u origin release-vX.X.X` (pushes new branch to remote)

> Development for release continues on this release branch.
> If you accidentally commit release code to develop branch, cherry-pick it over to release-x-x-x

### Code Freeze (Release - ~2d)

Feature development halts, all hands on deck to run final thorough testing

*(TODO: Testing protocols) and implement fixes.*

### Version Release

New features are stable and ready for release, all parties have signed off on testing.

We merge our feature branch on to master, tag it, and delete the feature branch. When all is done, we merge master back into develop.

#### Git Flow
- 'git pull --rebase' / `g plr`
- `git checkout master` / `g co master`
- `git merge --no-ff release-vX.X.X` / `g m`
- `git tag -m vX.X.X "Release vX.X.X"`
- `git push origin --tags` (pushes all tags to remote)
- `git branch -d release-vX.X.X` / `g b -d release-vX.X.X`
- `git push origin :release-vX.X.X` (deletes branch from remote)
- `git checkout develop` / `g dv`
- `git merge --no-ff master` / `g m master`



