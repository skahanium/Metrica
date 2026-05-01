export const DEFAULT_RUNTIME_BASE = "http://127.0.0.1:47821";
export const DEFAULT_RUNTIME_ENDPOINT = `${DEFAULT_RUNTIME_BASE}/fit_model`;
export const DEFAULT_INSPECT_ENDPOINT = `${DEFAULT_RUNTIME_BASE}/inspect_dataset`;
// 默认 CSV 路径相对工作目录解析，便于 Runtime 统一做路径归一化。
export const DEFAULT_DATASET_PATH = "data/demo.csv";
export const DEFAULT_WORKING_DIR = "apps/metrica-desktop";

function createTaskId() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
    return globalThis.crypto.randomUUID();
  }

  return `task-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export function buildFitModelRequest({
  datasetPath,
  formula,
  vcovType = "classical",
  weightsColumn = "",
  clusterColumn = "",
  projectId = "alpha-demo",
  workingDir = DEFAULT_WORKING_DIR,
}) {
  const modelSpec = {
    model_type: "ols",
    formula,
    vcov: {
      type: vcovType,
    },
  };
  const trimmedWeights = weightsColumn.trim();
  if (trimmedWeights) {
    modelSpec.weights = trimmedWeights;
  }
  const trimmedCluster = clusterColumn.trim();
  if (trimmedCluster) {
    modelSpec.cluster_column = trimmedCluster;
  }

  return {
    task_id: createTaskId(),
    action: "fit_model",
    project_context: {
      project_id: projectId,
      working_dir: workingDir,
    },
    dataset_ref: {
      source: "file",
      path: datasetPath,
      format: "csv",
    },
    model_spec: modelSpec,
    options: {
      drop_missing: true,
      return_augment: false,
    },
  };
}

export function buildInspectDatasetRequest({
  datasetPath,
  projectId = "alpha-demo",
  workingDir = DEFAULT_WORKING_DIR,
}) {
  return {
    task_id: createTaskId(),
    action: "inspect_dataset",
    project_context: {
      project_id: projectId,
      working_dir: workingDir,
    },
    dataset_ref: {
      source: "file",
      path: datasetPath,
      format: "csv",
    },
    model_spec: {
      model_type: "ols",
      formula: "",
      vcov: {
        type: "classical",
      },
    },
    options: {
      drop_missing: true,
      return_augment: false,
    },
  };
}

export function parseRuntimeError(response) {
  const firstMessage = response?.messages?.[0];

  return {
    title: response?.status === "error" ? "运行失败" : "请求未完成",
    text: firstMessage?.text || "Runtime 未返回可解析的结果。",
    hint: firstMessage?.hint || "",
    code: firstMessage?.code || "RUNTIME_UNKNOWN",
  };
}

export function normalizeRuntimeError(error) {
  if (error instanceof Error && error.message) {
    return {
      title: "连接失败",
      level: "error",
      code: "runtime_request_failed",
      text: error.message,
      hint: "请确认 Runtime 已启动，且端点地址可访问。",
    };
  }

  return {
    title: "连接失败",
    level: "error",
    code: "runtime_request_failed",
    text: "Runtime 请求失败。",
    hint: "请确认 Runtime 已启动，且端点地址可访问。",
  };
}

export async function postFitModel(endpoint, request, fetchImpl = fetch) {
  let response;

  try {
    response = await fetchImpl(endpoint, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(request),
    });
  } catch (error) {
    return {
      ok: false,
      error: normalizeRuntimeError(error),
    };
  }

  let payload;

  try {
    payload = await response.json();
  } catch (_error) {
    return {
      ok: false,
      error: {
        title: "响应无效",
        level: "error",
        code: "RUNTIME_INVALID_JSON",
        text: "Runtime 返回了无法解析的 JSON。",
        hint: "请检查 Runtime 日志，确认 /fit_model 返回结构化 JSON。",
      },
    };
  }

  if (!response.ok || payload?.status !== "success") {
    return {
      ok: false,
      error: parseRuntimeError(payload),
      response: payload,
    };
  }

  return {
    ok: true,
    response: payload,
  };
}

export async function fitModel({
  endpoint = DEFAULT_RUNTIME_ENDPOINT,
  datasetPath,
  formula,
  vcovType = "classical",
  weightsColumn = "",
  fetchImpl = fetch,
}) {
  const requestBody = buildFitModelRequest({
    datasetPath,
    formula,
    vcovType,
    weightsColumn,
  });
  const result = await postFitModel(endpoint, requestBody, fetchImpl);

  if (!result.ok) {
    throw result.error;
  }

  return result.response;
}

export async function inspectDataset({
  endpoint = DEFAULT_INSPECT_ENDPOINT,
  datasetPath,
  fetchImpl = fetch,
}) {
  const requestBody = buildInspectDatasetRequest({ datasetPath });
  const result = await postFitModel(endpoint, requestBody, fetchImpl);

  if (!result.ok) {
    throw result.error;
  }

  return result.response;
}
