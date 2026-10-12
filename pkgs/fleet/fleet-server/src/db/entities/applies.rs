use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel)]
#[sea_orm(table_name = "applies")]
pub struct Model {
    #[sea_orm(primary_key, auto_increment = false)]
    pub apply_id: String,
    pub host: String,
    pub commit: String,
    pub requested_by: String,
    pub requested_at: i64,
    /// snake_case `ApplyState`.
    pub state: String,
    /// snake_case `SkipReason`.
    pub skip_reason: Option<String>,
    pub message: Option<String>,
    pub exit_code: Option<i32>,
    pub started_at: Option<i64>,
    pub finished_at: Option<i64>,
    #[sea_orm(column_type = "Text", nullable)]
    pub log: Option<String>,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
