import type { FitModelRunRecord, ModelResult, RunRecord } from '../types/protocol';
import { isFitModelRun } from '../types/protocol';

const DISCRETE_MODELS = new Set([
  'logit', 'probit', 'poisson', 'ordered_logit', 'multinomial_logit', 'negbin',
]);

const CAUSAL_MODELS = new Set(['did', 'event_study', 'ipw', 'psm', 'aipw']);

export type CompareFamily = 'discrete' | 'causal';

export function detectCompareFamily(glanceModel: string | undefined): CompareFamily | null {
  if (!glanceModel) return null;
  if (DISCRETE_MODELS.has(glanceModel)) return 'discrete';
  if (CAUSAL_MODELS.has(glanceModel)) return 'causal';
  return null;
}

function getSummary(r: FitModelRunRecord): ModelResult | null {
  return r.result_summary ?? null;
}

/** 从 run 历史按 ID 收集 fit_model 成功记录；失败时返回错误文案（CLI warning 用） */
export function resolveCompareRuns(
  runHistory: RunRecord[],
  runIds: string[],
): { ok: true; runs: FitModelRunRecord[]; family: CompareFamily } | { ok: false; error: string } {
  const byId = new Map(runHistory.map((r) => [r.run_id, r]));
  const resolved: FitModelRunRecord[] = [];
  for (const id of runIds) {
    const raw = byId.get(id);
    if (!raw) {
      return { ok: false, error: `运行记录不存在：${id}` };
    }
    if (!isFitModelRun(raw)) {
      return { ok: false, error: `运行 ${id} 不是 fit_model，无法参与对比。` };
    }
    if (raw.status !== 'success') {
      return { ok: false, error: `运行 ${id} 未成功完成，无法参与对比。` };
    }
    if (!raw.result_summary) {
      return { ok: false, error: `运行 ${id} 缺少结构化结果摘要（result_summary）。` };
    }
    resolved.push(raw);
  }
  if (resolved.length < 2) {
    return { ok: false, error: '模型对比至少需要两个 run_id。' };
  }
  const path0 = resolved[0].dataset_ref.path;
  if (!resolved.every((r) => r.dataset_ref.path === path0)) {
    return { ok: false, error: '所选运行的数据集路径不一致，无法对比。' };
  }
  const m0 = getSummary(resolved[0])?.glance?.model;
  const fam = detectCompareFamily(m0);
  if (!fam) {
    return {
      ok: false,
      error: `当前 v1 不支持对模型族「${m0 ?? '未知'}」做 CLI 对比；支持离散（logit/probit/poisson/ordered_logit/multinomial_logit/negbin）与因果（did/event_study/ipw/psm/aipw）。`,
    };
  }
  for (const r of resolved) {
    const m = getSummary(r)?.glance?.model;
    const f = detectCompareFamily(m);
    if (f !== fam) {
      return { ok: false, error: '所选运行不属于同一可对比模型族（离散 vs 因果混用）。' };
    }
  }
  return { ok: true, runs: resolved, family: fam };
}

function num(v: unknown): number | null {
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string' && v.trim() !== '' && !Number.isNaN(Number(v))) return Number(v);
  return null;
}

export function buildDiscreteComparisonRows(runs: FitModelRunRecord[]): Array<Record<string, string | number | null>> {
  return runs.map((r) => {
    const g = r.result_summary!.glance;
    const d = r.result_summary!.diagnostics as { loglikelihood?: number; aic?: number; bic?: number } | undefined;
    const ll = (r.result_summary as ModelResult).loglikelihood
      ?? d?.loglikelihood
      ?? (g.metrics && (g.metrics as Record<string, number>).loglikelihood)
      ?? (g.metrics && (g.metrics as Record<string, number>).loglik)
      ?? null;
    return {
      run_id: r.run_id,
      model: g.model,
      nobs: g.nobs,
      loglikelihood: ll,
      aic: d?.aic ?? (g.metrics && (g.metrics as Record<string, number>).aic) ?? null,
      bic: d?.bic ?? (g.metrics && (g.metrics as Record<string, number>).bic) ?? null,
    };
  });
}

export function buildCausalComparisonRows(runs: FitModelRunRecord[]): Array<Record<string, string | number | null>> {
  return runs.map((r) => {
    const res = r.result_summary!;
    return {
      run_id: r.run_id,
      model: res.glance.model,
      nobs: res.glance.nobs,
      ate: num(res.ate),
      ate_se: num(res.ate_se),
      att: num(res.att),
      att_se: num(res.att_se),
      atu: num(res.atu),
      n_treated: num(res.n_treated),
      n_control: num(res.n_control),
    };
  });
}
