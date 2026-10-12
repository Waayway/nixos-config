use sea_orm_migration::prelude::*;

#[derive(DeriveMigrationName)]
pub struct Migration;

#[derive(DeriveIden)]
enum HostState {
    Table,
    Name,
    LastStatus,
    LastOkAt,
    ActivationsNext,
}

#[derive(DeriveIden)]
enum Applies {
    Table,
    ApplyId,
    Host,
    Commit,
    RequestedBy,
    RequestedAt,
    State,
    SkipReason,
    Message,
    ExitCode,
    StartedAt,
    FinishedAt,
    Log,
}

#[derive(DeriveIden)]
enum DesiredApplies {
    Table,
    Host,
    ApplyId,
}

#[derive(DeriveIden)]
enum AuditEvents {
    Table,
    Id,
    Time,
    Host,
    Kind,
    Actor,
    Details,
}

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(HostState::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(HostState::Name)
                            .string()
                            .not_null()
                            .primary_key(),
                    )
                    .col(ColumnDef::new(HostState::LastStatus).json().null())
                    .col(ColumnDef::new(HostState::LastOkAt).big_integer().null())
                    .col(
                        ColumnDef::new(HostState::ActivationsNext)
                            .big_integer()
                            .not_null()
                            .default(0),
                    )
                    .to_owned(),
            )
            .await?;
        manager
            .create_table(
                Table::create()
                    .table(Applies::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(Applies::ApplyId)
                            .string()
                            .not_null()
                            .primary_key(),
                    )
                    .col(ColumnDef::new(Applies::Host).string().not_null())
                    .col(ColumnDef::new(Applies::Commit).string().not_null())
                    .col(ColumnDef::new(Applies::RequestedBy).string().not_null())
                    .col(
                        ColumnDef::new(Applies::RequestedAt)
                            .big_integer()
                            .not_null(),
                    )
                    .col(ColumnDef::new(Applies::State).string().not_null())
                    .col(ColumnDef::new(Applies::SkipReason).string().null())
                    .col(ColumnDef::new(Applies::Message).string().null())
                    .col(ColumnDef::new(Applies::ExitCode).integer().null())
                    .col(ColumnDef::new(Applies::StartedAt).big_integer().null())
                    .col(ColumnDef::new(Applies::FinishedAt).big_integer().null())
                    .col(ColumnDef::new(Applies::Log).text().null())
                    .to_owned(),
            )
            .await?;
        manager
            .create_index(
                Index::create()
                    .name("idx_applies_host_requested_at")
                    .table(Applies::Table)
                    .col(Applies::Host)
                    .col(Applies::RequestedAt)
                    .if_not_exists()
                    .to_owned(),
            )
            .await?;
        manager
            .create_table(
                Table::create()
                    .table(DesiredApplies::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(DesiredApplies::Host)
                            .string()
                            .not_null()
                            .primary_key(),
                    )
                    .col(ColumnDef::new(DesiredApplies::ApplyId).string().not_null())
                    .to_owned(),
            )
            .await?;
        manager
            .create_table(
                Table::create()
                    .table(AuditEvents::Table)
                    .if_not_exists()
                    .col(
                        ColumnDef::new(AuditEvents::Id)
                            .big_integer()
                            .not_null()
                            .auto_increment()
                            .primary_key(),
                    )
                    .col(ColumnDef::new(AuditEvents::Time).big_integer().not_null())
                    .col(ColumnDef::new(AuditEvents::Host).string().null())
                    .col(ColumnDef::new(AuditEvents::Kind).string().not_null())
                    .col(ColumnDef::new(AuditEvents::Actor).string().not_null())
                    .col(ColumnDef::new(AuditEvents::Details).json().not_null())
                    .to_owned(),
            )
            .await
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        for t in [
            AuditEvents::Table.into_table_ref(),
            DesiredApplies::Table.into_table_ref(),
            Applies::Table.into_table_ref(),
            HostState::Table.into_table_ref(),
        ] {
            manager
                .drop_table(Table::drop().table(t).if_exists().to_owned())
                .await?;
        }
        Ok(())
    }
}
