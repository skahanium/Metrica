import { Card, Typography } from 'antd';
import { useModelStore } from '../stores/modelStore';

export function EventStudyPlot() {
  const lastResult = useModelStore((s) => s.lastResult);
  if (!lastResult || lastResult.glance.model !== 'event_study') return null;

  const coefs = lastResult.period_coefficients || [];
  const ses = lastResult.period_stderrors || [];
  const labels = lastResult.period_labels || [];
  const pval = lastResult.pre_trend_pvalue;
  const supported = lastResult.parallel_trends_supported;

  return (
    <Card size="small" title="事件研究" style={{ marginBottom: 16 }}>
      <Typography.Paragraph>
        事前趋势联合 F 检验 p = {pval?.toFixed(4)}。
        {supported
          ? ' 未拒绝平行趋势假设。'
          : ' 拒绝平行趋势假设，处理效应估计可能偏误。'}
      </Typography.Paragraph>
      <div style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
          <thead>
            <tr style={{ borderBottom: '2px solid #ddd' }}>
              <th style={{ padding: 4 }}>时期</th>
              <th style={{ padding: 4 }}>系数</th>
              <th style={{ padding: 4 }}>SE</th>
              <th style={{ padding: 4 }}>CI 下限</th>
              <th style={{ padding: 4 }}>CI 上限</th>
            </tr>
          </thead>
          <tbody>
            {coefs.map((c: number, i: number) => (
              <tr key={labels[i]} style={{
                borderBottom: '1px solid #eee',
                background: labels[i] === '-1' ? '#fff7e6' : undefined,
              }}>
                <td style={{ padding: 4, fontWeight: labels[i] === '-1' ? 'bold' : undefined }}>
                  {labels[i] === '-1' ? `${labels[i]} (基准)` : labels[i]}
                </td>
                <td style={{ padding: 4 }}>{c?.toFixed(4)}</td>
                <td style={{ padding: 4 }}>{ses[i]?.toFixed(4)}</td>
                <td style={{ padding: 4 }}>{(c - 1.96 * (ses[i] || 0)).toFixed(4)}</td>
                <td style={{ padding: 4 }}>{(c + 1.96 * (ses[i] || 0)).toFixed(4)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </Card>
  );
}
