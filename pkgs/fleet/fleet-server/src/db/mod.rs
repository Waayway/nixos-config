//! SQLite persistence (SeaORM). Enums are stored as their snake_case serde string.

pub mod entities;

use std::path::Path;

use anyhow::Context;
use fleet_migration::{Migrator, MigratorTrait};
use fleet_proto::{AgentStatus, ApplyRecord, AuditEvent};
use sea_orm::sea_query::OnConflict;
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, ConnectionTrait, Database, DatabaseConnection,
    EntityTrait, QueryFilter, QueryOrder, QuerySelect,
};
use serde::Serialize;

use entities::{applies, audit_events, desired_applies, host_state};

pub async fn connect(state_dir: &Path) -> anyhow::Result<DatabaseConnection> {
    std::fs::create_dir_all(state_dir)
        .with_context(|| format!("creating state dir {}", state_dir.display()))?;
    let url = format!("sqlite://{}?mode=rwc", state_dir.join("fleet.db").display());
    let conn = Database::connect(&url).await.context("opening database")?;
    Migrator::up(&conn, None)
        .await
        .context("running migrations")?;
    Ok(conn)
}

/// snake_case serde string of a unit-variant enum.
fn enum_str<T: Serialize>(v: &T) -> anyhow::Result<String> {
    match serde_json::to_value(v)? {
        serde_json::Value::String(s) => Ok(s),
        other => anyhow::bail!("expected a string enum, got {other}"),
    }
}

pub async fn insert_apply(
    db: &impl ConnectionTrait,
    host: &str,
    requested_by: &str,
    requested_at: i64,
    rec: &ApplyRecord,
) -> anyhow::Result<()> {
    applies::ActiveModel {
        apply_id: Set(rec.apply_id.clone()),
        host: Set(host.to_string()),
        commit: Set(rec.commit.clone()),
        requested_by: Set(requested_by.to_string()),
        requested_at: Set(requested_at),
        state: Set(enum_str(&rec.state)?),
        skip_reason: Set(rec.skip_reason.as_ref().map(enum_str).transpose()?),
        message: Set(rec.message.clone()),
        exit_code: Set(rec.exit_code),
        started_at: Set(rec.started_at),
        finished_at: Set(rec.finished_at),
        log: Set(None),
    }
    .insert(db)
    .await?;
    Ok(())
}

/// Updates state fields of an existing apply from an agent's record. Leaves host,
/// requester and log untouched. Errors if the apply is unknown.
pub async fn update_apply_from_record(
    db: &impl ConnectionTrait,
    rec: &ApplyRecord,
) -> anyhow::Result<()> {
    let existing = applies::Entity::find_by_id(rec.apply_id.clone())
        .one(db)
        .await?
        .with_context(|| format!("unknown apply {}", rec.apply_id))?;
    let mut am: applies::ActiveModel = existing.into();
    am.state = Set(enum_str(&rec.state)?);
    am.skip_reason = Set(rec.skip_reason.as_ref().map(enum_str).transpose()?);
    am.message = Set(rec.message.clone());
    am.exit_code = Set(rec.exit_code);
    am.started_at = Set(rec.started_at);
    am.finished_at = Set(rec.finished_at);
    am.update(db).await?;
    Ok(())
}

pub async fn get_apply(
    db: &impl ConnectionTrait,
    apply_id: &str,
) -> anyhow::Result<Option<applies::Model>> {
    Ok(applies::Entity::find_by_id(apply_id.to_string())
        .one(db)
        .await?)
}

/// Stores the server's copy of an apply's full log. Errors if the apply is unknown.
pub async fn set_apply_log(
    db: &impl ConnectionTrait,
    apply_id: &str,
    log: &str,
) -> anyhow::Result<()> {
    let existing = get_apply(db, apply_id)
        .await?
        .with_context(|| format!("unknown apply {apply_id}"))?;
    let mut am: applies::ActiveModel = existing.into();
    am.log = Set(Some(log.to_string()));
    am.update(db).await?;
    Ok(())
}

pub async fn set_desired(
    db: &impl ConnectionTrait,
    host: &str,
    apply_id: &str,
) -> anyhow::Result<()> {
    desired_applies::Entity::insert(desired_applies::ActiveModel {
        host: Set(host.to_string()),
        apply_id: Set(apply_id.to_string()),
    })
    .on_conflict(
        OnConflict::column(desired_applies::Column::Host)
            .update_column(desired_applies::Column::ApplyId)
            .to_owned(),
    )
    .exec(db)
    .await?;
    Ok(())
}

pub async fn desired(
    db: &impl ConnectionTrait,
    host: &str,
) -> anyhow::Result<Option<applies::Model>> {
    let Some(d) = desired_applies::Entity::find_by_id(host.to_string())
        .one(db)
        .await?
    else {
        return Ok(None);
    };
    Ok(applies::Entity::find_by_id(d.apply_id).one(db).await?)
}

/// Stores the latest agent status and marks the host as last seen OK at `now`.
pub async fn save_status(
    db: &impl ConnectionTrait,
    host: &str,
    status: &AgentStatus,
    now: i64,
) -> anyhow::Result<()> {
    host_state::Entity::insert(host_state::ActiveModel {
        name: Set(host.to_string()),
        last_status: Set(Some(serde_json::to_value(status)?)),
        last_ok_at: Set(Some(now)),
        activations_next: Set(0),
    })
    .on_conflict(
        OnConflict::column(host_state::Column::Name)
            .update_columns([host_state::Column::LastStatus, host_state::Column::LastOkAt])
            .to_owned(),
    )
    .exec(db)
    .await?;
    Ok(())
}

/// Last stored status and the time it was received, if any.
pub async fn load_status(
    db: &impl ConnectionTrait,
    host: &str,
) -> anyhow::Result<Option<(AgentStatus, Option<i64>)>> {
    let Some(row) = host_state::Entity::find_by_id(host.to_string())
        .one(db)
        .await?
    else {
        return Ok(None);
    };
    match row.last_status {
        Some(v) => Ok(Some((serde_json::from_value(v)?, row.last_ok_at))),
        None => Ok(None),
    }
}

pub async fn insert_audit(
    db: &impl ConnectionTrait,
    time: i64,
    host: Option<&str>,
    kind: &str,
    actor: &str,
    details: serde_json::Value,
) -> anyhow::Result<()> {
    audit_events::ActiveModel {
        id: sea_orm::NotSet,
        time: Set(time),
        host: Set(host.map(str::to_string)),
        kind: Set(kind.to_string()),
        actor: Set(actor.to_string()),
        details: Set(details),
    }
    .insert(db)
    .await?;
    Ok(())
}

/// Newest first (by time, then id).
pub async fn recent_audit(
    db: &impl ConnectionTrait,
    limit: u64,
) -> anyhow::Result<Vec<AuditEvent>> {
    let rows = audit_events::Entity::find()
        .order_by_desc(audit_events::Column::Time)
        .order_by_desc(audit_events::Column::Id)
        .limit(limit)
        .all(db)
        .await?;
    Ok(rows.into_iter().map(audit_from_row).collect())
}

fn audit_from_row(r: audit_events::Model) -> AuditEvent {
    AuditEvent {
        id: r.id,
        time: r.time,
        host: r.host,
        kind: r.kind,
        actor: r.actor,
        details: r.details,
    }
}

/// Newest audit event of `kind` for `host`.
pub async fn last_audit(
    db: &impl ConnectionTrait,
    host: &str,
    kind: &str,
) -> anyhow::Result<Option<AuditEvent>> {
    let row = audit_events::Entity::find()
        .filter(audit_events::Column::Host.eq(host))
        .filter(audit_events::Column::Kind.eq(kind))
        .order_by_desc(audit_events::Column::Time)
        .order_by_desc(audit_events::Column::Id)
        .one(db)
        .await?;
    Ok(row.map(audit_from_row))
}

pub async fn activations_next(db: &impl ConnectionTrait, host: &str) -> anyhow::Result<i64> {
    Ok(host_state::Entity::find_by_id(host.to_string())
        .one(db)
        .await?
        .map_or(0, |r| r.activations_next))
}

pub async fn set_activations_next(
    db: &impl ConnectionTrait,
    host: &str,
    n: i64,
) -> anyhow::Result<()> {
    host_state::Entity::insert(host_state::ActiveModel {
        name: Set(host.to_string()),
        last_status: Set(None),
        last_ok_at: Set(None),
        activations_next: Set(n),
    })
    .on_conflict(
        OnConflict::column(host_state::Column::Name)
            .update_column(host_state::Column::ActivationsNext)
            .to_owned(),
    )
    .exec(db)
    .await?;
    Ok(())
}
