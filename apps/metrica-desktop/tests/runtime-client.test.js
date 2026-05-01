import test from "node:test";
import assert from "node:assert/strict";

import {
  buildFitModelRequest,
  buildInspectDatasetRequest,
  fitModel,
  inspectDataset,
  DEFAULT_DATASET_PATH,
  DEFAULT_RUNTIME_ENDPOINT,
} from "../src/runtime-client.js";

test("buildFitModelRequest 生成稳定协议对象", () => {
  const request = buildFitModelRequest({
    datasetPath: "/tmp/demo.csv",
    formula: "y ~ x1 + x2",
  });

  assert.equal(request.action, "fit_model");
  assert.equal(request.dataset_ref.path, "/tmp/demo.csv");
  assert.equal(request.model_spec.model_type, "ols");
  assert.equal(request.model_spec.formula, "y ~ x1 + x2");
  assert.equal(request.options.drop_missing, true);
  assert.equal(request.options.return_augment, true);
});

test("buildFitModelRequest 支持协方差与权重字段", () => {
  const request = buildFitModelRequest({
    datasetPath: "/tmp/demo.csv",
    formula: "y ~ x1 + x2",
    vcovType: "HC1",
    weightsColumn: "x1",
  });

  assert.equal(request.model_spec.vcov.type, "HC1");
  assert.equal(request.model_spec.weights, "x1");
});

test("buildFitModelRequest 支持聚类变量字段", () => {
  const request = buildFitModelRequest({
    datasetPath: "/tmp/demo.csv",
    formula: "y ~ x1 + x2",
    vcovType: "cluster",
    clusterColumn: "group_id",
  });

  assert.equal(request.model_spec.vcov.type, "cluster");
  assert.equal(request.model_spec.cluster_column, "group_id");
});

test("fitModel 使用 JSON POST 调用 Runtime", async () => {
  let capturedUrl;
  let capturedOptions;

  const payload = await fitModel({
    endpoint: DEFAULT_RUNTIME_ENDPOINT,
    datasetPath: "/tmp/demo.csv",
    formula: "y ~ x1",
    vcovType: "HC1",
    weightsColumn: "x1",
    fetchImpl: async (url, options) => {
      capturedUrl = url;
      capturedOptions = options;

      return {
        ok: true,
        async json() {
          return { status: "success", result_payload: { glance: {}, tidy: [] } };
        },
      };
    },
  });

  assert.equal(capturedUrl, DEFAULT_RUNTIME_ENDPOINT);
  assert.equal(capturedOptions.method, "POST");
  assert.equal(capturedOptions.headers["Content-Type"], "application/json");
  const body = JSON.parse(capturedOptions.body);
  assert.equal(body.action, "fit_model");
  assert.equal(body.model_spec.vcov.type, "HC1");
  assert.equal(body.model_spec.weights, "x1");
  assert.equal(payload.status, "success");
});

test("fitModel 将网络失败归一化为结构化错误", async () => {
  await assert.rejects(
    fitModel({
      endpoint: DEFAULT_RUNTIME_ENDPOINT,
      datasetPath: "/tmp/demo.csv",
      formula: "y ~ x1",
      fetchImpl: async () => {
        throw new Error("connect ECONNREFUSED");
      },
    }),
    (error) => {
      assert.equal(error.code, "runtime_request_failed");
      assert.match(error.text, /connect ECONNREFUSED/);
      return true;
    },
  );
});

test("buildInspectDatasetRequest 生成稳定协议对象", () => {
  const request = buildInspectDatasetRequest({
    datasetPath: "/tmp/demo.csv",
  });

  assert.equal(request.action, "inspect_dataset");
  assert.equal(request.dataset_ref.path, "/tmp/demo.csv");
});

test("默认请求使用 app 内相对 demo 路径", () => {
  assert.equal(DEFAULT_DATASET_PATH, "data/demo.csv");

  const fitRequest = buildFitModelRequest({
    datasetPath: DEFAULT_DATASET_PATH,
    formula: "y ~ x1 + x2",
  });
  const inspectRequest = buildInspectDatasetRequest({
    datasetPath: DEFAULT_DATASET_PATH,
  });

  assert.equal(fitRequest.dataset_ref.path, DEFAULT_DATASET_PATH);
  assert.equal(fitRequest.project_context.working_dir, "apps/metrica-desktop");
  assert.equal(inspectRequest.dataset_ref.path, DEFAULT_DATASET_PATH);
  assert.equal(inspectRequest.project_context.working_dir, "apps/metrica-desktop");
});

test("inspectDataset 使用 JSON POST 调用 Runtime", async () => {
  let capturedUrl;
  let capturedOptions;

  const payload = await inspectDataset({
    endpoint: "http://127.0.0.1:47821/inspect_dataset",
    datasetPath: "/tmp/demo.csv",
    fetchImpl: async (url, options) => {
      capturedUrl = url;
      capturedOptions = options;

      return {
        ok: true,
        async json() {
          return {
            status: "success",
            result_payload: {
              dataset_summary: { row_count: 2, column_count: 2 },
              columns: [],
              preview_rows: [],
            },
          };
        },
      };
    },
  });

  assert.equal(capturedUrl, "http://127.0.0.1:47821/inspect_dataset");
  assert.equal(capturedOptions.method, "POST");
  assert.equal(JSON.parse(capturedOptions.body).action, "inspect_dataset");
  assert.equal(payload.status, "success");
});
