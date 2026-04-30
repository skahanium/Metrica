use metrica_runtime::{
    default_bind_addr, health_summary, sample_error_response, sample_fit_model_request,
    sample_success_response, serve_axum, JuliaSession,
};
use metrica_runtime::server::serve_oneshot;

#[tokio::main]
async fn main() {
    let mode = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "health".to_string());

    if mode == "serve" {
        let bind_addr = std::env::args()
            .skip(2)
            .find(|a| !a.starts_with("--"))
            .unwrap_or_else(|| default_bind_addr().to_string());
        let oneshot = std::env::args().any(|a| a == "--oneshot");

        if oneshot {
            eprintln!("metrica-runtime 以 oneshot 回退模式启动。");
            serve_oneshot(&bind_addr).await.unwrap();
            return;
        }

        let repo_root = metrica_runtime::repo_root();
        let repo_root_str = repo_root.to_string_lossy().to_string();

        let julia_project = std::env::var("METRICA_JULIA_PROJECT").unwrap_or_else(|_| {
            repo_root
                .join("packages")
                .join("MetricaLinear.jl")
                .to_string_lossy()
                .to_string()
        });

        eprintln!("正在启动 Julia 守护进程...");
        let session = match JuliaSession::start(&repo_root_str, &julia_project) {
            Ok(s) => {
                eprintln!("Julia 守护进程就绪。");
                s
            }
            Err(err) => {
                eprintln!("Julia 守护进程启动失败: {err}");
                eprintln!("将以 degraded 模式运行，请求将返回错误。");
                std::process::exit(1);
            }
        };

        serve_axum(&bind_addr, session).await.unwrap();
        return;
    }

    // CLI 打印模式（health / request / success / error）
    let payload = match mode.as_str() {
        "request" => serde_json::to_string_pretty(&sample_fit_model_request()).unwrap(),
        "success" => serde_json::to_string_pretty(&sample_success_response()).unwrap(),
        "error" => serde_json::to_string_pretty(&sample_error_response()).unwrap(),
        _ => serde_json::to_string_pretty(&health_summary()).unwrap(),
    };

    println!("{payload}");
}
