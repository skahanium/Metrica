import test from "node:test";
import assert from "node:assert/strict";

import {
  buildFitModelRequest,
  buildInspectDatasetRequest,
  fitModel,
  inspectDataset,
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
  assert.equal(request.options.return_augment, false);
});

test("fitModel 使用 JSON POST 调用 Runtime", async () => {
  let capturedUrl;
  let capturedOptions;

  const payload = await fitModel({
    endpoint: DEFAULT_RUNTIME_ENDPOINT,
    datasetPath: "/tmp/demo.csv",
    formula: "y ~ x1",
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
  assert.equal(JSON.parse(capturedOptions.body).action, "fit_model");
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
