import test from "node:test";
import assert from "node:assert/strict";

import {
  renderWarnings,
  renderGlance,
  renderTidyRows,
  renderError,
  renderDatasetSummary,
  renderDiagnostics,
  renderPreviewRows,
  renderAugmentPreview,
  renderVcovLabel,
} from "../src/result-view.js";

test("renderWarnings 输出 warning 标题与正文", () => {
  const html = renderWarnings([
    {
      title: "缺失值删样",
      detail: "因模型相关列存在缺失值，已删除 1 行观测。",
    },
  ]);

  assert.match(html, /缺失值删样/);
  assert.match(html, /已删除 1 行观测/);
});

test("renderGlance 输出关键指标卡片", () => {
  const html = renderGlance({
    model: "ols",
    nobs: 7,
    dof: 4,
    metrics: {
      r2: 0.99,
      adj_r2: 0.98,
      sigma: 0.52,
      rss: 1.1,
      tss: 165.4,
    },
  });

  assert.match(html, /样本量/);
  assert.match(html, /调整 R²/);
  assert.match(html, /0\.9900/);
});

test("renderGlance 支持面板模型指标", () => {
  const html = renderGlance({
    model: "fe",
    nobs: 400,
    dof: 377,
    metrics: {
      r2: 0.76,
      adj_r2: 0.74,
      n_ids: 20,
      n_times: 20,
    },
  });

  assert.match(html, /模型/);
  assert.match(html, /fe/);
  assert.match(html, /个体数/);
  assert.match(html, /20\.0000/);
  assert.match(html, /时期数/);
});

test("renderTidyRows 输出系数行", () => {
  const html = renderTidyRows([
    {
      name: "x1",
      estimate: 2.7333,
      stderror: 0.718,
      statistic: 3.80,
      pvalue: 0.019,
    },
  ]);

  assert.match(html, /x1/);
  assert.match(html, /2\.7333/);
  assert.match(html, /0\.0190/);
});

test("renderVcovLabel 输出协方差标签", () => {
  const html = renderVcovLabel("HC1");

  assert.match(html, /协方差/);
  assert.match(html, /HC1/);
});

test("renderDiagnostics 输出全部 7 项诊断结果", () => {
  const html = renderDiagnostics({
    vif: [
      { name: "x1", vif: 1.25 },
      { name: "x2", vif: 2.5 },
    ],
    breusch_pagan: {
      statistic: 3.2,
      pvalue: 0.0736,
      dof: 2,
    },
    white_test: {
      statistic: 5.1,
      pvalue: 0.0778,
      dof: 2,
    },
    durbin_watson: {
      statistic: 1.85,
      pvalue: 0.62,
    },
    breusch_godfrey: {
      statistic: 1.2,
      pvalue: 0.5488,
      dof: 2,
    },
    reset_test: {
      statistic: 0.45,
      pvalue: 0.6453,
      df_num: 2,
      df_den: 4,
    },
    jarque_bera: {
      statistic: 0.82,
      pvalue: 0.6637,
      skewness: 0.15,
      kurtosis: 2.8,
    },
  });

  // VIF
  assert.match(html, /VIF/);
  assert.match(html, /x1/);
  assert.match(html, /1\.2500/);

  // Breusch-Pagan
  assert.match(html, /Breusch-Pagan/);
  assert.match(html, /0\.0736/);

  // White
  assert.match(html, /White/);
  assert.match(html, /0\.0778/);

  // Durbin-Watson
  assert.match(html, /Durbin-Watson/);
  assert.match(html, /1\.85/);

  // Breusch-Godfrey
  assert.match(html, /Breusch-Godfrey/);
  assert.match(html, /0\.5488/);

  // RESET
  assert.match(html, /RESET/);
  assert.match(html, /0\.6453/);

  // Jarque-Bera
  assert.match(html, /Jarque-Bera/);
  assert.match(html, /0\.6637/);
  assert.match(html, /0\.15/);
  assert.match(html, /2\.8/);
});

test("renderDiagnostics 输出面板诊断结果", () => {
  const html = renderDiagnostics({
    hausman: {
      available: true,
      statistic: 4.2,
      pvalue: 0.0404,
      dof: 2,
      method: "hausman_fe_re_diagonal_v1",
      note: "H0: RE 估计量一致。",
    },
    fixed_effect_f: {
      available: true,
      statistic: 18.5,
      pvalue: 0.0001,
      df_num: 11,
      df_den: 346,
      method: "pooled_vs_fe_f",
      note: "H0: 个体固定效应整体不显著。",
    },
    breusch_pagan_lm: {
      available: false,
      method: "breusch_pagan_re_lm_balanced_v1",
      note: "当前 Breusch-Pagan LM v1 仅支持平衡面板。",
    },
  });

  assert.match(html, /Hausman/);
  assert.match(html, /0\.0404/);
  assert.match(html, /固定效应 F/);
  assert.match(html, /18\.5000/);
  assert.match(html, /Breusch-Pagan LM/);
  assert.match(html, /不可用/);
  assert.match(html, /平衡面板/);
});

test("renderError 输出错误与 hint", () => {
  const html = renderError({
    text: "公式中的变量无法在数据集中找到：x9。",
    hint: "请检查公式中的变量名是否与数据列一致。",
  });

  assert.match(html, /运行失败/);
  assert.match(html, /x9/);
  assert.match(html, /变量名是否与数据列一致/);
});

test("renderDatasetSummary 输出列摘要", () => {
  const html = renderDatasetSummary({
    dataset_summary: {
      row_count: 8,
      column_count: 3,
    },
    columns: [
      { name: "y", inferred_type: "Float64", missing_count: 0 },
      { name: "x2", inferred_type: "Float64?", missing_count: 1 },
    ],
  });

  assert.match(html, /8/);
  assert.match(html, /Float64/);
  assert.match(html, /missing/i);
});

test("renderPreviewRows 输出预览行", () => {
  const html = renderPreviewRows(
    [
      { y: 10, x1: 1, x2: 5 },
      { y: 12, x1: 2, x2: 4 },
    ],
    ["y", "x1", "x2"],
  );

  assert.match(html, /<table/);
  assert.match(html, /10/);
  assert.match(html, /x2/);
});

test("renderAugmentPreview 输出逐观测增强数据", () => {
  const html = renderAugmentPreview({
    observation: [1, 2, 3],
    fitted: [10.1, 12.3, 14.5],
    residual: [-0.1, 0.3, -0.5],
    std_residual: [-0.19, 0.57, -0.95],
    leverage: [0.33, 0.34, 0.33],
    cooks_d: [0.01, 0.02, 0.03],
  });

  assert.match(html, /augment/);
  assert.match(html, /fitted/);
  assert.match(html, /residual/);
  assert.match(html, /10\.1/);
  assert.match(html, /-0\.1/);
  assert.match(html, /leverage/);
  assert.match(html, /cooks_d/);
});

test("renderAugmentPreview 无数据时显示空状态", () => {
  const html = renderAugmentPreview(null);

  assert.match(html, /暂无逐观测增强数据/);
  assert.match(html, /return_augment/);
});
