import {
  DEFAULT_DATASET_PATH,
  DEFAULT_RUNTIME_BASE,
  fitModel,
  inspectDataset,
} from "./runtime-client.js";
import {
  renderDatasetSummary,
  renderError,
  renderGlance,
  renderMessagesMarkup,
  renderPreviewRows,
  renderSummaryText,
  renderTidyRows,
  renderVcovLabel,
  renderWarnings,
} from "./result-view.js";

const runtimeBaseInput = document.getElementById("runtime-base");
const datasetInput = document.getElementById("dataset-path");
const chooseFileButton = document.getElementById("choose-file");
const inspectButton = document.getElementById("inspect-dataset");
const filePicker = document.getElementById("file-picker");
const formulaInput = document.getElementById("formula-input");
const vcovTypeInput = document.getElementById("vcov-type");
const weightsColumnInput = document.getElementById("weights-column");
const runButton = document.getElementById("run-model");
const statusText = document.getElementById("status-text");
const errorBox = document.getElementById("error-box");
const messageBox = document.getElementById("message-box");
const warningBox = document.getElementById("warning-box");
const datasetSummaryBox = document.getElementById("dataset-summary-box");
const previewBox = document.getElementById("preview-box");
const glanceBox = document.getElementById("glance-box");
const summaryBox = document.getElementById("summary-box");
const vcovLabelBox = document.getElementById("vcov-label-box");
const tidyTableBody = document.querySelector("#tidy-table tbody");

runtimeBaseInput.value = DEFAULT_RUNTIME_BASE;
datasetInput.value = DEFAULT_DATASET_PATH;

function resetResultArea() {
  errorBox.hidden = true;
  errorBox.innerHTML = "";
  messageBox.innerHTML = "";
  warningBox.hidden = false;
  warningBox.innerHTML = renderWarnings([]);
  datasetSummaryBox.innerHTML = renderDatasetSummary(null);
  previewBox.innerHTML = renderPreviewRows([], []);
  glanceBox.hidden = false;
  glanceBox.innerHTML = renderGlance(null);
  summaryBox.hidden = false;
  summaryBox.innerHTML = renderSummaryText(null);
  vcovLabelBox.innerHTML = "";
  tidyTableBody.innerHTML = `
    <tr>
      <td colspan="5" class="empty-row">等待 Runtime 返回结构化 tidy。</td>
    </tr>
  `;
}

function runtimeEndpoint(path) {
  const base = runtimeBaseInput.value.trim().replace(/\/$/, "");
  return `${base}${path}`;
}

function showError(message) {
  errorBox.hidden = false;
  errorBox.innerHTML = renderError(message);
}

function showMessages(messages) {
  messageBox.innerHTML = renderMessagesMarkup(messages || []);
}

function showWarnings(warnings) {
  warningBox.innerHTML = renderWarnings(warnings);
}

function showGlance(glance) {
  glanceBox.innerHTML = renderGlance(glance);
}

function showSummary(summaryText) {
  summaryBox.innerHTML = renderSummaryText(summaryText);
}

function showTidy(rows) {
  tidyTableBody.innerHTML = renderTidyRows(rows);
}

function showVcovLabel(vcovLabel) {
  vcovLabelBox.innerHTML = renderVcovLabel(vcovLabel);
}

function showInspection(payload) {
  datasetSummaryBox.innerHTML = renderDatasetSummary(payload);
  previewBox.innerHTML = renderPreviewRows(
    payload.preview_rows || [],
    (payload.columns || []).map((column) => column.name),
  );
  showWarnings(payload.warnings || []);
}

async function inspectCurrentDataset() {
  const datasetPath = datasetInput.value.trim();

  if (!datasetPath) {
    showError({
      title: "数据集路径为空",
      code: "APP_INVALID_INPUT",
      text: "请先选择或填写 CSV 文件路径。",
      hint: "可以使用“选择文件”按钮或手工填写路径。",
    });
    return;
  }

  inspectButton.disabled = true;
  statusText.textContent = "检查数据中...";
  errorBox.hidden = true;
  errorBox.innerHTML = "";

  try {
    const response = await inspectDataset({
      endpoint: runtimeEndpoint("/inspect_dataset"),
      datasetPath,
    });

    statusText.textContent = "数据检查完成。";
    showMessages(response.messages || []);
    showInspection(response.result_payload || {});
  } catch (message) {
    statusText.textContent = "数据检查失败。";
    showError(message);
    showMessages([]);
  } finally {
    inspectButton.disabled = false;
  }
}

async function runModel() {
  const datasetPath = datasetInput.value.trim();
  const formula = formulaInput.value.trim();
  const vcovType = vcovTypeInput.value;
  const weightsColumn = weightsColumnInput.value.trim();

  if (!runtimeBaseInput.value.trim() || !datasetPath || !formula) {
    showError({
      title: "输入不完整",
      code: "APP_INVALID_INPUT",
      text: "Runtime 端点、CSV 路径和公式都不能为空。",
      hint: "请补全输入后重试。",
    });
    statusText.textContent = "输入待修正。";
    return;
  }

  runButton.disabled = true;
  statusText.textContent = "运行中...";
  resetResultArea();

  try {
    const response = await fitModel({
      endpoint: runtimeEndpoint("/fit_model"),
      datasetPath,
      formula,
      vcovType,
      weightsColumn,
    });

    statusText.textContent =
      response.status === "success" ? "运行完成。" : "运行失败。";
    showMessages(response.messages || []);

    if (response.status !== "success") {
      showError(response.messages?.[0]);
      return;
    }

    const payload = response.result_payload || {};
    showWarnings(payload.warnings || []);
    showGlance(payload.glance);
    showSummary(payload.summary_text || "");
    showVcovLabel(payload.vcov_label || "");
    showTidy(payload.tidy || []);
  } catch (message) {
    statusText.textContent = "运行失败。";
    showError(message);
    showMessages([]);
    tidyTableBody.innerHTML = `
      <tr>
        <td colspan="5" class="empty-row">未能取得结构化结果。</td>
      </tr>
    `;
  } finally {
    runButton.disabled = false;
  }
}

chooseFileButton.addEventListener("click", () => {
  filePicker.click();
});

filePicker.addEventListener("change", () => {
  const file = filePicker.files?.[0];

  if (!file) {
    return;
  }

  if (file.path) {
    datasetInput.value = file.path;
    statusText.textContent = "已选择文件，可继续检查数据。";
    return;
  }

  datasetInput.value = file.name;
  statusText.textContent =
    "当前浏览器未暴露本地绝对路径；请确认路径输入已可被 Runtime 访问。";
});

inspectButton.addEventListener("click", inspectCurrentDataset);
resetResultArea();
runButton.addEventListener("click", runModel);
