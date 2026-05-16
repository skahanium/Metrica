import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ResultBlock } from '../components/ResultBlock';
import type { ModelResult } from '../types/protocol';

// Mock echarts-for-react，避免 ECharts 在测试环境报错
vi.mock('echarts-for-react', () => ({
  default: () => <div data-testid="echarts-mock" />,
}));

const mockOlsResult: ModelResult = {
  glance: { model: 'ols', nobs: 100, dof: 97, metrics: { r2: 0.75 } },
  tidy: [
    { term: 'x1', estimate: 2.5, std_error: 0.3, statistic: 8.33, p_value: 0.001 },
  ],
  diagnostics: {},
  warnings: [],
};

const mockLogitResult: ModelResult = {
  glance: { model: 'logit', nobs: 200, dof: 197, metrics: { pseudo_r2: 0.45 } },
  tidy: [
    { term: 'x1', estimate: 1.2, std_error: 0.4, statistic: 3.0, p_value: 0.003 },
  ],
  diagnostics: {},
  warnings: [],
  odds_ratios: [
    { term: 'x1', odds_ratio: 3.32, ci_lower: 1.5, ci_upper: 7.3 },
  ],
};

const mockDidResult: ModelResult = {
  glance: { model: 'did', nobs: 500, dof: 496, metrics: {} },
  tidy: [
    { term: 'treat', estimate: 5.1, std_error: 1.2, statistic: 4.25, p_value: 0.0001 },
  ],
  diagnostics: {},
  warnings: [],
  treat_effect: 5.1,
  treat_effect_se: 1.2,
  treat_effect_pvalue: 0.0001,
  n_treated: 250,
  n_control: 250,
};

const mockSurveyResult: ModelResult = {
  glance: { model: 'survey_ols', nobs: 1000, dof: 995, metrics: {} },
  tidy: [
    { term: 'x1', estimate: 0.8, std_error: 0.1, statistic: 8.0, p_value: 0.0001 },
  ],
  diagnostics: {},
  warnings: [],
  design_effects: [
    { term: 'x1', deff: 2.5, n_eff: 400, srs_se: 0.05, survey_se: 0.1 },
  ],
  strata_summary: [
    { stratum: 'strata1', n: 500, sum_weights: 10000, mean_weight: 20, min_weight: 5, max_weight: 50 },
    { stratum: 'strata2', n: 500, sum_weights: 12000, mean_weight: 24, min_weight: 8, max_weight: 60 },
  ],
};

const mockGmmResult: ModelResult = {
  glance: { model: 'gmm_linear', nobs: 50, dof: 47, metrics: { j_stat: 2.1, j_df: 1 } },
  tidy: [
    { term: 'x1', estimate: 1.0, std_error: 0.2, statistic: 5.0, p_value: 0.01 },
  ],
  diagnostics: {
    j_statistic: 2.1,
    j_df: 1,
    j_pvalue: 0.15,
    n_moments: 3,
    n_params: 2,
    gmm_weight: 'two_step',
    weight_matrix_description: "(Z'Z)^{-1} 起步",
    exactly_identified: false,
    iterations: 1,
  },
  warnings: [],
};

/** ARCH 结果块：glance.model 须匹配 `ARCH(` 以挂载 VolatilitySummaryPanel */
const mockArchResult: ModelResult = {
  glance: {
    model: 'ARCH(2)',
    nobs: 400,
    dof: 0,
    metrics: {
      loglik: -612.34,
      aic: 1230.5,
      bic: 1255.2,
      arch_order: 2,
      persistence: 0.42,
      unconditional_variance: 1.05,
    },
  },
  tidy: [
    { term: 'mu', estimate: 0.01, std_error: null, statistic: null, p_value: null },
    { term: 'omega', estimate: 0.05, std_error: null, statistic: null, p_value: null },
    { term: 'alpha_1', estimate: 0.2, std_error: null, statistic: null, p_value: null },
  ],
  diagnostics: {
    converged: true,
    iterations: 120,
    optimizer: 'NelderMead',
    loglik: -612.34,
    persistence: 0.42,
    unconditional_variance: 1.05,
    conditional_volatility_preview: [0.12, 0.15, 0.11],
    volatility_length: 400,
    arch_order: 2,
    failure_code: null,
  },
  warnings: [],
};

describe('ResultBlock', () => {
  it('renders command text and OLS glance for ols model', () => {
    render(
      <ResultBlock command="ols(y ~ x1)" result={mockOlsResult} />,
    );
    expect(screen.getByText(/ols\(y ~ x1\)/)).toBeDefined();
  });

  it('renders DiscreteGlanceCards for logit model', () => {
    render(
      <ResultBlock command="logit(y ~ x1)" result={mockLogitResult} />,
    );
    // DiscreteGlanceCards 内容 — 通过 result prop 渲染
    expect(screen.getByText('模型摘要')).toBeDefined();
  });

  it('renders DIDResultCards for did model', () => {
    render(
      <ResultBlock command="did(y ~ treat)" result={mockDidResult} />,
    );
    expect(screen.getByText('DID 处理效应')).toBeDefined();
  });

  it('renders SurveyDesignPanel for survey model', () => {
    render(
      <ResultBlock command="survey_ols(y ~ x1)" result={mockSurveyResult} />,
    );
    expect(screen.getByText('抽样设计概览')).toBeDefined();
  });

  it('renders GmmDiagnosticsPanel for gmm_linear model', () => {
    render(
      <ResultBlock command="gmm y x1 x2, endogenous(x1) instruments(z1 z2)" result={mockGmmResult} />,
    );
    expect(screen.getByText('GMM 与序列相关诊断')).toBeDefined();
    expect(screen.getByText('Hansen J')).toBeDefined();
  });

  it('matches snapshot for ARCH result with volatility diagnostics panel', () => {
    const { asFragment } = render(
      <ResultBlock command="arch ret, time(time) arch(2)" result={mockArchResult} />,
    );
    expect(screen.getByText('波动率模型诊断')).toBeDefined();
    expect(screen.getByText('ARCH(2)')).toBeDefined();
    expect(asFragment()).toMatchSnapshot();
  });

  it('passes result prop to sub-components, not global store', () => {
    // 两个不同结果渲染各自的历史块，不应互相干扰
    const { unmount } = render(
      <ResultBlock command="cmd1" result={mockOlsResult} />,
    );
    // OLS 结果不应包含 DID 内容
    expect(screen.queryByText('DID 处理效应')).toBeNull();
    unmount();

    render(
      <ResultBlock command="cmd2" result={mockDidResult} />,
    );
    // DID 结果不应包含 DiscreteGlanceCards
    expect(screen.queryByText('模型摘要')).toBeNull();
    expect(screen.getByText('DID 处理效应')).toBeDefined();
  });
});
