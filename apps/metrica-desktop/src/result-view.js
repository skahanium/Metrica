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

function renderDiagnosticBlock(title, description, fields) {
  const cards = fields
    .map(
      ([label, value]) => `
        <div class="glance-card">
          <span>${escapeHtml(label)}</span>
          <strong>${formatNumber(value)}</strong>
        </div>
      `
    )
    .join("");

  return `
    <article class="diagnostics-block">
      <h4>${escapeHtml(title)}</h4>
      <p class="diag-desc">${escapeHtml(description)}</p>
      <div class="glance-grid diagnostics-grid">${cards}</div>
    </article>
  `;
}

export function renderDiagnostics(diagnostics) {
  if (!diagnostics) {
    return `
      <article class="empty-state">
        <strong>暂无诊断结果。</strong>
        <p>运行模型后会在这里显示结构化诊断。</p>
      </article>
    `;
  }

  const blocks = [];

  // VIF
  const vifRows = Array.isArray(diagnostics.vif) ? diagnostics.vif : [];
  if (vifRows.length) {
    const vifTable = `
      <table class="tidy-table diagnostics-table">
        <thead><tr><th>变量</th><th>VIF</th></tr></thead>
        <tbody>
          ${vifRows.map((row) => `<tr><td>${escapeHtml(row.name)}</td><td>${formatNumber(row.vif)}</td></tr>`).join("")}
        </tbody>
      </table>
    `;
    blocks.push(`<article class="diagnostics-block"><h4>VIF（多重共线性）</h4><p class="diag-desc">VIF > 10 表示存在严重共线性。</p>${vifTable}</article>`);
  }

  // 辅助：构建检验卡片块
  const testBlocks = [
    {
      key: "breusch_pagan",
      title: "Breusch-Pagan（异方差）",
      desc: "H₀: 同方差。p < 0.05 表示存在异方差。",
      fields: (d) => [["LM 统计量", d.statistic], ["p 值", d.pvalue], ["自由度", d.dof]],
    },
    {
      key: "white_test",
      title: "White 检验（异方差）",
      desc: "含二次项辅助回归。H₀: 同方差。",
      fields: (d) => [["LM 统计量", d.statistic], ["p 值", d.pvalue], ["自由度", d.dof]],
    },
    {
      key: "durbin_watson",
      title: "Durbin-Watson（一阶自相关）",
      desc: "DW ≈ 2 表示无自相关，< 2 为正自相关，> 2 为负自相关。",
      fields: (d) => [["DW 统计量", d.statistic], ["p 值（正态近似）", d.pvalue]],
    },
    {
      key: "breusch_godfrey",
      title: "Breusch-Godfrey（2 阶自相关）",
      desc: "H₀: 无直到 2 阶的自相关。",
      fields: (d) => [["LM 统计量", d.statistic], ["p 值", d.pvalue], ["自由度", d.dof]],
    },
    {
      key: "reset_test",
      title: "RESET 检验（模型设定）",
      desc: "H₀: 模型设定正确。添加 ŷ² 与 ŷ³ 检验遗漏的非线性。",
      fields: (d) => [["F 统计量", d.statistic], ["p 值", d.pvalue], ["分子 df", d.df_num], ["分母 df", d.df_den]],
    },
    {
      key: "jarque_bera",
      title: "Jarque-Bera（残差正态性）",
      desc: "H₀: 残差服从正态分布。",
      fields: (d) => [["JB 统计量", d.statistic], ["p 值", d.pvalue], ["偏度", d.skewness], ["峰度", d.kurtosis]],
    },
  ];

  for (const tb of testBlocks) {
    const data = diagnostics[tb.key];
    if (data) {
      blocks.push(renderDiagnosticBlock(tb.title, tb.desc, tb.fields(data)));
    }
  }

  return `<section class="diagnostics-section">${blocks.join("")}</section>`;
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
