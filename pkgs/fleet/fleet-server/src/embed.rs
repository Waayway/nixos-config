//! The built frontend, embedded at compile time from `$FLEET_WEB_DIST` (see `build.rs`).
//! Unknown paths without a file extension get `index.html` (client-side routing).

use axum::http::{StatusCode, Uri, header};
use axum::response::{IntoResponse, Response};
use rust_embed::RustEmbed;

#[derive(RustEmbed)]
#[folder = "$FLEET_WEB_DIST"]
struct Assets;

fn serve(path: &str, file: rust_embed::EmbeddedFile) -> Response {
    let mime = mime_guess::from_path(path).first_or_octet_stream();
    // Vite fingerprints everything but index.html, which must always be revalidated.
    let cache = if path == "index.html" {
        "no-cache"
    } else {
        "public, max-age=3600"
    };
    (
        [
            (header::CONTENT_TYPE, mime.as_ref()),
            (header::CACHE_CONTROL, cache),
        ],
        file.data,
    )
        .into_response()
}

pub async fn static_handler(uri: Uri) -> Response {
    let path = uri.path().trim_start_matches('/');
    let path = if path.is_empty() { "index.html" } else { path };
    if let Some(file) = Assets::get(path) {
        return serve(path, file);
    }
    let is_file = path
        .rsplit('/')
        .next()
        .is_some_and(|last| last.contains('.'));
    match Assets::get("index.html") {
        Some(index) if !is_file => serve("index.html", index),
        _ => (StatusCode::NOT_FOUND, "not found").into_response(),
    }
}
