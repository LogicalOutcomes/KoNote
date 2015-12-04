# KoNote

## Install & Run via CLI

-	`cd` to the repo directory
-	run `npm install` (this will download the right version of NW.js automatically)
-	run `npm start` (this will start the application)


## Release Workflow

#### Feature Freeze (Release - ~1w)

All features (and their corresponding issues) in progress are locked in around 1 week before release; no new features may be added after this point. This gives us a period to finish, test, and fine-tune the new feature branch.

##### Git Flow
1. `git checkout develop` / `g dv`
2. `git pull --rebase` / `g plr`
3. `git branch release-vX.X.X` / `g b release-vX.X.X`
4. `git checkout release-vX.X.X` / `g co release-vX.X.X`
5. `git push -u origin release-vX.X.X` (pushes new branch to remote)

*Development for release continues on this release branch.*
*If you accidentally commit release code to develop branch, cherry-pick it over to release-x-x-x*

#### Code Freeze (Release - ~2d)

Feature development halts, all hands on deck to run final thorough testing

*(TODO: Testing protocols) and implement fixes.*

#### Version Release

New features are stable and ready for release, all parties have signed off on testing.

We merge our release branch to master, tag it, and delete the release branch. When all is done, we merge master back into develop.

#### Git Flow
1. `git checkout master` / `g co master`
2. `git pull --rebase` / `g plr`
3. `git merge --no-ff release-vX.X.X` / `g m release-vX.X.X`
4. `npm version X.X.X` (updates package.json version, commits and tags)
5. `git push`
6. `git push --tags` (pushes all tags to remote)
7. `git branch -d release-vX.X.X` / `g b -d release-vX.X.X`
8. `git push origin :release-vX.X.X` (deletes branch from remote)
9. `git checkout develop` / `g dv`
10. `git merge --no-ff master` / `g m master`
11. `git push` (push everything else)
12. Celebrate!

## Packaging for Distribution

#### via Grunt:

1. Clone repo: `git clone git@github.com:konode001/konote.git`
2. Open repo: `cd konote`
3. Run `npm install -production` (does not install optional dependencies)
4. Run `grunt build`
5. A *releases* directory is created inside the builds directory

##### Windows builds:
6. Add icon to exe: ResHacker.exe -modify "KoNote.exe", "KoNote.exe", "icon.ico", ICONGROUP, MAINICON, 0
7. Codesign KoNote.exe with DigiSign utility
8. Create installer: Run builds/innosetup script
9. Add icon to installer: ResHacker.exe -modify "KoNote.exe", "KoNote.exe", "icon.ico", ICONGROUP, MAINICON, 0
10. Codesign installer with DigiSign utility

##### Mac builds:
###### Codesign app (requires Xcode). NOT WORKING WITH NWJS < 0.12:
6. Find appropriate security certificate: `security-find-identity`
7. Run `codesign --force --deep --sign "$identity" KoNote.app`
8. Verify signature: `sudo spctl -a -v "KoNote.app"`

#### Manually:

https://github.com/nwjs/nw.js/wiki/how-to-package-and-distribute-your-apps#step-1-make-a-package

##### NWJS builds are available here:
- Recent versions: https://github.com/nwjs/nw.js
- Old versions: https://github.com/nwjs/nw.js/wiki/Downloads-of-old-versions
