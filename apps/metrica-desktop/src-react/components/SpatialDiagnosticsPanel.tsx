import { Card, Descriptions, Typography } from 'antd';
import type { SpatialDiagnostics } from '../types/protocol';

const { Text } = Typography;

/** 展示空间模型的结构化 diagnostics（消费 JSON 键，不解析摘要文本）。 */
export function SpatialDiagnosticsPanel({ diagnostics }: { diagnostics: SpatialDiagnostics | undefined }) {
  if (!diagnostics) return null;

  const rsr = diagnostics.row_standardized_report;
  const moranZ = diagnostics.moran_z;
  const moranVar = diagnostics.moran_var;
  const direct = diagnostics.direct_effects;
  const indirect = diagnostics.indirect_effects;
  const total = diagnostics.total_effects;

  const renderEffects = (effects: Record<string, number> | null | undefined) => {
    if (!effects || Object.keys(effects).length === 0) return '未计算/暂不支持';
    return Object.entries(effects)
      .map(([name, value]) => `${name}: ${value}`)
      .join('；');
  };

  return (
    <Card title="空间诊断" size="small" style={{ marginTop: 12 }}>
      <Descriptions size="small" column={2} bordered>
        <Descriptions.Item label="权重文件" span={2}>
          <Text code>{diagnostics.spatial_weights_basename ?? '—'}</Text>
        </Descriptions.Item>
        <Descriptions.Item label="n（对齐后）">{diagnostics.n_obs ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="非零边（存储）">{diagnostics.n_nonzero_links ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="对称性提示" span={2}>
          {diagnostics.symmetry_hint ?? '—'}
        </Descriptions.Item>
        <Descriptions.Item label="行标准化（请求）">{rsr?.requested === undefined ? '—' : String(rsr.requested)}</Descriptions.Item>
        <Descriptions.Item label="行标准化（已应用）">{rsr?.applied === undefined ? '—' : String(rsr.applied)}</Descriptions.Item>
        <Descriptions.Item label="行和 min">{rsr?.row_sums_min ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="行和 max">{rsr?.row_sums_max ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="Moran I（残差）">{diagnostics.moran_i ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="Moran E(I)">{diagnostics.moran_ei ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="Moran Var">{moranVar ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="Moran z">{moranZ ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="Moran p">{diagnostics.moran_pvalue ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="效应算法">{diagnostics.effects_method ?? '未计算/暂不支持'}</Descriptions.Item>
        <Descriptions.Item label="ρ（SAR）">{diagnostics.rho ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="λ（SEM）">{diagnostics.lambda ?? '—'}</Descriptions.Item>
        <Descriptions.Item label="直接效应" span={2}>{renderEffects(direct)}</Descriptions.Item>
        <Descriptions.Item label="间接效应" span={2}>{renderEffects(indirect)}</Descriptions.Item>
        <Descriptions.Item label="总效应" span={2}>{renderEffects(total)}</Descriptions.Item>
      </Descriptions>
      {(direct == null || indirect == null || total == null) && (
        <Text type="secondary" style={{ display: 'block', marginTop: 8 }}>
          直接/间接/总效应未返回时，表示当前模型或估计器暂不支持该分解。
        </Text>
      )}
    </Card>
  );
}
