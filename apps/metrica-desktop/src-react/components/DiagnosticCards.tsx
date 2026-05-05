import { Card, Descriptions, Tag } from 'antd';
import { useModelStore } from '../stores/modelStore';
import type { DiagnosticResult, DiscreteDiagnostics, OLSDiagnostics, PanelDiagnostics } from '../types/protocol';
import { EmptyState } from './EmptyState';

type OlsDiagnosticKey = Exclude<keyof OLSDiagnostics, 'vif'>;

const OLS_DIAG_META: Array<{ key: OlsDiagnosticKey; label: string; description: string }> = [
  { key: 'breusch_pagan', label: 'Breusch-Pagan 异方差检验', description: 'H0: 同方差' },
  { key: 'white_test', label: 'White 异方差检验', description: 'H0: 同方差' },
  { key: 'durbin_watson', label: 'Durbin-Watson 自相关检验', description: 'H0: 无一阶自相关' },
  { key: 'breusch_godfrey', label: 'Breusch-Godfrey 自相关检验', description: 'H0: 无自相关' },
  { key: 'reset_test', label: 'RESET 模型设定检验', description: 'H0: 模型设定正确' },
  { key: 'jarque_bera', label: 'Jarque-Bera 正态性检验', description: 'H0: 残差正态' },
];

const PANEL_DIAG_META: Array<{ key: keyof PanelDiagnostics; label: string; description: string }> = [
  { key: 'hausman', label: 'Hausman 检验', description: 'H0: RE 一致；小 p 值倾向 FE' },
  { key: 'fixed_effect_f', label: '固定效应 F 检验', description: 'H0: 个体效应为零（混合 OLS）' },
  { key: 'breusch_pagan_lm', label: 'Breusch-Pagan LM 检验', description: 'H0: 无随机效应（混合 OLS）' },
];

function isPanelDiagnostics(d: OLSDiagnostics | PanelDiagnostics | DiscreteDiagnostics): d is PanelDiagnostics {
  return 'hausman' in d || 'fixed_effect_f' in d || 'breusch_pagan_lm' in d;
}

function isDiscreteDiagnostics(d: OLSDiagnostics | PanelDiagnostics | DiscreteDiagnostics): d is DiscreteDiagnostics {
  return 'converged' in d || 'iterations' in d || 'pseudo_r2' in d || 'aic' in d;
}

function DiagCard({ label, description, result }: { label: string; description: string; result?: DiagnosticResult }) {
  if (!result || result.available === false) {
    return (
      <Card size="small" title={label} style={{ marginBottom: 8 }}>
        <Tag color="default">不可用</Tag>
        <span style={{ color: '#8c8c8c', marginLeft: 8 }}>{result?.note ?? '当前数据集不满足检验条件。'}</span>
      </Card>
    );
  }
  return (
    <Card size="small" title={label} style={{ marginBottom: 8 }}>
      <Descriptions size="small" column={3}>
        <Descriptions.Item label="统计量">{result.statistic?.toFixed(4)}</Descriptions.Item>
        {result.dof != null && <Descriptions.Item label="自由度">{result.dof}</Descriptions.Item>}
        <Descriptions.Item label="p 值">{result.pvalue?.toFixed(4)}</Descriptions.Item>
        <Descriptions.Item label="说明">{description}</Descriptions.Item>
      </Descriptions>
    </Card>
  );
}

export function DiagnosticCards() {
  const lastResult = useModelStore((s) => s.lastResult);
  if (!lastResult) return <EmptyState title="尚未运行模型" />;

  const diag = lastResult.diagnostics;
  if (!diag) return <EmptyState title="无诊断结果" />;

  if (isDiscreteDiagnostics(diag)) {
    return <EmptyState title="离散模型诊断" description="GLM 模型使用 likelihood-based 诊断（AIC/BIC/LR 检验）。" />;
  }

  if (isPanelDiagnostics(diag)) {
    return (
      <div>
        {PANEL_DIAG_META.map(({ key, label, description }) => (
          <DiagCard key={key} label={label} description={description} result={diag[key]} />
        ))}
      </div>
    );
  }

  return (
    <div>
      {OLS_DIAG_META.map(({ key, label, description }) => (
        <DiagCard key={key} label={label} description={description} result={diag[key]} />
      ))}
    </div>
  );
}
