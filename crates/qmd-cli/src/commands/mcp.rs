use anyhow::{Context, Result};
use std::path::Path;
use qmd_mcp::QmdServer;

pub fn run_mcp(index_dir: &Path, http: bool, port: u16) -> Result<()> {
    eprintln!("Initialising QMD MCP server...");
    let server = QmdServer::new(index_dir.to_path_buf())
        .context("failed to create QMD server")?;

    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;

    rt.block_on(async {
        if http {
            qmd_mcp::run_http(server, port).await
        } else {
            qmd_mcp::run_stdio(server).await
        }
    })
}
