import test from "node:test";
import assert from "node:assert/strict";

import {
  applyModelControlState,
  modelControlState,
} from "../src/model-controls.js";

test("modelControlState 默认显示 OLS 配置", () => {
  const state = modelControlState("ols");

  assert.equal(state.isPanel, false);
  assert.equal(state.olsHidden, false);
  assert.equal(state.panelHidden, true);
  assert.equal(state.formulaLabel, "OLS 公式");
});

test("modelControlState 面板模型显示面板配置", () => {
  const state = modelControlState("panel");

  assert.equal(state.isPanel, true);
  assert.equal(state.olsHidden, true);
  assert.equal(state.panelHidden, false);
  assert.equal(state.formulaLabel, "面板公式");
});

test("applyModelControlState 更新字段可见性", () => {
  const olsOptions = { hidden: false };
  const panelOptions = { hidden: true };
  const formulaLabel = { textContent: "" };

  const state = applyModelControlState({
    modelType: "panel",
    olsOptions,
    panelOptions,
    formulaLabel,
  });

  assert.equal(state.isPanel, true);
  assert.equal(olsOptions.hidden, true);
  assert.equal(panelOptions.hidden, false);
  assert.equal(formulaLabel.textContent, "面板公式");
});
