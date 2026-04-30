use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};

use serde::Serialize;

use crate::{execute_fit_model, health_summary, Message, TaskRequest, TaskResponse};

const DEFAULT_BIND_ADDR: &str = "127.0.0.1:47821";
const ALLOWED_METHODS: &str = "GET, POST, OPTIONS";
const ALLOWED_HEADERS: &str = "Content-Type";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpResponse {
    pub status_code: u16,
    pub headers: Vec<(String, String)>,
    pub body: Vec<u8>,
}

pub fn default_bind_addr() -> &'static str {
    DEFAULT_BIND_ADDR
}

pub fn build_http_response(method: &str, path: &str, body: &[u8]) -> Result<HttpResponse, String> {
    match (method, path) {
        ("GET", "/health") => json_response(200, &health_summary()),
        ("OPTIONS", "/fit_model") | ("OPTIONS", "/inspect_dataset") => Ok(HttpResponse {
            status_code: 204,
            headers: cors_headers(),
            body: Vec::new(),
        }),
        ("POST", "/fit_model") | ("POST", "/inspect_dataset") => {
            let request: TaskRequest = match serde_json::from_slice(body) {
                Ok(request) => request,
                Err(err) => {
                    return json_response(400, &invalid_json_response(err));
                }
            };

            let response = execute_fit_model(&request)?;
            json_response(200, &response)
        }
        ("POST", _) | ("OPTIONS", _) => json_response(
            404,
            &error_response(
                "unknown".to_string(),
                "RUNTIME_HTTP_NOT_FOUND",
                format!("未找到路径 `{path}`。"),
                Some("当前 HTTP 入口仅暴露 /health、/fit_model 与 /inspect_dataset。".to_string()),
            ),
        ),
        _ => json_response(
            405,
            &error_response(
                "unknown".to_string(),
                "RUNTIME_HTTP_METHOD_NOT_ALLOWED",
                format!("HTTP 方法 `{method}` 不受支持。"),
                Some(
                    "请使用 GET /health、POST/OPTIONS /fit_model 或 POST/OPTIONS /inspect_dataset。".to_string(),
                ),
            ),
        ),
    }
}

pub fn serve_http(bind_addr: Option<&str>) -> Result<(), String> {
    let addr = bind_addr.unwrap_or(DEFAULT_BIND_ADDR);
    let listener = TcpListener::bind(addr).map_err(|err| format!("绑定 {addr} 失败: {err}"))?;

    for stream in listener.incoming() {
        match stream {
            Ok(stream) => {
                if let Err(err) = handle_connection(stream) {
                    eprintln!("{err}");
                }
            }
            Err(err) => eprintln!("接受连接失败: {err}"),
        }
    }

    Ok(())
}

fn handle_connection(mut stream: TcpStream) -> Result<(), String> {
    let (method, path, body) = read_http_request(&stream)?;
    let response = build_http_response(&method, &path, &body)?;
    write_http_response(&mut stream, &response)
}

fn read_http_request(stream: &TcpStream) -> Result<(String, String, Vec<u8>), String> {
    let mut reader = BufReader::new(stream);
    let mut request_line = String::new();
    reader
        .read_line(&mut request_line)
        .map_err(|err| format!("读取请求行失败: {err}"))?;

    let mut parts = request_line.split_whitespace();
    let method = parts
        .next()
        .ok_or_else(|| "HTTP 请求缺少 method。".to_string())?
        .to_string();
    let path = parts
        .next()
        .ok_or_else(|| "HTTP 请求缺少 path。".to_string())?
        .to_string();

    let mut content_length = 0usize;
    loop {
        let mut line = String::new();
        reader
            .read_line(&mut line)
            .map_err(|err| format!("读取请求头失败: {err}"))?;

        if line == "\r\n" || line.is_empty() {
            break;
        }

        if let Some((name, value)) = line.split_once(':') {
            if name.eq_ignore_ascii_case("content-length") {
                content_length = value
                    .trim()
                    .parse::<usize>()
                    .map_err(|err| format!("解析 Content-Length 失败: {err}"))?;
            }
        }
    }

    let mut body = vec![0u8; content_length];
    reader
        .read_exact(&mut body)
        .map_err(|err| format!("读取请求体失败: {err}"))?;

    Ok((method, path, body))
}

fn write_http_response(stream: &mut TcpStream, response: &HttpResponse) -> Result<(), String> {
    let status_text = match response.status_code {
        200 => "OK",
        204 => "No Content",
        400 => "Bad Request",
        404 => "Not Found",
        405 => "Method Not Allowed",
        500 => "Internal Server Error",
        _ => "OK",
    };

    let mut head = format!("HTTP/1.1 {} {}\r\n", response.status_code, status_text);
    for (name, value) in &response.headers {
        head.push_str(name);
        head.push_str(": ");
        head.push_str(value);
        head.push_str("\r\n");
    }
    head.push_str(&format!("Content-Length: {}\r\n\r\n", response.body.len()));

    stream
        .write_all(head.as_bytes())
        .map_err(|err| format!("写入响应头失败: {err}"))?;
    stream
        .write_all(&response.body)
        .map_err(|err| format!("写入响应体失败: {err}"))?;
    stream
        .flush()
        .map_err(|err| format!("刷新响应失败: {err}"))?;
    Ok(())
}

fn json_response<T>(status_code: u16, payload: &T) -> Result<HttpResponse, String>
where
    T: Serialize,
{
    let body = serde_json::to_vec(payload).map_err(|err| format!("序列化 HTTP 响应失败: {err}"))?;
    let mut headers = cors_headers();
    headers.push(("Content-Type".to_string(), "application/json".to_string()));

    Ok(HttpResponse {
        status_code,
        headers,
        body,
    })
}

fn cors_headers() -> Vec<(String, String)> {
    vec![
        ("Access-Control-Allow-Origin".to_string(), "*".to_string()),
        (
            "Access-Control-Allow-Methods".to_string(),
            ALLOWED_METHODS.to_string(),
        ),
        (
            "Access-Control-Allow-Headers".to_string(),
            ALLOWED_HEADERS.to_string(),
        ),
    ]
}

fn invalid_json_response(err: impl std::fmt::Display) -> TaskResponse {
    TaskResponse {
        task_id: "unknown".to_string(),
        status: "error".to_string(),
        messages: vec![Message {
            level: "error".to_string(),
            code: "RUNTIME_INVALID_JSON".to_string(),
            text: format!("请求 JSON 解析失败: {err}"),
            hint: Some("请确认请求体符合 runtime-protocol。".to_string()),
        }],
        artifacts: None,
        result_payload: None,
    }
}

fn error_response(task_id: String, code: &str, text: String, hint: Option<String>) -> TaskResponse {
    TaskResponse {
        task_id,
        status: "error".to_string(),
        messages: vec![Message {
            level: "error".to_string(),
            code: code.to_string(),
            text,
            hint,
        }],
        artifacts: None,
        result_payload: None,
    }
}
