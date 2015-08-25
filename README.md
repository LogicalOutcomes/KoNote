# KoNote

# Install & Run via CLI:

-	`cd` to the repo directory
-	run `npm install` (this will download the right version of NW.js automatically)
-	run `npm start` (this will start the application)


### Release Workflow

#### Feature Freeze (Release - ~1w)

All features (and their corresponding issues) in progress are locked in around 1 week before release; no new features may be added after this point. This gives us a period to finish, test, and fine-tune the new feature branch.

##### Git Flow
1. `git checkout develop` / `g dv`
2. `git pull --rebase` / `g plr`
3. `git branch release-vX.X.X` / `g b release-vX.X.X`
4. `git checkout release-vX.X.X` / `g co release-vX.X.X`
5. `git push -u origin release-vX.X.X` (pushes new branch to remote)

> Development for release continues on this release branch.
> If you accidentally commit release code to develop branch, cherry-pick it over to release-x-x-x

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
5. `git push --tags` (pushes all tags to remote)
6. `git branch -d release-vX.X.X` / `g b -d release-vX.X.X`
7. `git push origin :release-vX.X.X` (deletes branch from remote)
8. `git checkout develop` / `g dv`
9. `git merge --no-ff master` / `g m master`
10. `git push` (push everything else)
11. Celebrate!

### Packaging for Distribution

It might be wise to wait a couple of days before packaging to ensure the given release is stable.

#### the grunt way:

1. Clone repo: `git clone git@github.com:konode001/konote.git`
2. Open repo: `cd konote`
3. Run `npm install`
4. Run `grunt build`
5. *Konote-builds* folder is created beside the repo directory: tasty goodness inside!

- On OSX: Mount DMG and drag KoNote to Applications
- On Windows: Unzip and run KoNote.exe

#### by GUI

See: https://github.com/jyapayne/Web2Executable

#### by CLI

See: https://github.com/nwjs/nw.js/wiki/how-to-package-and-distribute-your-apps#step-1-make-a-package

#### or `The Manual Way`

##### Prepare & Clean Repository
1. Clone repo: `git clone git@github.com:konode001/konote.git`
2. Open repo: `cd konote`
3. Delete `.git` folder inside repo: `rm -rf .git`
4. Run `npm install`
5. Delete `node_modules/nw` or `node_modules/node-webkit`: `rm -rf node_modules/X`
6. Delete this README.md: `rm README.md`

##### Package Raw Version (no specific nwjs OS)
7. Zip up the repo dir, name as: "**KoNote vX.X.X (Raw)**"
8. Upload zip file to Google Docs: /KoNode Team/KoNote/

##### Package OS Version (do for each OS)
9. Download and unzip a copy of NW.js into the repo directory for the appropriate platform (Win/Mac/Linux, 32-/64-bit)
	- Recent Versions: https://github.com/nwjs/nw.js
	- Old Versions: https://github.com/nwjs/nw.js/wiki/Downloads-of-old-versions
10. Zip up the repo dir, name as: "**KoNote vX.X.X Win32/Win64/Mac32/Mac64/Linux32/Linux64**" (switch for OS)
11. Upload zip file to Google Docs: /KoNode Team/KoNote/Releases/vX.X.X

Ask the user to unzip whole folder and run `nw.exe` or `nw.app`
(On Mac if the user gets a warning that nw.app is untrusted they can Ctrl-click and open)

