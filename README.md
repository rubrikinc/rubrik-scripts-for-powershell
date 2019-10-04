# Powershell - Use Case Scripts

This repository is intended to provide useful Powershell scripts written for specific use cases. Below is an index of these scripts:

NB: This is currently a work-in-progress.

Name | Category | CDM Tested | CDM Versions | Description |
--- | --- | --- | --- | --- |
[Invoke-AzureBlobsProtect](Azure/Invoke-AzureBlobsProtect.ps1) | Azure | Yes | 5.x | AzCopy contents of a given Azure Blobs Container to a Rubrik Managed Volume (EAS)
[Alert-RubrikDatabaseMissedLogBackup.ps1](MSSQL/Alert-RubrikDatabaseMissedLogBackup.ps1)| MSSQL | Add Testing |  | 
[copy-LMDatabaseFiles.ps1](MSSQL/copy-LMDatabaseFiles.ps1)| MSSQL | Add Testing |  | 
[DatabaseBackupReport.ps1](MSSQL/DatabaseBackupReport.ps1)| MSSQL | Add Testing |  | 
[Export-RubrikDatabaseBackup.ps1](MSSQL/Export-RubrikDatabaseBackup.ps1)| MSSQL | Add Testing |  | 
[Export-RubrikDatabasesJob.ps1](MSSQL/Export-RubrikDatabasesJob.ps1)| MSSQL | Add Testing |  | 
[Export-RubrikDatabasesJobFile.json](MSSQL/Export-RubrikDatabasesJobFile.json)| MSSQL | Add Testing |  | 
[Export-RubrikDatabasesJob_V1.ps1](MSSQL/Export-RubrikDatabasesJob_V1.ps1)| MSSQL | Add Testing |  | 
[export-sqlfilelist.ps1](MSSQL/export-sqlfilelist.ps1)| MSSQL | Add Testing |  | 
[invoke-databaserefresh.ps1](MSSQL/invoke-databaserefresh.ps1)| MSSQL | Add Testing |  | 
[invoke-dbmaintenance.ps1](MSSQL/invoke-dbmaintenance.ps1)| MSSQL | Add Testing |  | 
[invoke-exportsql.ps1](MSSQL/invoke-exportsql.ps1)| MSSQL | Add Testing |  | 
[invoke-manualsqlbackup.ps1](MSSQL/invoke-manualsqlbackup.ps1)| MSSQL | Add Testing |  | 
[invoke-MassLiveMount.ps1](MSSQL/invoke-MassLiveMount.ps1)| MSSQL | Add Testing |  | 
[invoke-masssqlrestore.ps1](MSSQL/invoke-masssqlrestore.ps1)| MSSQL | Add Testing |  | 
[invoke-MassUnMount.ps1](MSSQL/invoke-MassUnMount.ps1)| MSSQL | Add Testing |  | 
[invoke-RubrikDatabaseAGRefresh.ps1](MSSQL/invoke-RubrikDatabaseAGRefresh.ps1)| MSSQL | Add Testing |  | 
[Invoke-RubrikDatabaseAGSeed.ps1](MSSQL/Invoke-RubrikDatabaseAGSeed.ps1)| MSSQL | Add Testing |  | 
[invoke-RubrikSqlMvBackup.ps1](MSSQL/invoke-RubrikSqlMvBackup.ps1)| MSSQL | Add Testing |  | 
[invoke-RubrikSqlMvRestore.ps1](MSSQL/invoke-RubrikSqlMvRestore.ps1)| MSSQL | Add Testing |  | 
[invoke-sqlondemand.ps1](MSSQL/invoke-sqlondemand.ps1)| MSSQL | Add Testing |  | 
[mass-livemount.ps1](MSSQL/mass-livemount.ps1)| MSSQL | Add Testing |  | 
[Measure-IOFreeze.ps1](MSSQL/Measure-IOFreeze.ps1)| MSSQL | Add Testing |  | 
[Parse-IOFreeze.ps1](MSSQL/Parse-IOFreeze.ps1)| MSSQL | Add Testing |  |
[Prepare-ExportDatabaseJobFile.ps1](MSSQL/Prepare-ExportDatabaseJobFile.ps1)| MSSQL | Add Testing |  | 
[restore-db-csv.ps1](MSSQL/restore-db-csv.ps1)| MSSQL | Add Testing |  | 
[RunSQLExportTest.ps1](MSSQL/RunSQLExportTest.ps1)| MSSQL | Add Testing |  | 
[set-agprotection.ps1](MSSQL/set-agprotection.ps1)| MSSQL | Add Testing |  | 
[set-sql-sla.ps1](MSSQL/set-sql-sla.ps1)| MSSQL | Add Testing |  | 
[snap-db-csv.ps1](MSSQL/snap-db-csv.ps1)| MSSQL | Add Testing |  | 
[sql-export-example.ps1](MSSQL/sql-export-example.ps1)| MSSQL | Add Testing |  | 
[sql-export-instance.ps1](MSSQL/sql-export-instance.ps1)| MSSQL | Add Testing |  | 
[sql-on-demand.ps1](MSSQL/sql-on-demand.ps1)| MSSQL | Add Testing |  | 
[sql-refresh-example.ps1](MSSQL/sql-refresh-example.ps1)| MSSQL | Add Testing |  | 
[SQLMVOps.ps1](MSSQL/SQLMVOps.ps1)| MSSQL | Add Testing |  | 
[Start-RubrikDBBackup.ps1](MSSQL/Start-RubrikDBBackup.ps1)| MSSQL | Add Testing |  | 
[Start-RubrikDBBackup_V1.ps1](MSSQL/Start-RubrikDBBackup_V1.ps1)| MSSQL | Add Testing |  | 
[Start-RubrikDBLogBackup.ps1](MSSQL/Start-RubrikDBLogBackup.ps1)| MSSQL | Add Testing |  | 
[Start-RubrikDBMigration.ps1](MSSQL/Start-RubrikDBMigration.ps1)| MSSQL | Add Testing |  | 
[Unprotect-DatabaseSnapshotsInRubrik.ps1](MSSQL/Unprotect-DatabaseSnapshotsInRubrik.ps1)| MSSQL | Add Testing |  | 
[New-FileSetSnapshot.ps1](NAS/New-FileSetSnapshot.ps1)| NAS | Add Testing |  | 
[Set-NAS-Share-and-Fileset.ps1](NAS/Set-NAS-Share-and-Fileset.ps1)| NAS | Add Testing |  | 
[install-connector-hufstetler.ps1](RBS/install-connector-hufstetler.ps1)| RBS | Add Testing |  | 
[Install-RubrikBackupService.ps1](RBS/Install-RubrikBackupService.ps1)| RBS | Add Testing |  | 
[install_connector.ps1](RBS/install_connector.ps1)| RBS | Add Testing |  | 
[check-index-status.ps1](Reporting/check-index-status.ps1)| Reporting | Add Testing |  | 
[check_last_backup_time.ps1](Reporting/check_last_backup_time.ps1)| Reporting | Add Testing |  | 
[check_snapshot_archive_status.ps1](Reporting/check_snapshot_archive_status.ps1)| Reporting | Add Testing |  | 
[create_jira_issue_missed_snapshot.ps1](Reporting/create_jira_issue_missed_snapshot.ps1)| Reporting | Add Testing |  | 
[Get-Archive-Backlog.ps1](Reporting/Get-Archive-Backlog.ps1)| Reporting | Add Testing |  | 
[get-lastsnapdate.ps1](Reporting/get-lastsnapdate.ps1)| Reporting | Add Testing |  | 
[get-protection-events-servers.ps1](Reporting/get-protection-events-servers.ps1)| Reporting | Add Testing |  | 
[get-SnapshotRetention.ps1](Reporting/get-SnapshotRetention.ps1)| Reporting | Add Testing |  | 
[get_all_backup_events.ps1](Reporting/get_all_backup_events.ps1)| Reporting | Add Testing |  | 
[get_archive_report.ps1](Reporting/get_archive_report.ps1)| Reporting | Add Testing |  | 
[get_failed_backups.ps1](Reporting/get_failed_backups.ps1)| Reporting | Add Testing |  | 
[get_failed_backups_basic.ps1](Reporting/get_failed_backups_basic.ps1)| Reporting | Add Testing |  | 
[get_reportdata_table_41.ps1](Reporting/get_reportdata_table_41.ps1)| Reporting | Add Testing |  | 
[missed_snapshots_envision.ps1](Reporting/missed_snapshots_envision.ps1)| Reporting | Add Testing |  | 
[per_org_cap_report.ps1](Reporting/per_org_cap_report.ps1)| Reporting | Add Testing |  | 
[sla_report.ps1](Reporting/sla_report.ps1)| Reporting | Add Testing |  | 
[backup_vcd_vapp_metadata.ps1](VM/backup_vcd_vapp_metadata.ps1)| VM | Add Testing |  | 
[restore_vcd_vapp_metadata.ps1](VM/restore_vcd_vapp_metadata.ps1)| VM | Add Testing |  | 
[create_vCenter_User.ps1](VM/create_vCenter_User.ps1)| VM | Add Testing |  | 
[findfiles.ps1](VM/findfiles.ps1)| VM | Add Testing |  | 
[Invoke-DRTest.ps1](VM/Invoke-DRTest.ps1)| VM | Add Testing |  | 
[invoke-krollrecovery.ps1](VM/invoke-krollrecovery.ps1)| VM | Add Testing |  | 
[Invoke-OnDemandSnapshotToSLA.ps1](VM/Invoke-OnDemandSnapshotToSLA.ps1)| VM | Add Testing |  | 
[invoke-vmsnapbyfolder.ps1](VM/invoke-vmsnapbyfolder.ps1)| VM | Add Testing |  | 
[protect_by_tag.ps1](VM/protect_by_tag.ps1)| VM | Add Testing |  | 
[set-auto-consistency.ps1](VM/set-auto-consistency.ps1)| VM | Add Testing |  | 
[set-sla-with-csv.ps1](VM/set-sla-with-csv.ps1)| VM | Add Testing |  | 
[set-toggle-vm-blackout.ps1](VM/set-toggle-vm-blackout.ps1)| VM | Add Testing |  | 
[SPBMtoSLAv3.ps1](VM/SPBMtoSLAv3.ps1)| VM | Add Testing |  | 
[StoragePolicytoSLAv2.ps1](VM/StoragePolicytoSLAv2.ps1)| VM | Add Testing |  | 
[VMDKRecovery.ps1](VM/VMDKRecovery.ps1)| VM | Add Testing |  | 
[VolumeRecovery.ps1](VM/VolumeRecovery.ps1)| VM | Add Testing |  | 
[export-vtpm-guardian-certs.ps1](VM/hyper-v-vtpm/export-vtpm-guardian-certs.ps1)| VM/hyper-v-vtpm | Yes | 5.x.x | Script to export Hyper-V Guardian Certificates from Hyper-V running vTPM
[import-vtpm-guardian-certs.ps1](VM/hyper-v-vtpm/import-vtpm-guardian-certs.ps1)| VM/hyper-v-vtpm | Yes | 5.x.x | Script to import Hyper-V Guardian Certificates to a new Hyper-V host

## :blue_book: Documentation

Here are some resources to get you started! If you find any challenges from this project are not properly documented or are unclear, please raise an issueand let us know! This is a fun, safe environment - don't worry if you're a GitHub newbie! :heart:

* [Rubrik SDK for Powershell](https://github.com/rubrikinc/rubrik-sdk-for-powershell)
* [Rubrik API Documentation](https://github.com/rubrikinc/api-documentation)

## :muscle: How You Can Help

We glady welcome contributions from the community. From updating the documentation to adding more functions for Python, all ideas are welcome. Thank you in advance for all of your issues, pull requests, and comments! :star:

* [Contributing Guide](CONTRIBUTING.md)
* [Code of Conduct](CODE_OF_CONDUCT.md)

## :pushpin: License

* [MIT License](LICENSE)

## :point_right: About Rubrik Build

We encourage all contributors to become members. We aim to grow an active, healthy community of contributors, reviewers, and code owners. Learn more in our [Welcome to the Rubrik Build Community](https://github.com/rubrikinc/welcome-to-rubrik-build) page.

We'd  love to hear from you! Email us: build@rubrik.com :love_letter:


