use tauri_plugin_updater::UpdaterExt;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            setup_autostart();

            // Check for updates in the background so app startup is never blocked.
            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                if let Err(e) = check_for_updates(handle).await {
                    eprintln!("[updater] update check failed: {e}");
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

/// Checks GitHub Releases for a newer signed version. If found, it downloads and
/// installs it silently (passive UI) and relaunches the app. User data lives in
/// the WebView2 data dir keyed by the bundle identifier, so it survives updates.
async fn check_for_updates(app: tauri::AppHandle) -> tauri_plugin_updater::Result<()> {
    let updater = app.updater()?;

    if let Some(update) = updater.check().await? {
        let mut downloaded: usize = 0;
        update
            .download_and_install(
                |chunk, _total| {
                    downloaded += chunk;
                },
                || {
                    eprintln!("[updater] download finished, installing...");
                },
            )
            .await?;

        // Installer applied; relaunch into the new version.
        app.restart();
    }

    Ok(())
}

fn setup_autostart() {
    #[cfg(target_os = "windows")]
    {
        use winreg::enums::{HKEY_CURRENT_USER, KEY_SET_VALUE};
        use winreg::RegKey;

        if let Ok(exe_path) = std::env::current_exe() {
            if let Ok(key) = RegKey::predef(HKEY_CURRENT_USER).open_subkey_with_flags(
                "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run",
                KEY_SET_VALUE,
            ) {
                let _ = key.set_value(
                    "ARZOJournalPro",
                    &exe_path.to_str().unwrap_or(""),
                );
            }
        }
    }
}
