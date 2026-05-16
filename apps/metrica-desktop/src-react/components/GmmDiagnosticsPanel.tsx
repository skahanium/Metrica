import React from 'react';
import { Descriptions, Typography, Tag } from 'antd';
import type { GmmDiagnostics } from '../types/protocol';

const { Text } = Typography;

export interface GmmDiagnosticsPanelProps {
  diagnostics: GmmDiagnostics;
}

/**
 * 线性 GMM 结构化诊断（Hansen / Sargan J、矩条件与权重说明），只读展示 Runtime 载荷。
 */
export const GmmDiagnosticsPanel: React.FC<GmmDiagnosticsPanelProps> = ({ diagnostics }) => {
  const fmt = (v: number | null | undefined) =>
    v === null || v === undefined || Number.isNaN(v) ? '—' : String(v);

  return (
    <div style={{ marginTop: 16 }}>
      <Text strong style={{ display: 'block', marginBottom: 8 }}>
        GMM 与序列相关诊断
      </Text>
      <Descriptions size="small" column={1} bordered>
        <Descriptions.Item label="Hansen J">
          {fmt(diagnostics.j_statistic)}
        </Descriptions.Item>
        <Descriptions.Item label="自由度 (L−k)">
          {fmt(diagnostics.j_df as number | undefined)}
        </Descriptions.Item>
        <Descriptions.Item label="J 检验 p 值">
          {diagnostics.j_pvalue === null || diagnostics.j_pvalue === undefined
            ? '—'
            : fmt(diagnostics.j_pvalue)}
        </Descriptions.Item>
        <Descriptions.Item label="矩条件数 L">
          {fmt(diagnostics.n_moments)}
        </Descriptions.Item>
        <Descriptions.Item label="参数个数 k">
          {fmt(diagnostics.n_params)}
        </Descriptions.Item>
        <Descriptions.Item label="权重步长">
          {diagnostics.gmm_weight ?? '—'}
        </Descriptions.Item>
        <Descriptions.Item label="权重矩阵">
          <Text type="secondary" style={{ whiteSpace: 'pre-wrap' }}>
            {diagnostics.weight_matrix_description ?? '—'}
          </Text>
        </Descriptions.Item>
        {diagnostics.exactly_identified !== undefined && (
          <Descriptions.Item label="恰识别">
            {diagnostics.exactly_identified ? '是（J 检验不适用）' : '否'}
          </Descriptions.Item>
        )}
        {diagnostics.iterations !== undefined && (
          <Descriptions.Item label="迭代次数">
            {String(diagnostics.iterations)}
          </Descriptions.Item>
        )}
        {diagnostics.ar1_test !== undefined && (
          <Descriptions.Item label="AR(1) 检验（差分残差）">
            z = {fmt(diagnostics.ar1_test?.statistic)}，p = {fmt(diagnostics.ar1_test?.pvalue)}
          </Descriptions.Item>
        )}
        {diagnostics.ar2_test !== undefined && (
          <Descriptions.Item label="AR(2) 检验（差分残差）">
            z = {fmt(diagnostics.ar2_test?.statistic)}，p = {fmt(diagnostics.ar2_test?.pvalue)}
          </Descriptions.Item>
        )}
        {(diagnostics.n_groups !== undefined || diagnostics.n_periods !== undefined) && (
          <Descriptions.Item label="面板规模">
            个体 {fmt(diagnostics.n_groups)}，时期 {fmt(diagnostics.n_periods)}，差分样本{' '}
            {fmt(diagnostics.n_obs_diff)}
          </Descriptions.Item>
        )}
        {diagnostics.instrument_lags !== undefined && diagnostics.instrument_lags.length >= 2 && (
          <Descriptions.Item label="工具滞后层">
            [{diagnostics.instrument_lags[0]}, {diagnostics.instrument_lags[1]}]
          </Descriptions.Item>
        )}
        {(diagnostics as any).dpgmm_style !== undefined && (
          <Descriptions.Item label="估计方法">
            <Tag color={(diagnostics as any).dpgmm_style === 'system' ? 'green' : 'blue'}>
              {(diagnostics as any).dpgmm_style === 'system' ? 'System GMM' : 'Difference GMM'}
            </Tag>
          </Descriptions.Item>
        )}
        {(diagnostics as any).diff_hansen !== undefined && (
          <>
            <Descriptions.Item label="Diff-Hansen C">
              {(diagnostics as any).diff_hansen.c_statistic?.toFixed(4) ?? '—'}
            </Descriptions.Item>
            <Descriptions.Item label="Diff-Hansen df">
              {(diagnostics as any).diff_hansen.df ?? '—'}
            </Descriptions.Item>
            <Descriptions.Item label="Diff-Hansen p">
              {(diagnostics as any).diff_hansen.pvalue?.toFixed(4) ?? '—'}
            </Descriptions.Item>
          </>
        )}
      </Descriptions>
    </div>
  );
};
