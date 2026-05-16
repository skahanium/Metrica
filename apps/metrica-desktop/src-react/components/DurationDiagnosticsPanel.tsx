import React from 'react';
import { Card, Descriptions, Table, Typography } from 'antd';
import type { DurationDiagnostics, HazardRatioEntry } from '../types/protocol';

const { Text } = Typography;

/** 展示 `duration_cox` 的结构化 diagnostics 与 HR 表（消费 JSON 键）。 */
export function DurationDiagnosticsPanel({
  diagnostics,
  hazardRatios,
}: {
  diagnostics: DurationDiagnostics | undefined;
  hazardRatios?: HazardRatioEntry[];
}) {
  if (!diagnostics && !(hazardRatios && hazardRatios.length > 0)) return null;

  const bh = diagnostics?.baseline_hazard_summary;
  const preview = bh?.preview;

  return (
    <>
      {diagnostics && (
        <Card title="久期/Cox 诊断" size="small" style={{ marginTop: 12 }}>
          <Descriptions size="small" column={2} bordered>
            <Descriptions.Item label="样本量">{diagnostics.n_obs ?? '—'}</Descriptions.Item>
            <Descriptions.Item label="事件数">{diagnostics.n_events ?? '—'}</Descriptions.Item>
            <Descriptions.Item label="删失数">{diagnostics.n_censored ?? '—'}</Descriptions.Item>
            <Descriptions.Item label="删失比例">
              {diagnostics.censoring_fraction != null ? diagnostics.censoring_fraction.toFixed(3) : '—'}
            </Descriptions.Item>
            <Descriptions.Item label="并列处理">{diagnostics.risk_set_ties_method ?? '—'}</Descriptions.Item>
            <Descriptions.Item label="收敛">{diagnostics.converged === undefined ? '—' : String(diagnostics.converged)}</Descriptions.Item>
            <Descriptions.Item label="迭代次数">{diagnostics.iterations ?? '—'}</Descriptions.Item>
            <Descriptions.Item label="部分似然（对数）">
              {diagnostics.loglikelihood != null ? diagnostics.loglikelihood.toFixed(4) : '—'}
            </Descriptions.Item>
            <Descriptions.Item label="PH 检验（预留）" span={2}>
              {diagnostics.ph_diagnostics === null ? (
                <Text type="secondary">首期为 null；二期可填 Schoenfeld 等。</Text>
              ) : (
                <Text code>{JSON.stringify(diagnostics.ph_diagnostics)}</Text>
              )}
            </Descriptions.Item>
            <Descriptions.Item label="基准风险预览点数" span={2}>
              {bh?.n_event_times ?? '—'}
            </Descriptions.Item>
          </Descriptions>
          {preview && preview.length > 0 && (
            <Table
              style={{ marginTop: 12 }}
              size="small"
              pagination={false}
              dataSource={preview.map((row, i) => ({ ...row, key: i }))}
              columns={[
                { title: '事件时间', dataIndex: 'time', key: 't', render: (v: number) => v?.toFixed(4) },
                { title: '累积基准风险 H₀', dataIndex: 'cumulative_hazard', key: 'h', render: (v: number) => v?.toFixed(4) },
              ]}
            />
          )}
        </Card>
      )}
      {hazardRatios && hazardRatios.length > 0 && (
        <Card title="风险比（HR）与 95% 置信区间" size="small" style={{ marginTop: 12 }}>
          <Table
            size="small"
            pagination={false}
            dataSource={hazardRatios.map((r) => ({ ...r, key: r.term }))}
            columns={[
              { title: '项', dataIndex: 'term', key: 'term' },
              { title: 'HR', dataIndex: 'hr', key: 'hr', render: (v: number) => (v != null ? v.toFixed(4) : '—') },
              { title: 'CI 下限', dataIndex: 'ci_lower', key: 'lo', render: (v: number | null) => (v != null ? v.toFixed(4) : '—') },
              { title: 'CI 上限', dataIndex: 'ci_upper', key: 'hi', render: (v: number | null) => (v != null ? v.toFixed(4) : '—') },
            ]}
          />
          <Text type="secondary" style={{ display: 'block', marginTop: 8 }}>
            tidy 表中的 estimate 为 log(HR) 尺度；本表为 HR 与置信区间，便于与文献对照。
          </Text>
        </Card>
      )}
    </>
  );
}
