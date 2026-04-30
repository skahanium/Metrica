function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

export function formatNumber(value) {
  if (value === null || value === undefined || value === "") {
    return "—";
  }

  if (typeof value !== "number" || Number.isNaN(value)) {
    return escapeHtml(value);
  }

  return value.toFixed(4);
}

function formatMetricLabel(label) {
  const knownLabels = {
    r2: "R²",
    adj_r2: "调整 R²",
    sigma: "Sigma",
    rss: "RSS",
    tss: "TSS",
  };

  return knownLabels[label] || label;
}

export function renderMessagesMarkup(messages = []) {
  if (!messages.length) {
    return "";
  }

  return messages
    .map((message) => {
      const hint = message.hint
        ? `<p class="message-hint">${escapeHtml(message.hint)}</p>`
        : "";

      return `
        <article class="message-card message-card-${escapeHtml(message.level || "info")}">
          <div class="message-head">
            <strong>${escapeHtml(message.text || "未提供消息内容。")}</strong>
            <span>${escapeHtml(message.code || "")}</span>
          </div>
          ${hint}
        </article>
      `;
    })
    .join("");
}

export function renderError(message) {
  if (!message) {
    return "";
  }

  const hint = message.hint
    ? `<p class="message-hint">${escapeHtml(message.hint)}</p>`
    : "";
  return `
    <div class="message-head">
      <strong>${escapeHtml(message.title || "运行失败")}</strong>
      <span>${escapeHtml(message.code || "")}</span>
    </div>
    <p>${escapeHtml(message.text || "未知错误。")}</p>
    ${hint}
  `;
}

export function renderWarnings(warnings = []) {
  if (!warnings.length) {
    return `
      <article class="empty-state">
        <strong>当前没有结构化 warning。</strong>
        <p>如存在删样或教学提示，Runtime 会在这里返回。</p>
      </article>
    `;
  }

  return warnings
    .map(
      (warning) => `
        <article class="warning-card">
          <div class="warning-head">
            <strong>${escapeHtml(warning.title || warning.code || "提示")}</strong>
            <span>${escapeHtml(warning.code || "")}</span>
          </div>
          <p>${escapeHtml(warning.detail || warning.text || "")}</p>
          ${warning.hint ? `<p class="warning-hint">${escapeHtml(warning.hint)}</p>` : ""}
        </article>
      `
    )
    .join("");
}

export function renderGlance(glance) {
  if (!glance) {
    return `
      <article class="empty-state">
        <strong>结果尚未生成。</strong>
        <p>运行模型后会在这里显示 <code>glance</code> 摘要。</p>
      </article>
    `;
  }

  const metrics = glance.metrics || {};
  const core = [
    ["模型", glance.model],
    ["样本量", glance.nobs],
    ["自由度", glance.dof],
  ]
    .map(
      ([label, value]) => `
        <div class="glance-card">
          <span>${escapeHtml(label)}</span>
          <strong>${formatNumber(value)}</strong>
        </div>
      `
    )
    .join("");

  const metricMarkup = Object.entries(metrics)
    .map(
      ([label, value]) => `
        <div class="glance-card metric-card">
          <span>${escapeHtml(formatMetricLabel(label))}</span>
          <strong>${formatNumber(value)}</strong>
        </div>
      `
    )
    .join("");

  return `
    <section class="glance-section">
      <div class="glance-grid">${core}</div>
      <div class="glance-grid metrics-grid">${metricMarkup}</div>
    </section>
  `;
}

export function renderTidyRows(rows = []) {
  if (!rows.length) {
    return `
      <tr>
        <td colspan="5" class="empty-row">结果中没有系数行。</td>
      </tr>
    `;
  }

  return rows
    .map(
      (row) => `
        <tr>
          <td>${escapeHtml(row.name)}</td>
          <td>${formatNumber(row.estimate)}</td>
          <td>${formatNumber(row.stderror)}</td>
          <td>${formatNumber(row.statistic)}</td>
          <td>${formatNumber(row.pvalue)}</td>
        </tr>
      `
    )
    .join("");
}

export function renderVcovLabel(vcovLabel) {
  if (!vcovLabel) {
    return "";
  }

  return `
    <article class="vcov-card">
      <span>协方差</span>
      <strong>${escapeHtml(vcovLabel)}</strong>
    </article>
  `;
}

export function renderWarningsMarkup(warnings = []) {
  return renderWarnings(warnings);
}

export function renderGlanceMarkup(glance) {
  return renderGlance(glance);
}

export function renderTidyMarkup(rows = []) {
  if (!rows.length) {
    return `
      <article class="empty-state">
        <strong>系数表为空。</strong>
        <p>成功响应中的 <code>tidy</code> 行会在这里展示。</p>
      </article>
    `;
  }

  return `
    <table class="tidy-table">
      <thead>
        <tr>
          <th>参数</th>
          <th>估计值</th>
          <th>标准误</th>
          <th>统计量</th>
          <th>p 值</th>
        </tr>
      </thead>
      <tbody>${renderTidyRows(rows)}</tbody>
    </table>
  `;
}

export function renderDatasetSummary(inspection) {
  if (!inspection) {
    return `
      <article class="empty-state">
        <strong>尚未检查数据集。</strong>
        <p>点击"检查数据"后，这里会显示列摘要。</p>
      </article>
    `;
  }

  const summary = inspection.dataset_summary || {};
  const columns = inspection.columns || [];
  const columnItems = columns
    .map(
      (column) => `
        <tr>
          <td>${escapeHtml(column.name)}</td>
          <td>${escapeHtml(column.inferred_type)}</td>
          <td>${formatNumber(column.missing_count)}</td>
        </tr>
      `
    )
    .join("");

  return `
    <section class="dataset-summary">
      <div class="glance-grid">
        <div class="glance-card">
          <span>行数</span>
          <strong>${formatNumber(summary.row_count)}</strong>
        </div>
        <div class="glance-card">
          <span>列数</span>
          <strong>${formatNumber(summary.column_count)}</strong>
        </div>
      </div>
      <table class="tidy-table">
        <thead>
          <tr>
            <th>列名</th>
            <th>推断类型</th>
            <th>Missing</th>
          </tr>
        </thead>
        <tbody>${columnItems}</tbody>
      </table>
    </section>
  `;
}

export function renderPreviewRows(rows = [], columnOrder = []) {
  if (!rows.length) {
    return `
      <article class="empty-state">
        <strong>暂无预览行。</strong>
        <p>Runtime 返回前几行后，这里会显示表格预览。</p>
      </article>
    `;
  }

  const columns = columnOrder.length ? columnOrder : Object.keys(rows[0]);
  const head = columns.map((column) => `<th>${escapeHtml(column)}</th>`).join("");
  const body = rows
    .map(
      (row) => `
        <tr>
          ${columns
            .map((column) => `<td>${formatNumber(row[column])}</td>`)
            .join("")}
        </tr>
      `
    )
    .join("");

  return `
    <table class="tidy-table">
      <thead>
        <tr>${head}</tr>
      </thead>
      <tbody>${body}</tbody>
    </table>
  `;
}

export function renderSummaryText(summaryText) {
  if (!summaryText) {
    return `
      <article class="empty-state">
        <strong>尚未生成摘要。</strong>
        <p>运行模型后会在这里显示文本摘要。</p>
      </article>
    `;
  }

  return `
    <article class="summary-card">
      <strong>模型摘要</strong>
      <p>${escapeHtml(summaryText)}</p>
    </article>
  `;
}
