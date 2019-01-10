### 2.3.0 (Jan 10, 2019)

2.3.0 adds support for OneDrive data directory and the ability to import and export plan templates. It also completes support for Node v10+.

- Import/Export Plan Templates between instances ([#1240](https://github.com/konode001/konote/issues/1240))
- OneDrive for Business compatibility ([#1243](https://github.com/konode001/konote/issues/1243))
- Various minor fixes ([#1194](https://github.com/konode001/konote/issues/1194), ([666369e](https://github.com/konode001/konote/commit/666369e)), ([851ad6f](https://github.com/konode001/konote/commit/851ad6f)))


### 2.2.9 (Nov 2, 2018)

2.2.9 brings additional user access levels, support for custom metric identifiers, and a better user experience when working with plan templates.

- New 'Basic Admin' role can create and edit basic info in client files ([#1147](https://github.com/konode001/konote/issues/1147))
- Metrics can have optional unique identifier ([#1242](https://github.com/konode001/konote/issues/1242))
- Program override can be disabled via Config ([#1172](https://github.com/konode001/konote/issues/1172))
- Various fixes and improvements ([#1248](https://github.com/konode001/konote/issues/1248), [#1249](https://github.com/konode001/konote/issues/1249), [#1250](https://github.com/konode001/konote/issues/1250))


### 2.2.8 (Sep 11, 2018)

This release adds support for reactivating user accounts and improves program stability.

- Improved support for CSV files created by MS Excel ([#1226](https://github.com/konode001/konote/issues/1226))
- Allow reactivation of user accounts ([#1224](https://github.com/konode001/konote/issues/1224))
- Several bug fixes ([#1229](https://github.com/konode001/konote/issues/1229), [#1245](https://github.com/konode001/konote/issues/1245), [#1193](https://github.com/konode001/konote/issues/1193))


### 2.2.7 (Jul 14, 2018)

Hotfix to address crash which could occur when opening a client file on Dropbox ([#1230](https://github.com/konode001/konote/issues/1230))


### 2.2.6 (Jul 12, 2018)

This maintenance release reduces the number of temp files KoNote creates and improves CSV parsing to accommodate more edge cases.

- Automatically purge temporary lock files ([#1034](https://github.com/konode001/konote/issues/1034))
- Disable templates button until plan has been saved ([#1210](https://github.com/konode001/konote/issues/1210))
- Fix CSV parsing of Excel files ([#1226](https://github.com/konode001/konote/issues/1226))
- Several minor fixes


### 2.2.5 (May 20, 2018)

This release includes some bugfixes and improvements to the plan templates system.

- Can save templates with name of existing template ([#1192](https://github.com/konode001/konote/issues/1192))


### 2.2.4 (May 25, 2018)

This release updates our build process to remain compatible with the latest versions of nwjs and macOS, and includes
a number of general fixes and improvements.

- Migrate to nwjs-builder-phoenix ([#1195](https://github.com/konode001/konote/issues/1195))
- Fix crash on exit for mac ([#1201](https://github.com/konode001/konote/issues/1201))
- Metric import fixes ([#1202](https://github.com/konode001/konote/issues/1202))


### 2.2.3 (May 19, 2018)

#### Improvements

- Close all windows on exit ([#1111](https://github.com/konode001/konote/issues/1111))
- Templates exclude inactive targets by default ([#1191](https://github.com/konode001/konote/issues/1191))
- Plan is now default client file tab ([#1166](https://github.com/konode001/konote/issues/1166))

#### Fixes

- Fix metric import of UTF-8 csv files ([#1187](https://github.com/konode001/konote/issues/1187))
- Program description now optional ([#1197](https://github.com/konode001/konote/issues/1197))
- Better metric tooltip positining ([#1199](https://github.com/konode001/konote/issues/1199))


### 2.2.2 (May 4, 2018)

Maintenance release to fix a regression in the analysis tab introduced in v2.2.1


### 2.2.1 (May 3, 2018)

This release refines some workflows and generally improves the UX, especially in the client file.
The analysis tab gets a number of improvements and the application is more stable when working on busy networks, including DropBox.

#### Improvements

- Improve analysis performance ([#1175](https://github.com/konode001/konote/issues/1175))
- Only show selected metrics on chart legend ([a0f5b53](https://github.com/konode001/konote/commit/a0f5b53))
- Include day of week on chart tooltips, better X-axis labelling ([de9a2c3](https://github.com/konode001/konote/commit/de9a2c3)), ([7daa4c9](https://github.com/konode001/konote/commit/7daa4c9))
- Filter clients by program on search page ([#1128](https://github.com/konode001/konote/issues/1128))
- More informative messaging when adding assigned metrics to plan ([#600](https://github.com/konode001/konote/issues/600))

#### Fixes

- Improve MS Excel compatibility of CSV exports ([#1174](https://github.com/konode001/konote/issues/1174))
- Dropbox file locking fix ([#1168](https://github.com/konode001/konote/issues/1168))
- Progress note does not prompt for program override when client in a single program ([#1180](https://github.com/konode001/konote/issues/1180))
- Progress note program override cleared when client file closed ([#1171](https://github.com/konode001/konote/issues/1171))
- New chart palette prevents metrics from sharing similar colors ([#1176](https://github.com/konode001/konote/issues/1176))


### 2.2.0 (Mar 7, 2018)

This release brings a variety of new features and resolves several stability and usability issues.
A general review during this release cycle also confirmed KoNote's continued fulfilment of the [HIPAA Security Rule Technical Safeguards](https://github.com/konode001/konote/wiki/HIPAA).

#### Improvements

- Support deactivating sections with active targets ([#1092](https://github.com/konode001/konote/issues/1092))
- Improved analysis legend for metrics ([#1118](https://github.com/konode001/konote/issues/1118))
- Windows installer allows user to specify custom locations for the database and application ([#1120](https://github.com/konode001/konote/issues/1120))
- Option to show full plan description while writing a progress note ([#1126](https://github.com/konode001/konote/issues/1126))
- Import metric definitions from CSV ([#1129](https://github.com/konode001/konote/issues/1129))

#### Fixes

- Fix chart navigation bug ([#1097](https://github.com/konode001/konote/issues/1097))
- Allow target description to be blank ([#1124](https://github.com/konode001/konote/issues/1124))
- Fix crash when printing quick note ([#1150](https://github.com/konode001/konote/issues/1150))
- Fix potential XSS vulnerability in dialogs ([#1151](https://github.com/konode001/konote/issues/1151))
- Various UI and stability improvements


### 2.1.12 (Jan 29, 2018)

#### Fixes

- Fix potential freeze during metrics export ([#1105](https://github.com/konode001/konote/issues/1105))
- Improved input validation on new client file dialog ([579a720](https://github.com/konode001/konote/commit/579a7200a8cb22f0306f4aff208631cc7ee21d2b))


### 2.1.11 (Jan 28, 2018)

#### Improvements

- Progress note shift summaries can be edited ([#1112](https://github.com/konode001/konote/issues/1112))
- Several UI and performance improvements

#### Fixes

- Prevent potential crash that could occur while editing events on new progress note ([#1109](https://github.com/konode001/konote/issues/1109))
- Improved formatting of exported metrics and events ([#1107](https://github.com/konode001/konote/issues/1107))


### 2.1.9 (Dec 16, 2017)

#### Improvements

- Improve performance when creating certain objects ([#1104](https://github.com/konode001/konote/issues/1104))

#### Fixes

- Fix issue with truncated text when renaming a section title ([361c74d](https://github.com/konode001/konote/commit/361c74d))


### 2.1.8 (Dec 13, 2017)

This release restores a missing migration file from v2.1.7


### 2.1.7 (Dec 13, 2017)

#### Improvements

- Default client file tab can be set via config ([#1101](https://github.com/konode001/konote/issues/1101))
- Crash log is written to disk instead of localStorage ([#402](https://github.com/konode001/konote/issues/402))

#### Fixes

- Resolve issue that allowed duplicate metric names to be created under certain circumstances ([#109](https://github.com/konode001/konote/issues/109))
- Allow removal of transient targets from unsaved plan ([#1103](https://github.com/konode001/konote/issues/1103))
- Disable user management functions for inactive users ([ef3ed1e](https://github.com/konode001/konote/commit/ef3ed1e))
- Minor UI improvements


### 2.1.6 (Jun 30, 2017)

This releases improves startup performance ([c0ef898](https://github.com/konode001/konote/commit/c0ef898))


### 2.1.5 (Jun 26, 2017)

#### Improvements

- All sections of a progress note can be flagged for highlighting ([be2faed](https://github.com/konode001/konote/commit/be2faed))
- Event type and colour now included in events tab of new prognote window ([#1077](https://github.com/konode001/konote/issues/1077))
- Spellcheck language can be defined via config file ([#810](https://github.com/konode001/konote/issues/810))
- Shift summary prompts user for program if they are not assigned to one ([#1062](https://github.com/konode001/konote/issues/1062))

#### Fixes

- Resolve potential crash on accounts manager page ([579017a](https://github.com/konode001/konote/commit/579017a))
- Resolve potential crash when opening attachments on Windows ([#1065](https://github.com/konode001/konote/issues/1065))
- Include all fields when editing a progress note ([#1074](https://github.com/konode001/konote/issues/1074))
- Global events now show event type, removed legacy 'title' field ([#1085](https://github.com/konode001/konote/issues/1085))
- Programs manager better supports large number of clients ([#1064](https://github.com/konode001/konote/issues/1064))
- Improve button positioning on progress notes tab for new client files ([#1083](https://github.com/konode001/konote/issues/1083))
- Prevent backwards migration and improve version checking ([a5e4f63](https://github.com/konode001/konote/commit/a5e4f63))
- Minor UI improvements


### 2.1.4 (May 17, 2017)

This maintenance release resolves a crash which could occur when applying a plan template to a client file. It also
resolves an issue where the same client file could be opened in multiple windows, and finally improves the status
message when exporting data.

#### Improvements

- Larger definition field when creating a metric ([f957032](https://github.com/konode001/konote/commit/f957032))

#### Fixes

- Resolve crash when applying templates ([#1059](https://github.com/konode001/konote/issues/1059))
- Resolve issue where data export could display "completed" message prematurely ([#1061](https://github.com/konode001/konote/issues/1061))
- Fix extraneous client file window from being opened on double-click ([2dfe0e6](https://github.com/konode001/konote/commit/2dfe0e6c6eb156dde4257bfb4e797d8e7abe3cea))


### 2.1.3 (May 2, 2017)

This point release resolves a couple of minor UI issues from 2.0

#### Improvements

- Improve UX of Account Manager and Account Settings tabs ([cd782fc](https://github.com/konode001/konote/commit/cd782fc1dc82fedf642ec9cfe9c95c59fd519ab2)), ([6dfbb39](https://github.com/konode001/konote/commit/6dfbb39))
- Restyle new installation window to include the End User License Agreement and Support URL ([5a52d66](https://github.com/konode001/konote/commit/5a52d66ed5e662d8945eb6e36b3c2f7001408d1a))


### 2.1.2 (April 30, 2017)

#### Fixes

- Adds additional columnns to plan exported as Word document, per Griffin's requirements.


### 2.1.1 (April 29, 2017)

This maintenance release resolves a potential crash when exporting a plan to Word, and also improves the formatting of
the exported document.

#### Fixes

- Improve plan export to Word ([#1056](https://github.com/konode001/konote/issues/1056))


### 2.1.0 (April 29, 2017)

This release improves the UX when adding metrics to a plan and when selecting metrics for analysis. The analysis pane
also gets the same side panel toggle that the plan and progress note views have. Finally, an 'export to Word' option
has been added to the plan's print preview page.

#### Improvements

- Plan can be exported to Word document ([#1055](https://github.com/konode001/konote/issues/1055))
- Analysis data selection pane can be toggled open or closed ([#1054](https://github.com/konode001/konote/issues/1054))

#### Fixes

- Fix metric lookup results from sometimes being hidden below the viewport ([#1053](https://github.com/konode001/konote/issues/1053))
- Some minor UI improvements


### 2.0 (Apr 21, 2017)

This release marks the stability of the core features of konote. Some of the changes in 2.0 are intended to make
reviewing client information easier, such as the plan outline and history pane toggle. Programs are also more fully
supported. New progress notes now only include plan sections from the author's program. In addition, regular user
permissions have been redefined (see notes for details).

#### Improvements

- New plan outline view ([#1014](https://github.com/konode001/konote/issues/1014))
- History pane toggle ([#296](https://github.com/konode001/konote/issues/296))
- Plan sections can be assigned to program; new progress note includes sections for user's program only
([#697](https://github.com/konode001/konote/issues/697))
- Restrict non admin users from: creating new client files, changing plans, editing metrics, editing event types,
viewing client files outside their program ([#241](https://github.com/konode001/konote/issues/241))
- Show version number in UI ([#1030](https://github.com/konode001/konote/issues/1030))
- Windows releases are now 64-bit by default

#### Fixes

- Auto migration fix ([#1050](https://github.com/konode001/konote/issues/1050))
- Events toggle in analysis was not always working ([#1044](https://github.com/konode001/konote/issues/1044))
- Events overlap metrics in analysis ([#1045](https://github.com/konode001/konote/issues/1045))
- Prognote quick-navigation positioning fix ([#1046](https://github.com/konode001/konote/issues/1046))
- Fix crash which could occur when opening a cancelled quick note ([#1048](https://github.com/konode001/konote/issues/1048))
- Fix regression that allowed long metric names to overly extend the middle pane ([#866](https://github.com/konode001/konote/issues/866)) 
- Fix regression that allowed same client file to be opened in multiple windows ([#722](https://github.com/konode001/konote/issues/722))
- Various UI and performance improvements


### 1.15.1 (Mar 24 2017)

This release resolves a dependency issue which may have prevented the app from starting. It also introduces automatic
migration when importing a previous database through the UI.

#### Improvements

- Automatic migration of database on import ([#974](https://github.com/konode001/konote/issues/974))

#### Fixes

- Explicitly install moment.js (02bae74)
- Support custom headers/footers when printing analysis tab (970e822)


### 1.15.0 (Mar 17 2017)

#### Improvements

- Quick navigation to date in progress notes tab ([#994](https://github.com/konode001/konote/issues/994))
- Analysis can be printed or exported to PNG ([#969](https://github.com/konode001/konote/issues/969))
- Friendly display names for users ([#20](https://github.com/konode001/konote/issues/20))
- Custom print headers and footers ([#913](https://github.com/konode001/konote/issues/913))
- Restyle new progress note window ([#1024](https://github.com/konode001/konote/issues/1024))
- Shift summaries button moved to main menu ([#751](https://github.com/konode001/konote/issues/751))

#### Fixes

- Fix revision link style ([#1007](https://github.com/konode001/konote/issues/1007))
- Fix default filename for export functions ([#1021](https://github.com/konode001/konote/issues/1021))


### 1.14.0 (Feb 1 2017)

This release largely improves the client file analysis tab. The interface is more responsive, informative,
better supports large datasets, and features a new date range selector. Under the hood are several important
performance and stability improvements.

#### Improvements

- New analysis date selector ([#970](https://github.com/konode001/konote/issues/970))
- Default analysis time span set to 30 days ([#827](https://github.com/konode001/konote/issues/827))
- Metric definition shown on chart tooltips ([#784](https://github.com/konode001/konote/issues/784))
- Analysis chart is more responsive ([#967](https://github.com/konode001/konote/issues/967))
- Plan view whitespace condensed by 30% ([#1009](https://github.com/konode001/konote/issues/1009))
- Section headers are now "sticky"([#1014](https://github.com/konode001/konote/issues/1014))
- Words can be added to spellcheck dictionary with right-click ([#811](https://github.com/konode001/konote/issues/811))
- New programs dropdown on create client file dialog ([#999](https://github.com/konode001/konote/issues/999))
- Builds now include End User License Agreement ([#1001](https://github.com/konode001/konote/issues/1001))

#### Fixes

- Fix issue which could cause incomplete data load of client file ([#968](https://github.com/konode001/konote/issues/968))
- Improve progress note search performance ([#991](https://github.com/konode001/konote/issues/991))
- Restore data import function ([#959](https://github.com/konode001/konote/issues/959))
- Analysis chart enforces a "0" minimum value for display purposes ([#998](https://github.com/konode001/konote/issues/998))
- Fix metric/event counts on analysis tab ([#998](https://github.com/konode001/konote/issues/998))
- Filter empty entries from prognotes history ([#960](https://github.com/konode001/konote/issues/960))
- Filter empty metrics from prognote print ([#961](https://github.com/konode001/konote/issues/961))
- Revision history renders line breaks ([#935](https://github.com/konode001/konote/issues/935))
- Analysis chart shows events independently of metrics ([#822](https://github.com/konode001/konote/issues/822))
- Various other fixes and stability improvements


### 1.13.1 (Dec 15 2016)

This maintenance release improves search performance and fixes a crash which could occur when closing a client
file in certain cases.

#### Improvements

- Improved options menu (edit/print/discard) in progress note header (#934)

#### Fixes

- Fix crash when closing a client file before it has fully loaded (#745)
- Events search filter now excludes all non-event data (#953)
- Search results cleared when search bar closed (#955)
- Improve search performance (#956)


### 1.13.0 (Dec 14 2016)

This release brings the ability to search and filter data within a client file. It further refines the style
of 1.12, with data more intelligently displayed throughout, including some important fixes for metric values.
Additionally, the file size of the Windows release has been reduced by 20%.

#### Improvements

- Progress notes can be searched / filtered (#135, #512)
- Metrics can be searched in manager tab (#685)
- Plan details are shown in progress note history (#846)
- New toolbar in plan tab (fd23448)
- Removed timeout notification (#749)

#### Fixes

- Long metric values stretch input (#803)
- Printed pages render line breaks (#948)
- Metric name length limited to 50 characters (#937)
- Fix Windows uninstall utility (#920)
- Cancelling a progress note cancels associated global events (#841)
- Executable files not permitted in attachments (#788)
- KoNote version included in crash log (#820)
- Events listed alphabetically in analysis (#895)
- Scrollbars always visible (#926, #861)
- Various other style, performance, and UI improvements


### 1.12.4 (Dec 1 2016)

This maintenance release fixes a crash inadvertently introduced by (#922) in 1.12.2.
It will be the last release for today :)


### 1.12.3 (Dec 1 2016)

This maintenance release fixes a crash inadvertently introduced by (#923) in 1.12.2


### 1.12.2 (Dec 1 2016)

This maintenance release addresses several sorting and display issues in the progress notes tab.

#### Fixes

- Ensure most recent notes are displayed after initial data load (6fe61a8)
- Progress note history includes blank entries if they have a metric value (#922)
- Fix prognote cancellation dialog not closing (#923)
- Add uniqueness check to second pass prognote histories (0f46893)


### 1.12.1 (Nov 24 2016)

This maintenance release improves the stability of 1.12.

#### Fixes

- Fix crash when closing new prognote window prematurely (#907)
- Fix crash cancelling an event (#904)
- Fix event tooltip title in analysis (#906)
- Fix client file loading delay in read-only mode (#902)
- Fix client info save/discard buttons persisting after save (#903)
- Nicer event formatting in prognote tab (#905)


### 1.12.0 (Nov 18 2016)

This release generally improves performance. Startup time is 50% faster and client file loading times are also
significantly faster. Responsiveness has been improved throughout, and we've tried to eliminate most sources
of latency (such as when navigating between tabs or highlighting items on a chart). We've also made
performance more consistent when dealing with very large databases.

#### Improvements

- Faster startup time (#830, #831, #865)
- Faster client file loading time (#671, #800)
- Faster progress note saving time
- Faster transitions between pages and history (#859)
- Events have a singular description instead of both a title and a description (#871)
- Events in analysis can be highlighted (#817)
- Items in the analysis legend include a count for the number of items displayed (#825)
- Plan can be printed as a "cheat sheet" including metric definitions (#781)
- Client information includes additional fields (DOB, Care Providers) (#823)
- Templates have descriptions, and can be viewed from manager layer (#758, #786)
- Various other performance, style and UI improvements

#### Fixes

- Targets without metrics are no longer displayed in analysis (#815)
- Backdated notes use backdate for default event start date (#888)
- Event end-date defaults to day after start date (#857)
- Datepicker better supports years / decades (#851)
- Events can be edited when editing a progress note (#248)
- Cancelling a progress note cancels associated events (#813)


### 1.11.0

#### Improvements

- Add client information page (#114)
- Support for file attachments in quick notes (#721)
- New UI for plan view (#767, #780)
- Allow reordering of plan sections and targets (#80)
- Nicer formating of printed pages (#808)

#### Fixes

- Fix input latency on new progress note page (#783)
- Apply template without requiring a section (#785)
- Programs can be deactivated (#760)
- Various other fixes and stability improvements
