import { Alert } from 'antd';
import type { Warning } from '../types/protocol';

interface WarningPanelProps {
  warnings: Warning[];
}

export function WarningPanel({ warnings }: WarningPanelProps) {
  if (!warnings.length) return null;
  return (
    <div style={{ marginBottom: 16 }}>
      {warnings.map((w, i) => (
        <Alert
          key={i}
          type="warning"
          message={w.title}
          description={w.detail}
          style={{ marginBottom: 8 }}
          showIcon
        />
      ))}
    </div>
  );
}
