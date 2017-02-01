### 1.14.0

This release largely improves the client file analysis tab. The interface is more responsive, informative,
better supports large datasets, and features a new date range selector. Under the hood are many performance
and stability improvements.

#### Improvements

- New analysis date selector (#970)
- Default analysis time span set to 30 days (#827)
- Analysis can be printed (#969)
- Metric definition shown on chart tooltips (#784)
- Analysis chart is more responsive (#967)
- Plan view whitespace condensed by 30% (#1009)
- Section headers are now "sticky" (#1014)
- New programs dropdown on create client file dialog (#999)
- Builds now include End User License Agreement (#1001)

#### Fixes

- Fix issue which could cause incomplete data load of client file (#968)
- Improve progress note search performance (#991)
- Restore data import function (#959)
- Analysis chart enforces a "0" minimum value for display purposes (#998)
- Fix metric/event counts on analysis tab (#998)
- Filter empty entries from prognotes history (#960)
- Filter empty metrics from prognote print (#961)
- Revision history renders line breaks (#935)
- Analysis chart shows events independently of metrics (#822)
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
